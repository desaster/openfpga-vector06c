#ifndef SOFTCPU_REGS_H
#define SOFTCPU_REGS_H

#include <stdint.h>

// OSD framebuffer (first 32 KB of RAM)
// 512x128 pixels, 4bpp = 32768 bytes
#define OSD_FB ((volatile uint8_t *) 0x10000000)

// Controller input (read-only)
#define CONT1_KEY ((volatile uint32_t *) 0x20000000)

// FDD hardware status (read-only, directly from WD1793)
#define FDD_HW_STATUS ((volatile uint32_t *) 0x20000004)
#define FDD_HW_BUSY1  (1 << 0)
#define FDD_HW_BUSY2  (1 << 1)

// RUS/LAT LED status (read-only, from PPI1 port C bit 3)
#define RUS_LED_STATUS ((volatile uint32_t *) 0x20000008)
#define RUS_LED_ON     (1 << 0)

// Core I/O registers, directly memory-mapped
#define OSD_CTRL   ((volatile uint32_t *) 0x30000000)
#define VKB_KEYS_0 ((volatile uint32_t *) 0x30000004) // rows 0-3
#define VKB_KEYS_1 ((volatile uint32_t *) 0x30000008) // rows 4-7
#define VKB_SHIFT  ((volatile uint32_t *) 0x3000000C) // bit 0=Shift, 1=Ctrl, 2=Alt
#define VKB_ACTIVE ((volatile uint32_t *) 0x30000010) // 1=suppress pocket_keys
#define VKB_VVOD   ((volatile uint32_t *) 0x30000014) // ВВОД key (write 1 to trigger)
#define VKB_SBR    ((volatile uint32_t *) 0x30000018) // СБР key (write 1 to trigger)
#define OSD_POS    ((volatile uint32_t *) 0x3000001C) // 0=bottom, 1=top

// Softcore FDD bridge registers
#define FDD_STATUS       ((volatile uint32_t *) 0x30000020) // R: status
#define FDD_CTRL         ((volatile uint32_t *) 0x30000020) // W: control
#define FDD_LBA1         ((volatile uint32_t *) 0x30000024) // R: FDD1 LBA
#define FDD_LBA2         ((volatile uint32_t *) 0x30000028) // R: FDD2 LBA
#define FDD_SD_ACK       ((volatile uint32_t *) 0x3000002C) // W: sd_ack control
#define FDD_TDS_ID       ((volatile uint32_t *) 0x30000030) // W: dataslot id
#define FDD_TDS_OFFSET   ((volatile uint32_t *) 0x30000034) // W: dataslot offset
#define FDD_TDS_TRIGGER  ((volatile uint32_t *) 0x30000038) // W: trigger read/write
#define FDD_BRAM_ADDR    ((volatile uint32_t *) 0x3000003C) // W: bridgeram address
#define FDD_BRAM_RDATA   ((volatile uint32_t *) 0x30000040) // R: bridgeram read
#define FDD_BRAM_WDATA   ((volatile uint32_t *) 0x30000044) // W: bridgeram write
#define FDD_SD_BUFF_WR   ((volatile uint32_t *) 0x30000048) // W: sd_buff write
#define FDD_SD_BUFF_ADDR ((volatile uint32_t *) 0x3000004C) // W: sd_buff addr (for read)
#define FDD_SD_BUFF_DIN  ((volatile uint32_t *) 0x30000050) // R: sd_buff data in

// FDD_CTRL write bits
#define FDD_CTRL_CLR_PENDING1 (1 << 0)
#define FDD_CTRL_CLR_PENDING2 (1 << 1)
#define FDD_CTRL_CLR_TDS_DONE (1 << 2)

// FDD_STATUS read bits
#define FDD_ST_PENDING1 (1 << 0)
#define FDD_ST_PENDING2 (1 << 1)
#define FDD_ST_TDS_DONE (1 << 3)
#define FDD_ST_WRITING1 (1 << 11)
#define FDD_ST_WRITING2 (1 << 12)

// OSD_CTRL bits: [0]=enable
#define OSD_ENABLE (1 << 0)

// cont1_key button bits
#define BTN_DPAD_UP    (1 << 0)
#define BTN_DPAD_DOWN  (1 << 1)
#define BTN_DPAD_LEFT  (1 << 2)
#define BTN_DPAD_RIGHT (1 << 3)
#define BTN_A          (1 << 4)
#define BTN_B          (1 << 5)
#define BTN_X          (1 << 6)
#define BTN_Y          (1 << 7)
#define BTN_L1         (1 << 8)
#define BTN_R1         (1 << 9)
#define BTN_SELECT     (1 << 14)

// OSD framebuffer dimensions
#define OSD_WIDTH   512
#define OSD_HEIGHT  128
#define OSD_STRIDE  256   // bytes per row, 512 pixels / 2 nibbles
#define OSD_FB_SIZE 32768 // OSD_STRIDE * OSD_HEIGHT

// Functions provided by start.S
extern void timer_start(uint32_t timeout);
extern void irq_mask(uint32_t mask);

#endif
