// PicoRV32 softcpu subsystem for OSD, VKB and FDD bridge service
//
// Runs firmware that manages the on-screen keyboard UI and FDD request
// scheduling. Rendering is done through a memory-mapped OSD framebuffer,
// while APF/FDD data movement is handled by softcpu_fdd_bridge.
//
// Based on the approach used by myc64-pocket and OpenFPGA_ZX-Spectrum

module softcpu_subsystem (
	input         clk_sys,
	input         clk_74a,
	input         reset,

	// Controller input, active-high button bits
	input  [15:0] cont1_key,

	// Video position for OSD pixel readout
	input  [9:0]  pix_cnt,
	input  [8:0]  line_cnt,

	// OSD video outputs
	output  [3:0] osd_palette_idx,
	output        in_osd_area,
	output        osd_enable,

	// Virtual keyboard matrix output
	output [63:0] vkb_keys,
	output  [2:0] vkb_shift,
	output        vkb_active,

	// Special key outputs for ВВОД and СБР
	output        vkb_vvod,
	output        vkb_sbr,

	// RUS/LAT LED state from PPI port C bit 3
	input         rus_led,

	// FDD bridge/APF inputs
	input  [31:0] fdd1_sd_lba,
	input         fdd1_sd_rd,
	input         fdd1_sd_wr,
	input         fdd1_busy,
	input         fdd1_cmd_busy,
	input   [7:0] fdd1_track,
	input   [7:0] fdd1_sd_buff_din,
	input  [31:0] fdd2_sd_lba,
	input         fdd2_sd_rd,
	input         fdd2_sd_wr,
	input         fdd2_busy,
	input         fdd2_cmd_busy,
	input   [7:0] fdd2_track,
	input   [7:0] fdd2_sd_buff_din,
	input         bridge_wr,
	input  [31:0] bridge_addr,
	input  [31:0] bridge_wr_data,
	input         target_dataslot_ack,
	input         target_dataslot_done,
	input   [2:0] target_dataslot_err,

	// FDD bridge/APF outputs
	output        fdd1_sd_ack,
	output        fdd2_sd_ack,
	output  [8:0] sd_buff_addr,
	output  [7:0] sd_buff_dout,
	output        sd_buff_wr,
	output        target_dataslot_read,
	output        target_dataslot_write,
	output [15:0] target_dataslot_id,
	output [31:0] target_dataslot_slotoffset,
	output [31:0] target_dataslot_bridgeaddr,
	output [31:0] target_dataslot_length,
	output [31:0] fdd_bridge_rd_data
);

// -------------------------------------------------------------------
// CPU clock: 96 MHz / 12 = 8 MHz gated clock,
// same approach as OpenFPGA_ZX-Spectrum's ce_7mp PicoRV32 clock
// -------------------------------------------------------------------

reg [3:0] clk_div;
reg clk_pico;
always @(posedge clk_sys) begin
	clk_div  <= (clk_div == 4'd11) ? 4'd0 : clk_div + 4'd1;
	clk_pico <= (clk_div == 4'd0);
end

// -------------------------------------------------------------------
// PicoRV32 CPU
// -------------------------------------------------------------------

wire        cpu_mem_valid;
wire        cpu_mem_instr;
reg         cpu_mem_ready;
wire [31:0] cpu_mem_addr;
wire [31:0] cpu_mem_wdata;
wire  [3:0] cpu_mem_wstrb;
reg  [31:0] cpu_mem_rdata;
wire        cpu_trap;

picorv32 #(
	.COMPRESSED_ISA(0),
	.ENABLE_IRQ(0),
	.ENABLE_MUL(1),
	.ENABLE_DIV(0)
) pico (
	.clk       (clk_pico),
	.resetn    (~reset),
	.trap      (cpu_trap),
	.mem_valid (cpu_mem_valid),
	.mem_instr (cpu_mem_instr),
	.mem_ready (cpu_mem_ready),
	.mem_addr  (cpu_mem_addr),
	.mem_wdata (cpu_mem_wdata),
	.mem_wstrb (cpu_mem_wstrb),
	.mem_rdata (cpu_mem_rdata)
);

// -------------------------------------------------------------------
// Address decode
// -------------------------------------------------------------------

wire sel_rom = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h0);
wire sel_io  = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h3);

