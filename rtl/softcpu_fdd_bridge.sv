module softcpu_fdd_bridge #(
	parameter [31:0] BRIDGE_ADDR = 32'h60000000
) (
	input  wire        clk_pico,
	input  wire        clk_sys,
	input  wire        clk_74a,
	input  wire        reset,

	input  wire        cpu_valid,
	input  wire [31:0] cpu_addr,
	input  wire [31:0] cpu_wdata,
	input  wire  [3:0] cpu_wstrb,
	output reg  [31:0] cpu_rdata,

	input  wire [31:0] fdd1_sd_lba,
	input  wire        fdd1_sd_rd,
	input  wire        fdd1_sd_wr,
	output reg         fdd1_sd_ack,
	input  wire        fdd1_busy,

	input  wire [31:0] fdd2_sd_lba,
	input  wire        fdd2_sd_rd,
	input  wire        fdd2_sd_wr,
	output reg         fdd2_sd_ack,
	input  wire        fdd2_busy,

	input  wire  [7:0] fdd1_sd_buff_din,
	input  wire  [7:0] fdd2_sd_buff_din,

	output reg   [8:0] sd_buff_addr,
	output reg   [7:0] sd_buff_dout,
	output reg         sd_buff_wr,

	input  wire        bridge_wr,
	input  wire [31:0] bridge_addr,
	input  wire [31:0] bridge_wr_data,

	output wire        target_dataslot_read,
	output wire        target_dataslot_write,
	output reg  [15:0] target_dataslot_id,
	output reg  [31:0] target_dataslot_slotoffset,
	output reg  [31:0] target_dataslot_bridgeaddr,
	output reg  [31:0] target_dataslot_length,
	input  wire        target_dataslot_ack,
	input  wire        target_dataslot_done,
	input  wire  [2:0] target_dataslot_err,

	output wire [31:0] bridge_rd_data_out
);

// cpu_valid is pre-decoded by parent (sel_fdd = addr[31:8] == 24'h300000 && |addr[7:5])
//
// Clock domain note: clk_pico is a gated clock derived from clk_sys —
// its posedges ARE clk_sys posedges (1-in-12 duty cycle). Registers
// driven on posedge clk_pico are stable for 12 clk_sys cycles and
// directly readable by clk_sys logic without synchronizers.
// Only clk_sys ↔ clk_74a crossings require synch_3.

// -------------------------------------------------------------------
// Bridgeram: BIDIR_DUAL_PORT altsyncram
//
// Port A (clk_74a): APF DMA writes (fills for reads) + reads (for writes)
// Port B (clk_pico): firmware read/write via FDD_BRAM registers
// -------------------------------------------------------------------

wire [31:0] bram_q_a;
wire [31:0] bram_q_b;

reg  [7:0]  bram_addr_b_r;
reg  [31:0] bram_data_b_r;
reg         bram_wren_b_r;

assign bridge_rd_data_out = bram_q_a;

