#include <stdint.h>

#include "softcpu_regs.h"

#define FDD_SLOT_A 3
#define FDD_SLOT_B 4

static void fdd_handle_request(int drive, uint32_t lba, int is_write)
{
    // Clear pending immediately — we've consumed this request.
    // After sd_ack deasserts, the WD1793 fires a new sd_rd within ~3
    // clk_sys cycles for the next chunk (1024-byte sectors = 2x512).
    // If pending is still set when the new sd_rd arrives, it's lost.
    *FDD_CTRL = drive ? FDD_CTRL_CLR_PENDING2 : FDD_CTRL_CLR_PENDING1;

    uint16_t slot_id = drive ? FDD_SLOT_B : FDD_SLOT_A;
    uint32_t sd_ack_bit = drive ? 2 : 1;

    if (is_write) {
        // Assert sd_ack — WD1793 buffer already has the data
        *FDD_SD_ACK = sd_ack_bit;

        // Read 512 bytes from WD1793 buffer, pack into bridgeram.
        // Hardware auto-increments sd_buff_addr on each DIN read
        // and bram_addr on each WDATA write.
        *FDD_SD_BUFF_ADDR = 0;
        *FDD_BRAM_ADDR = 0;
        for (int i = 0; i < 128; i++) {
            uint32_t word = 0;
            for (int b = 0; b < 4; b++) {
                word |= (*FDD_SD_BUFF_DIN & 0xFFu) << (24 - b * 8);
            }
            *FDD_BRAM_WDATA = word;
        }

        // Trigger APF DMA write
        *FDD_TDS_ID = slot_id;
        *FDD_TDS_OFFSET = lba << 9;
        *FDD_TDS_TRIGGER = 2; // write
        while (!(*FDD_STATUS & FDD_ST_TDS_DONE))
            ;

        // Deassert sd_ack
        *FDD_SD_ACK = 0;
    } else {
        // Trigger APF DMA read
        *FDD_TDS_ID = slot_id;
        *FDD_TDS_OFFSET = lba << 9;
        *FDD_TDS_TRIGGER = 1; // read
        while (!(*FDD_STATUS & FDD_ST_TDS_DONE))
            ;

        // Assert sd_ack — required for sd_buff writes to WD1793
        *FDD_SD_ACK = sd_ack_bit;

        // Transfer 512 bytes from bridgeram to WD1793 buffer.
        // Hardware auto-increments bram_addr on each RDATA read.
        *FDD_BRAM_ADDR = 0;
        for (int i = 0; i < 128; i++) {
            uint32_t word = *FDD_BRAM_RDATA;
            *FDD_SD_BUFF_WR = ((uint32_t) (i * 4) << 0) | ((word & 0xFFu) << 16);
            *FDD_SD_BUFF_WR = ((uint32_t) (i * 4 + 1) << 0) | (((word >> 8) & 0xFFu) << 16);
            *FDD_SD_BUFF_WR = ((uint32_t) (i * 4 + 2) << 0) | (((word >> 16) & 0xFFu) << 16);
            *FDD_SD_BUFF_WR = ((uint32_t) (i * 4 + 3) << 0) | (((word >> 24) & 0xFFu) << 16);
        }

        // Deassert sd_ack
        *FDD_SD_ACK = 0;
    }

    *FDD_CTRL = FDD_CTRL_CLR_TDS_DONE;
}

void fdd_service_poll(uint16_t input_edges)
{
    static uint32_t last_started_drive = 1;
    uint32_t status = *FDD_STATUS;

    // Don't start FDD operations during button transitions
    if (input_edges) {
        return;
    }

    if ((status & (FDD_ST_PENDING1 | FDD_ST_PENDING2)) == (FDD_ST_PENDING1 | FDD_ST_PENDING2)) {
        // Both pending — alternate drives
        uint32_t drive = last_started_drive ^ 1u;
        uint32_t lba = drive ? *FDD_LBA2 : *FDD_LBA1;
        int is_write = drive ? !!(status & FDD_ST_WRITING2) : !!(status & FDD_ST_WRITING1);
        fdd_handle_request(drive, lba, is_write);
        last_started_drive = drive;
        return;
    }

    if (status & FDD_ST_PENDING1) {
        fdd_handle_request(0, *FDD_LBA1, !!(status & FDD_ST_WRITING1));
        last_started_drive = 0;
        return;
    }

    if (status & FDD_ST_PENDING2) {
        fdd_handle_request(1, *FDD_LBA2, !!(status & FDD_ST_WRITING2));
        last_started_drive = 1;
    }
}