// Memory ready: ROM needs 2-cycle latency (registered read), others 1-cycle
reg [1:0] rom_wait_cnt;
reg       cpu_mem_ready_rom;
reg       cpu_mem_ready_other;

always @(posedge clk_pico) begin
	if (reset) begin
		rom_wait_cnt <= 0;
		cpu_mem_ready_rom <= 0;
	end else if (sel_rom) begin
		if (rom_wait_cnt == 0 && cpu_mem_valid)
			rom_wait_cnt <= 1;
		else if (rom_wait_cnt == 1) begin
			rom_wait_cnt <= 0;
			cpu_mem_ready_rom <= 1;
		end else
			cpu_mem_ready_rom <= 0;
	end else begin
		rom_wait_cnt <= 0;
		cpu_mem_ready_rom <= 0;
	end
end

always @(posedge clk_pico) begin
	if (reset)
		cpu_mem_ready_other <= 0;
	else
		cpu_mem_ready_other <= ~cpu_mem_ready_other & cpu_mem_valid & ~sel_rom;
end

assign cpu_mem_ready = cpu_mem_ready_rom | cpu_mem_ready_other;

// -------------------------------------------------------------------
// ROM: 8 KB firmware, sprom 2048 x 32-bit
// -------------------------------------------------------------------

wire [31:0] rom_rdata;