altsyncram bridgeram (
	.clock0    (clk_74a),
	.address_a (bridge_addr[9:2]),
	.data_a    ({bridge_wr_data[7:0], bridge_wr_data[15:8],
	             bridge_wr_data[23:16], bridge_wr_data[31:24]}),
	.wren_a    (bridge_wr && bridge_addr[31:28] == BRIDGE_ADDR[31:28]),
	.q_a       (bram_q_a),

	.clock1    (clk_pico),
	.address_b (bram_addr_b_r),
	.data_b    (bram_data_b_r),
	.wren_b    (bram_wren_b_r),
	.q_b       (bram_q_b),

	.aclr0 (1'b0),
	.aclr1 (1'b0),
	.addressstall_a (1'b0),
	.addressstall_b (1'b0),
	.byteena_a (1'b1),
	.byteena_b (1'b1),
	.clocken0 (1'b1),
	.clocken1 (1'b1),
	.clocken2 (1'b1),
	.clocken3 (1'b1),
	.eccstatus (),
	.rden_a (1'b1),
	.rden_b (1'b1)
);
defparam
	bridgeram.operation_mode = "BIDIR_DUAL_PORT",
	bridgeram.width_a = 32,
	bridgeram.widthad_a = 8,
	bridgeram.width_b = 32,
	bridgeram.widthad_b = 8,
	bridgeram.address_reg_b = "CLOCK1",
	bridgeram.outdata_reg_a = "UNREGISTERED",
	bridgeram.outdata_reg_b = "CLOCK1",
	bridgeram.numwords_a = 256,
	bridgeram.numwords_b = 256,
	bridgeram.lpm_type = "altsyncram",
	bridgeram.intended_device_family = "Cyclone V";

// -------------------------------------------------------------------
// Pending / direction tracking (clk_sys domain)
// -------------------------------------------------------------------

reg        fdd1_pending;
reg        fdd2_pending;
reg [31:0] fdd1_lba_hold;
reg [31:0] fdd2_lba_hold;
reg        fdd1_is_write;
reg        fdd2_is_write;

reg fdd1_sd_rd_prev;
reg fdd2_sd_rd_prev;
reg fdd1_sd_wr_prev;
reg fdd2_sd_wr_prev;

// -------------------------------------------------------------------
// CDC: clk_sys ↔ clk_74a (truly asynchronous — synch_3 required)
// -------------------------------------------------------------------

reg tds_read_r;
reg tds_write_r;
synch_3 tds_read_sync(.i(tds_read_r), .o(target_dataslot_read), .clk(clk_74a));
synch_3 tds_write_sync(.i(tds_write_r), .o(target_dataslot_write), .clk(clk_74a));

wire target_dataslot_ack_s;
wire target_dataslot_done_rise;
synch_3 tds_ack_sync(.i(target_dataslot_ack), .o(target_dataslot_ack_s), .clk(clk_sys));
synch_3 tds_done_sync(.i(target_dataslot_done), .o(), .clk(clk_sys), .rise(target_dataslot_done_rise));

// -------------------------------------------------------------------
// TDS done/err latching (clk_sys domain)
// -------------------------------------------------------------------

reg        tds_done;
reg  [2:0] tds_err;

// -------------------------------------------------------------------
// Firmware command pulses (clk_pico registers, directly read by clk_sys)
//
// Set on firmware write, auto-cleared next clk_pico cycle. Visible to
// clk_sys for 12 cycles (one full clk_pico period) — idempotent effects.
// -------------------------------------------------------------------

reg clear_pending1_pulse;
reg clear_pending2_pulse;
reg clear_tds_done_pulse;
reg tds_read_pulse;
reg tds_write_pulse;

reg cpu_valid_prev;

// -------------------------------------------------------------------
// clk_sys logic: edge detection, TDS handshake, pending clear
// -------------------------------------------------------------------

always @(posedge clk_sys) begin
	fdd1_sd_rd_prev <= fdd1_sd_rd;
	fdd2_sd_rd_prev <= fdd2_sd_rd;
	fdd1_sd_wr_prev <= fdd1_sd_wr;
	fdd2_sd_wr_prev <= fdd2_sd_wr;

	// Edge detect sd_rd (read requests)
	if (~fdd1_sd_rd_prev & fdd1_sd_rd) begin
		fdd1_lba_hold <= fdd1_sd_lba;
		fdd1_pending <= 1;
		fdd1_is_write <= 0;
	end
	if (~fdd2_sd_rd_prev & fdd2_sd_rd) begin
		fdd2_lba_hold <= fdd2_sd_lba;
		fdd2_pending <= 1;
		fdd2_is_write <= 0;
	end

	// Edge detect sd_wr (write requests)
	if (~fdd1_sd_wr_prev & fdd1_sd_wr) begin
		fdd1_lba_hold <= fdd1_sd_lba;
		fdd1_pending <= 1;
		fdd1_is_write <= 1;
	end
	if (~fdd2_sd_wr_prev & fdd2_sd_wr) begin
		fdd2_lba_hold <= fdd2_sd_lba;
		fdd2_pending <= 1;
		fdd2_is_write <= 1;
	end

	// Firmware clear pending (pulse regs, directly readable)
	if (clear_pending1_pulse) fdd1_pending <= 0;
	if (clear_pending2_pulse) fdd2_pending <= 0;

	// TDS trigger from firmware (pulse regs)
	// Auto-clear tds_done on new trigger to prevent stale done
	if (tds_read_pulse) begin
		tds_read_r <= 1;
		tds_done <= 0;
	end
	if (tds_write_pulse) begin
		tds_write_r <= 1;
		tds_done <= 0;
	end

	// Auto-deassert tds_read/write when APF acknowledges (takes priority)
	if (target_dataslot_ack_s) begin
		tds_read_r <= 0;
		tds_write_r <= 0;
	end

	// Latch APF done/err for firmware status register
	if (target_dataslot_done_rise) begin
		tds_done <= 1;
		tds_err <= target_dataslot_err;
	end
	if (clear_tds_done_pulse)
		tds_done <= 0;

	if (reset & ~fdd1_busy & ~fdd2_busy) begin
		fdd1_pending <= 0;
		fdd2_pending <= 0;
		tds_read_r <= 0;
		tds_write_r <= 0;
		tds_done <= 0;
		tds_err <= 0;
		fdd1_is_write <= 0;
		fdd2_is_write <= 0;
	end
end

// -------------------------------------------------------------------
// sd_buff_din mux (active drive selects which WD1793 buffer to read)
// -------------------------------------------------------------------

reg active_drive_r;

wire [7:0] sd_buff_din_mux = active_drive_r ? fdd2_sd_buff_din : fdd1_sd_buff_din;

// -------------------------------------------------------------------
// Firmware register reads (combinational)
//
// clk_sys registers (pending, LBA, done, err) are directly readable
// from the clk_pico domain — no synchronizers needed.
// -------------------------------------------------------------------

always_comb begin
	cpu_rdata = 32'd0;
	if (cpu_valid) begin
		case (cpu_addr[7:0])
			8'h20: cpu_rdata = {
				19'd0,
				fdd2_is_write,   // bit [12]
				fdd1_is_write,   // bit [11]
				tds_err,         // bits [10:8]
				4'd0,            // bits [7:4] reserved
				tds_done,        // bit [3]
				1'b0,            // bit [2] reserved
				fdd2_pending,    // bit [1]
				fdd1_pending     // bit [0]
			};
			8'h24: cpu_rdata = fdd1_lba_hold;
			8'h28: cpu_rdata = fdd2_lba_hold;
			8'h40: cpu_rdata = bram_q_b;
			8'h50: cpu_rdata = {24'd0, sd_buff_din_mux};
			default: cpu_rdata = 32'd0;
		endcase
	end
end

// -------------------------------------------------------------------
// Firmware register writes + read auto-increment (clk_pico domain)
//
// Auto-increment: BRAM addr increments on BRAM_RDATA read or
// BRAM_WDATA write; sd_buff_addr increments on SD_BUFF_DIN read.
// Firmware sets starting address once, then accesses sequentially.
// -------------------------------------------------------------------

always @(posedge clk_pico) begin
	// Auto-clear pulses and one-shot signals
	bram_wren_b_r <= 0;
	sd_buff_wr <= 0;
	clear_pending1_pulse <= 0;
	clear_pending2_pulse <= 0;
	clear_tds_done_pulse <= 0;
	tds_read_pulse <= 0;
	tds_write_pulse <= 0;

	// Track cpu_valid rising edge
	cpu_valid_prev <= cpu_valid;

	if (reset) begin
		fdd1_sd_ack <= 0;
		fdd2_sd_ack <= 0;
		sd_buff_addr <= 0;
		sd_buff_dout <= 0;
		bram_addr_b_r <= 0;
		bram_data_b_r <= 0;
		cpu_valid_prev <= 0;
		active_drive_r <= 0;
		target_dataslot_id <= 0;
		target_dataslot_slotoffset <= 0;
		target_dataslot_bridgeaddr <= BRIDGE_ADDR;
		target_dataslot_length <= 32'd512;
	end else if (cpu_valid && !cpu_valid_prev && (cpu_wstrb != 0)) begin
		case (cpu_addr[7:0])
			8'h20: begin // FDD_CTRL
				if (cpu_wdata[0]) clear_pending1_pulse <= 1;
				if (cpu_wdata[1]) clear_pending2_pulse <= 1;
				if (cpu_wdata[2]) clear_tds_done_pulse <= 1;
			end
			8'h2C: begin // FDD_SD_ACK
				fdd1_sd_ack <= cpu_wdata[0];
				fdd2_sd_ack <= cpu_wdata[1];
				active_drive_r <= cpu_wdata[1];
			end
			8'h30: target_dataslot_id <= cpu_wdata[15:0]; // FDD_TDS_ID
			8'h34: target_dataslot_slotoffset <= cpu_wdata; // FDD_TDS_OFFSET
			8'h38: begin // FDD_TDS_TRIGGER
				if (cpu_wdata[0]) tds_read_pulse <= 1;
				if (cpu_wdata[1]) tds_write_pulse <= 1;
			end
			8'h3C: bram_addr_b_r <= cpu_wdata[7:0]; // FDD_BRAM_ADDR
			8'h44: begin // FDD_BRAM_WDATA (auto-increments bram addr)
				bram_data_b_r <= cpu_wdata;
				bram_wren_b_r <= 1;
			end
			8'h48: begin // FDD_SD_BUFF_WR
				sd_buff_addr <= cpu_wdata[8:0];
				sd_buff_dout <= cpu_wdata[23:16];
				sd_buff_wr <= 1;
			end
			8'h4C: sd_buff_addr <= cpu_wdata[8:0]; // FDD_SD_BUFF_ADDR
		endcase
	end

	// Second cycle of cpu_valid: auto-increment for sequential-access regs.
	// Fires one clk_pico after the action, so BRAM/sd_buff sees the current
	// address on the action cycle before it advances.
	if (!reset && cpu_valid && cpu_valid_prev) begin
		case (cpu_addr[7:0])
			8'h40: bram_addr_b_r <= bram_addr_b_r + 8'd1;
			8'h44: bram_addr_b_r <= bram_addr_b_r + 8'd1;
			8'h50: sd_buff_addr <= sd_buff_addr + 9'd1;
		endcase
	end
end

endmodule