sprom #(
	.aw(11),
	.dw(32),
	.MEM_INIT_FILE("fw/firmware.vh")
) pico_rom (
	.clk  (clk_pico),
	.rst  (reset),
	.ce   (sel_rom),
	.oe   (1'b1),
	.addr (cpu_mem_addr[12:2]),
	.dout (rom_rdata)
);

// -------------------------------------------------------------------
// Framebuffer RAM: 32 KB as 4 x 8192x8 dual-port RAMs
//
// CPU-side memory map:
//   0x10000000 - 0x10007FFF  OSD framebuffer, 32 KB, 512x128 @ 4bpp
//   0x10008000 - 0x10008FFF  Work RAM + stack, 4 KB
//
// Port A: CPU read/write in clk_pico domain, word-addressed via addr[14:2]
// Port B: Video read-only in clk_sys domain
// -------------------------------------------------------------------

wire sel_fb   = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h1) && !cpu_mem_addr[15];
wire sel_wram = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h1) &&  cpu_mem_addr[15];
wire sel_fdd  = cpu_mem_valid && (cpu_mem_addr[31:8] == 24'h300000) && |cpu_mem_addr[7:5];

wire [12:0] fb_word_addr   = cpu_mem_addr[14:2];
wire  [9:0] wram_word_addr = cpu_mem_addr[11:2];

// Framebuffer: four byte lanes, each 8192 x 8-bit
reg [7:0] fb0 [0:8191];
reg [7:0] fb1 [0:8191];
reg [7:0] fb2 [0:8191];
reg [7:0] fb3 [0:8191];

// Port A: CPU side, registered read with byte-write-enable, clk_pico domain
reg [7:0] fb0_qa, fb1_qa, fb2_qa, fb3_qa;

always @(posedge clk_pico) begin
	if (sel_fb) begin
		if (cpu_mem_wstrb[0]) fb0[fb_word_addr] <= cpu_mem_wdata[7:0];
		if (cpu_mem_wstrb[1]) fb1[fb_word_addr] <= cpu_mem_wdata[15:8];
		if (cpu_mem_wstrb[2]) fb2[fb_word_addr] <= cpu_mem_wdata[23:16];
		if (cpu_mem_wstrb[3]) fb3[fb_word_addr] <= cpu_mem_wdata[31:24];
		fb0_qa <= fb0[fb_word_addr];
		fb1_qa <= fb1[fb_word_addr];
		fb2_qa <= fb2[fb_word_addr];
		fb3_qa <= fb3[fb_word_addr];
	end
end

wire [31:0] fb_rdata = {fb3_qa, fb2_qa, fb1_qa, fb0_qa};

// -------------------------------------------------------------------
// Work RAM: 4 KB as 4 x 1024x8 single-port RAMs
// -------------------------------------------------------------------

reg [7:0] wram0 [0:1023];
reg [7:0] wram1 [0:1023];
reg [7:0] wram2 [0:1023];
reg [7:0] wram3 [0:1023];

reg [7:0] wram0_qa, wram1_qa, wram2_qa, wram3_qa;

always @(posedge clk_pico) begin
	if (sel_wram) begin
		if (cpu_mem_wstrb[0]) wram0[wram_word_addr] <= cpu_mem_wdata[7:0];
		if (cpu_mem_wstrb[1]) wram1[wram_word_addr] <= cpu_mem_wdata[15:8];
		if (cpu_mem_wstrb[2]) wram2[wram_word_addr] <= cpu_mem_wdata[23:16];
		if (cpu_mem_wstrb[3]) wram3[wram_word_addr] <= cpu_mem_wdata[31:24];
		wram0_qa <= wram0[wram_word_addr];
		wram1_qa <= wram1[wram_word_addr];
		wram2_qa <= wram2[wram_word_addr];
		wram3_qa <= wram3[wram_word_addr];
	end
end

wire [31:0] wram_rdata = {wram3_qa, wram2_qa, wram1_qa, wram0_qa};

// -------------------------------------------------------------------
// OSD framebuffer video read (Port B of the dual-port RAMs)
// -------------------------------------------------------------------

// OSD display area within pocket_de region, 576x288 display.
// OSD native resolution is 512x128, displayed at 1:1 without scaling.
// Centered horizontally and bottom-aligned vertically.
//
// pocket_de: pix_cnt 142..717, line_cnt 24..311
// OSD horizontal: 142 + (576-512)/2 = 174 .. 685
// OSD vertical:   24 + (288-128)    = 184 .. 311

localparam [9:0] OSD_X_START = 10'd174;
localparam [9:0] OSD_X_END   = 10'd685;
wire osd_pos_sys;
synch_3 osd_pos_sync(.i(osd_pos_r), .o(osd_pos_sys), .clk(clk_sys));
wire [8:0] OSD_Y_START = osd_pos_sys ? 9'd24 : 9'd184;
wire [8:0] OSD_Y_END   = osd_pos_sys ? 9'd151 : 9'd311;

// OSD pixel coordinates, 1:1 with no scaling
wire [8:0] osd_x = pix_cnt - OSD_X_START;    // 0..511
wire [6:0] osd_y = line_cnt - OSD_Y_START;   // 0..127

// 4bpp framebuffer: byte_addr = y*256 + x/2, each byte holds 2 pixels
wire [14:0] osd_byte_addr = {osd_y, osd_x[8:1]};
wire [12:0] osd_word_addr = osd_byte_addr[14:2];

// Port B: registered read in clk_sys domain for video readout
reg [7:0] fb0_qb, fb1_qb, fb2_qb, fb3_qb;

always @(posedge clk_sys) begin
	fb0_qb <= fb0[osd_word_addr];
	fb1_qb <= fb1[osd_word_addr];
	fb2_qb <= fb2[osd_word_addr];
	fb3_qb <= fb3[osd_word_addr];
end

// Pipeline byte/nibble selectors to match BRAM read latency
reg  [1:0] osd_byte_lane_r;
reg        osd_nibble_sel_r;
reg        in_osd_area_r;

always @(posedge clk_sys) begin
	osd_byte_lane_r <= osd_byte_addr[1:0];
	osd_nibble_sel_r <= osd_x[0];
	in_osd_area_r   <= (pix_cnt >= OSD_X_START) & (pix_cnt <= OSD_X_END) &
	                    (line_cnt >= OSD_Y_START) & (line_cnt <= OSD_Y_END);
end

// Select the correct byte from the 4 lanes, then the correct nibble
reg [7:0] osd_byte;
always_comb begin
	case (osd_byte_lane_r)
		2'd0: osd_byte = fb0_qb;
		2'd1: osd_byte = fb1_qb;
		2'd2: osd_byte = fb2_qb;
		2'd3: osd_byte = fb3_qb;
	endcase
end

// Upper nibble is the even pixel when x[0]=0, lower nibble is the odd pixel when x[0]=1
assign osd_palette_idx = osd_nibble_sel_r ? osd_byte[3:0] : osd_byte[7:4];
assign in_osd_area = in_osd_area_r;

// -------------------------------------------------------------------
// CPU read mux
// -------------------------------------------------------------------

always_comb begin
	casez (cpu_mem_addr)
		32'h0???_????: cpu_mem_rdata = rom_rdata;
		32'h1???_????: cpu_mem_rdata = cpu_mem_addr[15] ? wram_rdata : fb_rdata;
		32'h2000_0000: cpu_mem_rdata = {16'd0, cont1_key};
		32'h2000_0004: cpu_mem_rdata = {8'd0, fdd2_track, fdd1_track, 6'd0, fdd2_cmd_busy, fdd1_cmd_busy};
		32'h2000_0008: cpu_mem_rdata = {31'd0, rus_led};
		32'h3???_????: cpu_mem_rdata = sel_fdd ? fdd_rdata : 32'd0;
		default:       cpu_mem_rdata = 32'd0;
	endcase
end

wire [31:0] fdd_rdata;

softcpu_fdd_bridge #(
	.BRIDGE_ADDR(32'h60000000)
) fdd_softcpu (
	.clk_pico(clk_pico),
	.clk_sys(clk_sys),
	.clk_74a(clk_74a),
	.reset(reset),

	.cpu_valid(sel_fdd),
	.cpu_addr(cpu_mem_addr),
	.cpu_wdata(cpu_mem_wdata),
	.cpu_wstrb(cpu_mem_wstrb),
	.cpu_rdata(fdd_rdata),

	.fdd1_sd_lba(fdd1_sd_lba),
	.fdd1_sd_rd(fdd1_sd_rd),
	.fdd1_sd_wr(fdd1_sd_wr),
	.fdd1_sd_ack(fdd1_sd_ack),
	.fdd1_busy(fdd1_busy),
	.fdd1_sd_buff_din(fdd1_sd_buff_din),

	.fdd2_sd_lba(fdd2_sd_lba),
	.fdd2_sd_rd(fdd2_sd_rd),
	.fdd2_sd_wr(fdd2_sd_wr),
	.fdd2_sd_ack(fdd2_sd_ack),
	.fdd2_busy(fdd2_busy),
	.fdd2_sd_buff_din(fdd2_sd_buff_din),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),

	.bridge_wr(bridge_wr),
	.bridge_addr(bridge_addr),
	.bridge_wr_data(bridge_wr_data),

	.target_dataslot_read(target_dataslot_read),
	.target_dataslot_write(target_dataslot_write),
	.target_dataslot_id(target_dataslot_id),
	.target_dataslot_slotoffset(target_dataslot_slotoffset),
	.target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
	.target_dataslot_length(target_dataslot_length),
	.target_dataslot_ack(target_dataslot_ack),
	.target_dataslot_done(target_dataslot_done),
	.target_dataslot_err(target_dataslot_err),

	.bridge_rd_data_out(fdd_bridge_rd_data)
);

// -------------------------------------------------------------------
// I/O registers, active on write to 0x30000000+
// -------------------------------------------------------------------

reg        osd_enable_r;
reg [63:0] vkb_keys_r;
reg  [2:0] vkb_shift_r;
reg        vkb_active_r;
reg        vkb_vvod_r;
reg        vkb_sbr_r;
reg        osd_pos_r;

always @(posedge clk_pico) begin
	if (reset) begin
		osd_enable_r <= 0;
		vkb_keys_r   <= 0;
		vkb_shift_r  <= 0;
		vkb_active_r <= 0;
		vkb_vvod_r   <= 0;
		vkb_sbr_r    <= 0;
		osd_pos_r    <= 0;
	end else begin
		// Special keys are one-shot pulses.
		vkb_vvod_r <= 0;
		vkb_sbr_r  <= 0;

		if (sel_io && (cpu_mem_wstrb != 0)) begin
			case (cpu_mem_addr[7:0])
				8'h00: osd_enable_r <= cpu_mem_wdata[0];
				8'h04: vkb_keys_r[31:0]  <= cpu_mem_wdata;
				8'h08: vkb_keys_r[63:32] <= cpu_mem_wdata;
				8'h0C: vkb_shift_r       <= cpu_mem_wdata[2:0];
				8'h10: vkb_active_r      <= cpu_mem_wdata[0];
				8'h14: vkb_vvod_r        <= cpu_mem_wdata[0];
				8'h18: vkb_sbr_r         <= cpu_mem_wdata[0];
				8'h1C: osd_pos_r         <= cpu_mem_wdata[0];
			endcase
		end
	end
end

assign osd_enable = osd_enable_r;
assign vkb_keys   = vkb_keys_r;
assign vkb_shift   = vkb_shift_r;
assign vkb_active  = vkb_active_r;
assign vkb_vvod    = vkb_vvod_r;
assign vkb_sbr     = vkb_sbr_r;

endmodule
