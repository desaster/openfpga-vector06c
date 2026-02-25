// ====================================================================
//                Vector 06C FPGA REPLICA
//
//            Copyright (C) 2016-2019 Sorgelig
//
// This core is distributed under modified BSD license.
// For complete licensing information see LICENSE.TXT.
// --------------------------------------------------------------------
//
// An open implementation of Vector 06C home computer
//
// Based on code from Dmitry Tselikov and Viacheslav Slavinsky
//
// Ported to Analogue Pocket by Upi Tamminen
//

`default_nettype none

module core_top (

	//
	// physical connections
	//

	////////////////////////////////////////////////////
	// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

	input wire clk_74a,  // mainclk1
	input wire clk_74b,  // mainclk1

	////////////////////////////////////////////////////
	// cartridge interface
	// switches between 3.3v and 5v mechanically
	// output enable for multibit translators controlled by pic32

	// GBA AD[15:8]
	inout  wire [7:0] cart_tran_bank2,
	output wire       cart_tran_bank2_dir,

	// GBA AD[7:0]
	inout  wire [7:0] cart_tran_bank3,
	output wire       cart_tran_bank3_dir,

	// GBA A[23:16]
	inout  wire [7:0] cart_tran_bank1,
	output wire       cart_tran_bank1_dir,

	// GBA [7] PHI#
	// GBA [6] WR#
	// GBA [5] RD#
	// GBA [4] CS1#/CS#
	//     [3:0] unwired
	inout  wire [7:4] cart_tran_bank0,
	output wire       cart_tran_bank0_dir,

	// GBA CS2#/RES#
	inout  wire cart_tran_pin30,
	output wire cart_tran_pin30_dir,
	output wire cart_pin30_pwroff_reset,

	// GBA IRQ/DRQ
	inout  wire cart_tran_pin31,
	output wire cart_tran_pin31_dir,

	// infrared
	input  wire port_ir_rx,
	output wire port_ir_tx,
	output wire port_ir_rx_disable,

	// GBA link port
	inout  wire port_tran_si,
	output wire port_tran_si_dir,
	inout  wire port_tran_so,
	output wire port_tran_so_dir,
	inout  wire port_tran_sck,
	output wire port_tran_sck_dir,
	inout  wire port_tran_sd,
	output wire port_tran_sd_dir,

	////////////////////////////////////////////////////
	// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

	output wire [21:16] cram0_a,
	inout  wire [ 15:0] cram0_dq,
	input  wire         cram0_wait,
	output wire         cram0_clk,
	output wire         cram0_adv_n,
	output wire         cram0_cre,
	output wire         cram0_ce0_n,
	output wire         cram0_ce1_n,
	output wire         cram0_oe_n,
	output wire         cram0_we_n,
	output wire         cram0_ub_n,
	output wire         cram0_lb_n,

	output wire [21:16] cram1_a,
	inout  wire [ 15:0] cram1_dq,
	input  wire         cram1_wait,
	output wire         cram1_clk,
	output wire         cram1_adv_n,
	output wire         cram1_cre,
	output wire         cram1_ce0_n,
	output wire         cram1_ce1_n,
	output wire         cram1_oe_n,
	output wire         cram1_we_n,
	output wire         cram1_ub_n,
	output wire         cram1_lb_n,

	////////////////////////////////////////////////////
	// sdram, 512mbit 16bit

	output wire [12:0] dram_a,
	output wire [ 1:0] dram_ba,
	inout  wire [15:0] dram_dq,
	output wire [ 1:0] dram_dqm,
	output wire        dram_clk,
	output wire        dram_cke,
	output wire        dram_ras_n,
	output wire        dram_cas_n,
	output wire        dram_we_n,

	////////////////////////////////////////////////////
	// sram, 1mbit 16bit

	output wire [16:0] sram_a,
	inout  wire [15:0] sram_dq,
	output wire        sram_oe_n,
	output wire        sram_we_n,
	output wire        sram_ub_n,
	output wire        sram_lb_n,

	////////////////////////////////////////////////////
	// vblank driven by dock for sync in a certain mode

	input wire vblank,

	////////////////////////////////////////////////////
	// i/o to 6515D breakout usb uart

	output wire dbg_tx,
	input  wire dbg_rx,

	////////////////////////////////////////////////////
	// i/o pads near jtag connector user can solder to

	output wire user1,
	input  wire user2,

	////////////////////////////////////////////////////
	// RFU internal i2c bus

	inout  wire aux_sda,
	output wire aux_scl,

	////////////////////////////////////////////////////
	// RFU, do not use
	output wire vpll_feed,


	//
	// logical connections
	//

	////////////////////////////////////////////////////
	// video, audio output to scaler
	output wire [23:0] video_rgb,
	output wire        video_rgb_clock,
	output wire        video_rgb_clock_90,
	output wire        video_de,
	output wire        video_skip,
	output wire        video_vs,
	output wire        video_hs,

	output wire audio_mclk,
	input  wire audio_adc,
	output wire audio_dac,
	output wire audio_lrck,

	////////////////////////////////////////////////////
	// bridge bus connection
	// synchronous to clk_74a
	output wire        bridge_endian_little,
	input  wire [31:0] bridge_addr,
	input  wire        bridge_rd,
	output reg  [31:0] bridge_rd_data,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,

	////////////////////////////////////////////////////
	// controller data
	//
	// key bitmap:
	//   [0]    dpad_up
	//   [1]    dpad_down
	//   [2]    dpad_left
	//   [3]    dpad_right
	//   [4]    face_a
	//   [5]    face_b
	//   [6]    face_x
	//   [7]    face_y
	//   [8]    trig_l1
	//   [9]    trig_r1
	//   [10]   trig_l2
	//   [11]   trig_r2
	//   [12]   trig_l3
	//   [13]   trig_r3
	//   [14]   face_select
	//   [15]   face_start
	// joy values - unsigned
	//   [ 7: 0] lstick_x
	//   [15: 8] lstick_y
	//   [23:16] rstick_x
	//   [31:24] rstick_y
	// trigger values - unsigned
	//   [ 7: 0] ltrig
	//   [15: 8] rtrig
	//
	input wire [15:0] cont1_key,
	input wire [15:0] cont2_key,
	input wire [15:0] cont3_key,
	input wire [15:0] cont4_key,
	input wire [31:0] cont1_joy,
	input wire [31:0] cont2_joy,
	input wire [31:0] cont3_joy,
	input wire [31:0] cont4_joy,
	input wire [15:0] cont1_trig,
	input wire [15:0] cont2_trig,
	input wire [15:0] cont3_trig,
	input wire [15:0] cont4_trig

);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx              = 0;
assign port_ir_rx_disable      = 1;

// bridge endianness
assign bridge_endian_little    = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3         = 8'hzz;
assign cart_tran_bank3_dir     = 1'b0;
assign cart_tran_bank2         = 8'hzz;
assign cart_tran_bank2_dir     = 1'b0;
assign cart_tran_bank1         = 8'hzz;
assign cart_tran_bank1_dir     = 1'b0;
assign cart_tran_bank0         = 4'hf;
assign cart_tran_bank0_dir     = 1'b1;
assign cart_tran_pin30         = 1'b0;
assign cart_tran_pin30_dir     = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;
assign cart_tran_pin31         = 1'bz;
assign cart_tran_pin31_dir     = 1'b0;

// link port is input only
assign port_tran_so            = 1'bz;
assign port_tran_so_dir        = 1'b0;
assign port_tran_si            = 1'bz;
assign port_tran_si_dir        = 1'b0;
assign port_tran_sck           = 1'bz;
assign port_tran_sck_dir       = 1'b0;
assign port_tran_sd            = 1'bz;
assign port_tran_sd_dir        = 1'b0;

// tie off the rest of the pins we are not using
assign cram0_a                 = 'h0;
assign cram0_dq                = {16{1'bZ}};
assign cram0_clk               = 0;
assign cram0_adv_n             = 1;
assign cram0_cre               = 0;
assign cram0_ce0_n             = 1;
assign cram0_ce1_n             = 1;
assign cram0_oe_n              = 1;
assign cram0_we_n              = 1;
assign cram0_ub_n              = 1;
assign cram0_lb_n              = 1;

assign cram1_a                 = 'h0;
assign cram1_dq                = {16{1'bZ}};
assign cram1_clk               = 0;
assign cram1_adv_n             = 1;
assign cram1_cre               = 0;
assign cram1_ce0_n             = 1;
assign cram1_ce1_n             = 1;
assign cram1_oe_n              = 1;
assign cram1_we_n              = 1;
assign cram1_ub_n              = 1;
assign cram1_lb_n              = 1;

// SDRAM active, directly driven by sdram controller

assign sram_a                  = 'h0;
assign sram_dq                 = {16{1'bZ}};
assign sram_oe_n               = 1;
assign sram_we_n               = 1;
assign sram_ub_n               = 1;
assign sram_lb_n               = 1;

assign dbg_tx                  = 1'bZ;
assign user1                   = 1'bZ;
assign aux_scl                 = 1'bZ;
assign vpll_feed               = 1'bZ;


//////////////   Analogue Pocket   /////////////////

// FDD bridgeram read buffer: APF bridge reads are 1-word pipelined
// (io_bridge_peripheral captures data BEFORE pulsing bridge_rd).
// Register BRAM output on bridge_rd to match this protocol.
wire [31:0] fdd_bridge_rd_data;
reg  [31:0] fdd_rd_data_buf;
always @(posedge clk_74a) begin
	if (bridge_rd)
		fdd_rd_data_buf <= fdd_bridge_rd_data;
end

always @(*) begin
	casex (bridge_addr)
		32'h6xxxxxxx: begin
			bridge_rd_data <= fdd_rd_data_buf;
		end
		32'hF8xxxxxx: begin
			bridge_rd_data <= cmd_bridge_rd_data;
		end
		default: begin
			bridge_rd_data <= 0;
		end
	endcase
end

// Interact menu actions
reg [19:0] cold_reboot_delay = 0;
reg [19:0] cpu_reset_delay = 0;
reg [19:0] vvod_delay = 0;
reg [19:0] pal_reset_delay = 0;

wire cold_reboot_pending = |cold_reboot_delay;
wire cpu_reset_pending   = |cpu_reset_delay;
wire vvod_pending        = |vvod_delay;
wire pal_reset_pending   = |pal_reset_delay;

reg gamepad_joy = 0;      // 0 = Keyboard, 1 = Joystick
reg [1:0] cpu_setting = 0; // bit 0 = turbo (6 MHz), bit 1 = Z80
reg [1:0] audio_mix_setting = 0; // 0 = no mix, 1 = 25%, 2 = 50%, 3 = mono
reg [6:0] kbd_cfg_a = 7'd65, kbd_cfg_b = 7'd64, kbd_cfg_x = 7'd3, kbd_cfg_y = 7'd11;
reg [6:0] kbd_cfg_select = 7'd11, kbd_cfg_r1 = 7'd3;

always @(posedge clk_74a) begin
	if (cold_reboot_delay > 0) cold_reboot_delay <= cold_reboot_delay - 20'd1;
	if (cpu_reset_delay > 0)   cpu_reset_delay   <= cpu_reset_delay   - 20'd1;
	if (vvod_delay > 0)        vvod_delay        <= vvod_delay        - 20'd1;
	if (pal_reset_delay > 0)   pal_reset_delay   <= pal_reset_delay   - 20'd1;
	if (bridge_wr) begin
		case (bridge_addr)
			32'h00000050: begin
				if (bridge_wr_data == 32'd1) cold_reboot_delay <= 20'hFFFFF;
				if (bridge_wr_data == 32'd2) cpu_reset_delay   <= 20'hFFFFF;
				if (bridge_wr_data == 32'd3) vvod_delay        <= 20'hFFFFF;
				if (bridge_wr_data == 32'd4) pal_reset_delay   <= 20'hFFFFF;
			end
			32'h00000060: gamepad_joy       <= bridge_wr_data[0];
			32'h00000070: cpu_setting       <= bridge_wr_data[1:0];
			32'h00000090: audio_mix_setting <= bridge_wr_data[1:0];
			32'h000000A0: kbd_cfg_a      <= bridge_wr_data[6:0];
			32'h000000A4: kbd_cfg_b      <= bridge_wr_data[6:0];
			32'h000000A8: kbd_cfg_x      <= bridge_wr_data[6:0];
			32'h000000AC: kbd_cfg_y      <= bridge_wr_data[6:0];
			32'h000000B0: kbd_cfg_select <= bridge_wr_data[6:0];
			32'h000000B4: kbd_cfg_r1     <= bridge_wr_data[6:0];
			default: ;
		endcase
	end
end

wire reset_n;  // active-low reset from bridge
wire [31:0] cmd_bridge_rd_data;

wire pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

wire status_boot_done  = pll_core_locked_s;
wire status_setup_done = pll_core_locked_s;
wire status_running    = reset_n;

wire dataslot_requestread;
wire [15:0] dataslot_requestread_id;
wire dataslot_requestread_ack = 1;
wire dataslot_requestread_ok = 1;

wire dataslot_requestwrite;
wire [15:0] dataslot_requestwrite_id;
wire [31:0] dataslot_requestwrite_size;
wire dataslot_requestwrite_ack = sdram_init_done_74a;
wire dataslot_requestwrite_ok = 1;

wire dataslot_allcomplete;

wire savestate_supported = 0;
wire [31:0] savestate_addr = 0;
wire [31:0] savestate_size = 0;
wire [31:0] savestate_maxloadsize = 0;

wire savestate_start;
wire savestate_start_ack = 0;
wire savestate_start_busy = 0;
wire savestate_start_ok = 0;
wire savestate_start_err = 0;

wire savestate_load;
wire savestate_load_ack = 0;
wire savestate_load_busy = 0;
wire savestate_load_ok = 0;
wire savestate_load_err = 0;

wire osnotify_inmenu;

wire        dataslot_update;
wire [15:0] dataslot_update_id;
wire [31:0] dataslot_update_size;

wire        target_dataslot_read;
wire        target_dataslot_write;
wire        target_dataslot_ack;
wire        target_dataslot_done;
wire  [2:0] target_dataslot_err;
wire [15:0] target_dataslot_id;
wire [31:0] target_dataslot_slotoffset;
wire [31:0] target_dataslot_bridgeaddr;
wire [31:0] target_dataslot_length;

wire [9:0] datatable_addr;
wire datatable_wren;
wire [31:0] datatable_data;
wire [31:0] datatable_q;

core_bridge_cmd icb (

	.clk    (clk_74a),
	.reset_n(reset_n),

	.bridge_endian_little(bridge_endian_little),
	.bridge_addr         (bridge_addr),
	.bridge_rd           (bridge_rd),
	.bridge_rd_data      (cmd_bridge_rd_data),
	.bridge_wr           (bridge_wr),
	.bridge_wr_data      (bridge_wr_data),

	.status_boot_done (status_boot_done),
	.status_setup_done(status_setup_done),
	.status_running   (status_running),

	.dataslot_requestread    (dataslot_requestread),
	.dataslot_requestread_id (dataslot_requestread_id),
	.dataslot_requestread_ack(dataslot_requestread_ack),
	.dataslot_requestread_ok (dataslot_requestread_ok),

	.dataslot_requestwrite    (dataslot_requestwrite),
	.dataslot_requestwrite_id (dataslot_requestwrite_id),
	.dataslot_requestwrite_size(dataslot_requestwrite_size),
	.dataslot_requestwrite_ack(dataslot_requestwrite_ack),
	.dataslot_requestwrite_ok (dataslot_requestwrite_ok),

	.dataslot_allcomplete(dataslot_allcomplete),

	.dataslot_update     (dataslot_update),
	.dataslot_update_id  (dataslot_update_id),
	.dataslot_update_size(dataslot_update_size),

	.savestate_supported  (savestate_supported),
	.savestate_addr       (savestate_addr),
	.savestate_size       (savestate_size),
	.savestate_maxloadsize(savestate_maxloadsize),

	.savestate_start     (savestate_start),
	.savestate_start_ack (savestate_start_ack),
	.savestate_start_busy(savestate_start_busy),
	.savestate_start_ok  (savestate_start_ok),
	.savestate_start_err (savestate_start_err),

	.savestate_load     (savestate_load),
	.savestate_load_ack (savestate_load_ack),
	.savestate_load_busy(savestate_load_busy),
	.savestate_load_ok  (savestate_load_ok),
	.savestate_load_err (savestate_load_err),

	.osnotify_inmenu(osnotify_inmenu),

	.target_dataslot_read      (target_dataslot_read),
	.target_dataslot_write     (target_dataslot_write),
	.target_dataslot_ack       (target_dataslot_ack),
	.target_dataslot_done      (target_dataslot_done),
	.target_dataslot_err       (target_dataslot_err),
	.target_dataslot_id        (target_dataslot_id),
	.target_dataslot_slotoffset(target_dataslot_slotoffset),
	.target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
	.target_dataslot_length    (target_dataslot_length),

	.datatable_addr(datatable_addr),
	.datatable_wren(datatable_wren),
	.datatable_data(datatable_data),
	.datatable_q   (datatable_q)
);

wire        dl_wr;
wire [27:0] dl_addr;
wire  [7:0] dl_data;

data_loader #(
	.ADDRESS_MASK_UPPER_4(4'h1),
	.ADDRESS_SIZE(28),
	.OUTPUT_WORD_SIZE(1),
	.WRITE_MEM_CLOCK_DELAY(8)
) data_loader (
	.clk_74a(clk_74a),
	.clk_memory(clk_sys),
	.bridge_wr(bridge_wr),
	.bridge_endian_little(bridge_endian_little),
	.bridge_addr(bridge_addr),
	.bridge_wr_data(bridge_wr_data),
	.write_en  (dl_wr),
	.write_addr(dl_addr),
	.write_data(dl_data)
);

reg is_downloading = 0;
reg [15:0] download_id;

always @(posedge clk_74a) begin
	if (dataslot_requestwrite) begin
		is_downloading <= 1;
		download_id <= dataslot_requestwrite_id;
	end
	else if (dataslot_allcomplete)
		is_downloading <= 0;
end

wire is_downloading_s;
synch_3 dl_sync(is_downloading, is_downloading_s, clk_sys);

reg [15:0] dl_addr_max;
always @(posedge clk_sys) begin
	if (download_start)
		dl_addr_max <= 16'h0000;
	else if (dl_wr)
		dl_addr_max <= dl_addr[15:0];
	if (dl_wr && dl_addr[18:16] == 3'b101)
		rom_size <= dl_addr[15:0] + 16'd1;
end


////////////////////   CLOCKS   ///////////////////
wire pll_core_locked;

pll mp1 (
	.refclk  (clk_74a),
	.rst     (0),
	.outclk_0(clk_sys),
	.outclk_1(clk_vid),
	.outclk_2(clk_vid_90),
	.locked  (pll_core_locked)
);

wire clk_sys;      // 96MHz
wire clk_vid;      // 12MHz
wire clk_vid_90;   // 12MHz 90°
reg  ce_f1, ce_f2; // 3MHz/6MHz
reg  ce_12mp;
reg  ce_12mn;
reg  ce_psg;       // 1.75MHz
reg  clk_pit;      // 1.5MHz

always @(negedge clk_sys) begin
	reg [6:0] div = 0;
	reg [5:0] psg_div = 0;
	reg       turbo;

	div <= div + 1'd1;

	if(&div) turbo <= cpu_turbo_s;
	if(turbo) begin
		ce_f1 <= !div[3] & !div[2:0];
		ce_f2 <=  div[3] & !div[2:0];
		if(sdram_ready) cpu_ready <= 1;
	end else begin
		ce_f1 <= !div[4] & !div[3:0];
		ce_f2 <=  div[4] & !div[3:0];
		if(div[6:4]==3'b100 && sdram_ready) cpu_ready <= 1;
			else if(!div[4:2] & cpu_sync & mreq) cpu_ready <= 0;
	end

	ce_12mp <= !div[2] & !div[1:0];
	ce_12mn <=  div[2] & !div[1:0];

	psg_div <= psg_div + 1'b1;
	if(psg_div == 54) psg_div <= 0;
	ce_psg <= !psg_div;

	clk_pit <= div[5];
end


////////////////////   RESET   ////////////////////
reg cold_reset = 1;
reg reset;
reg rom_enable = 1;
reg [15:0] rom_size = 0;
wire read_rom = rom_enable && (addr < rom_size) && !ed_page && ram_read;

wire cold_reboot_s, cold_reboot_rise;
synch_3 s_cold(.i(cold_reboot_pending), .o(cold_reboot_s), .clk(clk_sys), .rise(cold_reboot_rise));

wire cpu_reset_s, cpu_reset_rise;
synch_3 s_restart(.i(cpu_reset_pending), .o(cpu_reset_s), .clk(clk_sys), .rise(cpu_reset_rise));

wire vvod_s, vvod_rise;
synch_3 s_vvod(.i(vvod_pending), .o(vvod_s), .clk(clk_sys), .rise(vvod_rise));

wire pal_reset_s, pal_reset_rise;
synch_3 s_pal(.i(pal_reset_pending), .o(pal_reset_s), .clk(clk_sys), .rise(pal_reset_rise));

reg is_downloading_prev = 0;
wire download_start = is_downloading_s & ~is_downloading_prev;
wire download_end   = ~is_downloading_s & is_downloading_prev;

always @(posedge clk_sys) begin
	is_downloading_prev <= is_downloading_s;
end

reg [15:0] download_id_sys;
always @(posedge clk_sys) begin
	if(download_start)
		download_id_sys <= download_id;
end

reg force_cold_restart = 0;
reg force_erase_post_dl = 0;

always @(posedge clk_sys) begin
	if(cpu_reset_rise) begin
		rom_enable <= 0;
	end
	else if(cold_reboot_rise) begin
		rom_enable <= 1;
		force_cold_restart <= 1;
	end
	else if(download_start) begin
		rom_enable <= 0;
	end
	else if(key_vvod | vvod_rise) begin
		rom_enable <= 1;
	end
	else if(key_sbr) begin
		rom_enable <= 0;
	end
	if(download_end && download_id_sys == 16'd1)
		force_erase_post_dl <= 1;
	if(download_end && download_id_sys == 16'd5) begin
		rom_enable <= 1;
		force_cold_restart <= 1;
	end
	if(download_end && download_id_sys == 16'd6)
		rom_enable <= 1;
	if(erasing) begin
		force_erase_post_dl <= 0;
		force_cold_restart <= 0;
	end
end

always @(posedge clk_sys) begin
	reg reset_flg  = 1;
	int reset_hold = 0;

	if(erasing | is_downloading_s | cpu_reset_rise | cold_reboot_rise | vvod_rise | (fdd_busy & rom_enable)) begin
		reset_flg <= 1;
		reset     <= 1;
	end else begin
		if(reset_flg) begin
			reset_flg  <= 0;
			cpu_type   <= cpu_type_s;
			reset      <= 1;
			reset_hold <= 10000;
		end else if(reset_hold) reset_hold <= reset_hold - 1;
		else if(sdram_init_done) {cold_reset,reset} <= 0;

		if(cpu_type != cpu_type_s) reset_flg <= 1;
		if(key_vvod | key_sbr) reset_flg <= 1;
	end
end


////////////////////   CPU   ////////////////////
wire [15:0] addr     = cpu_type ? addr_z80     : addr_i80;
reg   [7:0] cpu_i;
wire  [7:0] cpu_o    = cpu_type ? cpu_o_z80    : cpu_o_i80;
wire        cpu_sync = cpu_type ? cpu_sync_z80 : cpu_sync_i80;
wire        cpu_rd   = cpu_type ? cpu_rd_z80   : cpu_rd_i80;
wire        cpu_wr_n = cpu_type ? cpu_wr_n_z80 : cpu_wr_n_i80;
reg         cpu_ready;

reg         cpu_type = 0;

reg   [7:0] status_word;
always @(posedge clk_sys) begin
	reg old_sync;
	old_sync <= cpu_sync;
	if(~old_sync & cpu_sync) status_word <= cpu_o;
end

wire int_ack  = status_word[0];
wire write_n  = status_word[1];
wire io_stack = status_word[2];
//wire halt_ack = status_word[3];
wire io_write = status_word[4];
//wire m1       = status_word[5];
wire io_read  = status_word[6];
wire ram_read = status_word[7];

wire mreq = (ram_read | ~write_n) & ~io_write & ~io_read;

reg ppi1_sel, joy_sel, vox_sel, pit_sel, pal_sel, psg_sel, edsk_sel, fdd_sel;

reg [7:0] io_data;
always_comb begin
	ppi1_sel =0;
	joy_sel  =0;
	vox_sel  =0;
	pit_sel  =0;
	pal_sel  =0;
	edsk_sel =0;
	psg_sel  =0;
	fdd_sel  =0;
	io_data  =255;
	casex(addr[7:0])
		8'b000000XX: begin ppi1_sel =1; io_data = ppi1_o;  end
		8'b0000010X: begin joy_sel  =1; io_data = 0;       end
		8'b00000110: begin              io_data = joyP_o;  end
		8'b00000111: begin vox_sel  =1; io_data = joyPU_o; end
		8'b000010XX: begin pit_sel  =1; io_data = pit_o;   end
		8'b0000110X: begin pal_sel  =1;                    end
		8'b00001110: begin pal_sel  =1; io_data = joyA_o;  end
		8'b00001111: begin pal_sel  =1; io_data = joyB_o;  end
		8'b00010000: begin edsk_sel =1;                    end
		8'b0001010X: begin psg_sel  =1; io_data = psg_o;   end
		8'b000110XX: begin fdd_sel  =1; io_data = fdd_o;   end
		8'b000111XX: begin fdd_sel  =1;                    end
		    default: ;
	endcase
end

always_comb begin
	casex({int_ack, io_read})
		 2'b01: cpu_i = io_data;
		 2'b1X: cpu_i = 255;
		default: cpu_i = ram_o;
	endcase
end

wire io_rd = io_read  & cpu_rd;
wire io_wr = io_write & ~cpu_wr_n;

wire [15:0] addr_i80;
wire  [7:0] cpu_o_i80;
wire        cpu_inte_i80;
wire        cpu_sync_i80;
wire        cpu_rd_i80;
wire        cpu_wr_n_i80;
reg         cpu_int_i80;

k580vm80a cpu_i80
(
   .pin_clk(clk_sys),
   .pin_f1(ce_f1),
   .pin_f2(ce_f2),
   .pin_reset(reset | cpu_type),
   .pin_a(addr_i80),
   .pin_dout(cpu_o_i80),
   .pin_din(cpu_i),
   .pin_hold(0),
   .pin_ready(cpu_ready),
   .pin_int(cpu_int_i80),
   .pin_inte(cpu_inte_i80),
   .pin_sync(cpu_sync_i80),
   .pin_dbin(cpu_rd_i80),
   .pin_wr_n(cpu_wr_n_i80)
);

wire [15:0] addr_z80;
wire  [7:0] cpu_o_z80;
wire        cpu_inte_z80;
wire        cpu_sync_z80;
wire        cpu_rd_z80;
wire        cpu_wr_n_z80;
reg         cpu_int_z80;

T8080se cpu_z80
(
	.CLK(clk_sys),
	.CLKEN(ce_f1),
	.RESET_n(~reset & cpu_type),
	.A(addr_z80),
	.DO(cpu_o_z80),
	.DI(cpu_i),
	.HOLD(0),
	.READY(cpu_ready),
	.INT(cpu_int_z80),
	.INTE(cpu_inte_z80),
	.SYNC(cpu_sync_z80),
	.DBIN(cpu_rd_z80),
	.WR_n(cpu_wr_n_z80)
);


////////////////////   MEM   ////////////////////
wire  [7:0] sdram_dout;
wire        sdram_ready;

wire [18:0] ram_addr = dl_wr    ? dl_addr[18:0] :
                       erasing  ? erase_addr :
                       read_rom ? {3'b101, addr} :
                       {ed_page, addr};
wire  [7:0] ram_din  = dl_wr    ? dl_data :
                       erasing  ? 8'd0 :
                       cpu_o;
wire        ram_we   = dl_wr |
                       (erasing & erase_wr & ~dl_wr) |
                       (~erasing & ~is_downloading_s & ~cpu_wr_n & ~io_write);
wire  [7:0] ram_o    = sdram_dout;

wire [24:0] sdram_addr = {6'b0, ram_addr[18:15], ram_addr[12:0], ram_addr[14:13]};

wire sdram_rd = cpu_rd & mreq;

reg sdram_init_done = 0;
always @(posedge clk_sys) begin
	if (sdram_ready & ~sdram_init_done) sdram_init_done <= 1;
end

wire sdram_init_done_74a;
synch_3 sdram_init_sync(sdram_init_done, sdram_init_done_74a, clk_74a);

sdram sdram_inst
(
	.init(~pll_core_locked),
	.clk(clk_sys),

	.SDRAM_DQ(dram_dq),
	.SDRAM_A(dram_a),
	.SDRAM_DQML(dram_dqm[0]),
	.SDRAM_DQMH(dram_dqm[1]),
	.SDRAM_BA(dram_ba),
	.SDRAM_nWE(dram_we_n),
	.SDRAM_nRAS(dram_ras_n),
	.SDRAM_nCAS(dram_cas_n),
	.SDRAM_CKE(dram_cke),
	.SDRAM_CLK(dram_clk),

	.addr(sdram_addr),
	.din(ram_din),
	.dout(sdram_dout),
	.we(ram_we),
	.rd(sdram_rd),
	.ready(sdram_ready)
);

// VRAM shadow: mirrors page 0 writes for video reads
dpram #(8, 16, 65536, 32, 14, 16384) vram
(
	.clock(clk_sys),

	.address_a({ram_addr[15], ram_addr[12:0], ram_addr[14:13]}),
	.data_a(ram_din),
	.wren_a(ram_we & ~|ram_addr[18:16]),
	.q_a(),

	.address_b({1'b1, vaddr}),
	.data_b(32'd0),
	.wren_b(1'b0),
	.q_b(vdata)
);




/////////////////  E-DISK 256KB  ///////////////////
reg  [2:0] ed_page;
reg  [7:0] ed_reg;

wire edsk_we = io_wr & edsk_sel;
always @(posedge clk_sys) begin
	reg old_we;

	old_we <= edsk_we;
	if(reset) ed_reg <= 0;
		else if(~old_we & edsk_we) ed_reg <= cpu_o;
end

wire ed_win   = addr[15] & ((addr[13] ^ addr[14]) | (ed_reg[7] & addr[13] & addr[14]) | (ed_reg[6] & ~addr[13] & ~addr[14]));
wire ed_ram   = ed_reg[5] & ed_win   & (ram_read | ~write_n);
wire ed_stack = ed_reg[4] & io_stack & (ram_read | ~write_n);

always_comb begin
	casex({ed_stack, ed_ram, ed_reg[3:0]})
		6'b1X00XX, 6'b01XX00: ed_page = 1;
		6'b1X01XX, 6'b01XX01: ed_page = 2;
		6'b1X10XX, 6'b01XX10: ed_page = 3;
		6'b1X11XX, 6'b01XX11: ed_page = 4;
		             default: ed_page = 0;
	endcase
end


/////////////////////   FDD   /////////////////////
localparam [15:0] SLOT_FDD_A = 16'd3;  // data.json slot IDs
localparam [15:0] SLOT_FDD_B = 16'd4;

reg        fdd1_img_mounted = 0, fdd2_img_mounted = 0;
reg [19:0] fdd1_img_size = 0, fdd2_img_size = 0;

always @(posedge clk_74a) begin
	reg old_dataslot_update;
	old_dataslot_update <= dataslot_update;
	fdd1_img_mounted <= 0;
	fdd2_img_mounted <= 0;

	if (dataslot_update & ~old_dataslot_update) begin
		if (dataslot_update_id == SLOT_FDD_A) begin
			fdd1_img_mounted <= 1;
			fdd1_img_size <= dataslot_update_size[19:0];
		end
		if (dataslot_update_id == SLOT_FDD_B) begin
			fdd2_img_mounted <= 1;
			fdd2_img_size <= dataslot_update_size[19:0];
		end
	end
end

wire fdd1_mount_rise, fdd2_mount_rise;
synch_3 fdd1_mount_sync(.i(fdd1_img_mounted), .o(), .clk(clk_sys), .rise(fdd1_mount_rise));
synch_3 fdd2_mount_sync(.i(fdd2_img_mounted), .o(), .clk(clk_sys), .rise(fdd2_mount_rise));

reg         fdd_drive;
reg         fdd_side;
wire        fdd_busy  = fdd_drive ? fdd2_busy  : fdd1_busy;
wire        fdd_ready = fdd_drive ? fdd2_ready : fdd1_ready;
wire  [7:0] fdd_o = fdd_ready ? (fdd_drive ? fdd2_o : fdd1_o) : 8'd0;

always @(posedge clk_sys) begin
	reg old_wr;

	old_wr <= io_wr;
	if(~old_wr & io_wr & fdd_sel & addr[2]) {fdd_side, fdd_drive} <= {~cpu_o[2], cpu_o[0]};

	if(cold_reset | cold_reboot_rise) fdd_drive <= 0;
end

//FDD1
wire  [7:0] fdd1_o;
reg         fdd1_ready;
wire        fdd1_busy;
wire        fdd1_cmd_busy;
wire  [7:0] fdd1_track;
wire [31:0] fdd1_sd_lba;
wire        fdd1_sd_rd;
wire        fdd1_sd_wr;
wire  [7:0] fdd1_sd_buff_din;

always @(posedge clk_sys) begin
	if(cold_reset | cold_reboot_rise) fdd1_ready <= 0;
		else if(fdd1_mount_rise) fdd1_ready <= |fdd1_img_size;
end

wd1793 #(1) fdd1
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel & fdd1_ready & ~fdd_drive & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdd1_o),

	.img_mounted(fdd1_mount_rise),
	.img_size(fdd1_img_size),
	.sd_lba(fdd1_sd_lba),
	.sd_rd(fdd1_sd_rd),
	.sd_wr(fdd1_sd_wr),
	.sd_ack(fdd1_sd_ack),
	.sd_buff_addr(fdd_sd_buff_addr),
	.sd_buff_dout(fdd_sd_buff_dout),
	.sd_buff_din(fdd1_sd_buff_din),
	.sd_buff_wr(fdd_sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(~fdd_drive & fdd1_ready),
	.prepare(fdd1_busy),
	.busy(fdd1_cmd_busy),
	.track(fdd1_track),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

//FDD2
wire  [7:0] fdd2_o;
reg         fdd2_ready;
wire        fdd2_busy;
wire        fdd2_cmd_busy;
wire  [7:0] fdd2_track;
wire [31:0] fdd2_sd_lba;
wire        fdd2_sd_rd;
wire        fdd2_sd_wr;
wire  [7:0] fdd2_sd_buff_din;

always @(posedge clk_sys) begin
	if(cold_reset | cold_reboot_rise) fdd2_ready <= 0;
		else if(fdd2_mount_rise) fdd2_ready <= |fdd2_img_size;
end

wd1793 #(1) fdd2
(
	.clk_sys(clk_sys),
	.ce(ce_f1),
	.reset(reset),
	.io_en(fdd_sel & fdd2_ready & fdd_drive & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdd2_o),

	.img_mounted(fdd2_mount_rise),
	.img_size(fdd2_img_size),
	.sd_lba(fdd2_sd_lba),
	.sd_rd(fdd2_sd_rd),
	.sd_wr(fdd2_sd_wr),
	.sd_ack(fdd2_sd_ack),
	.sd_buff_addr(fdd_sd_buff_addr),
	.sd_buff_dout(fdd_sd_buff_dout),
	.sd_buff_din(fdd2_sd_buff_din),
	.sd_buff_wr(fdd_sd_buff_wr),

	.wp(0),

	.size_code(3),
	.layout(0),
	.side(fdd_side),
	.ready(fdd_drive & fdd2_ready),
	.prepare(fdd2_busy),
	.busy(fdd2_cmd_busy),
	.track(fdd2_track),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

wire        fdd1_sd_ack, fdd2_sd_ack;
wire  [8:0] fdd_sd_buff_addr;
wire  [7:0] fdd_sd_buff_dout;
wire        fdd_sd_buff_wr;


////////////////////   VIDEO   ////////////////////
wire        retrace;
wire [12:0] vaddr;
wire [31:0] vdata;

wire  [7:0] vid_r, vid_g, vid_b;
wire        vid_hs, vid_vs, vid_de;

video video
(
	.reset(reset),
	.clk_sys(clk_sys),
	.ce_12mp(ce_12mp),
	.ce_12mn(ce_12mn),
	.CE_PIXEL(),
	.VGA_R(vid_r),
	.VGA_G(vid_g),
	.VGA_B(vid_b),
	.VGA_HS(vid_hs),
	.VGA_VS(vid_vs),
	.VGA_DE(vid_de),
	.vaddr(vaddr),
	.vdata(vdata),
	.scroll(ppi1_a),
	.din(cpu_o),
	.io_we(pal_sel & io_wr),
	.border(ppi1_b[3:0]),
	.mode512(ppi1_b[4]),
	.pal_reset(pal_reset_rise),
	.retrace(retrace)
);

// Video output to Pocket scaler
assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;

// Pocket-specific DE generation for uniform line widths.
// video.sv's viden produces non-uniform DE (line 0 is 563px, others 608px,
// plus a ghost line). Fix by counting pixels from HSYNC and lines from VSYNC
// to generate a clean display window independent of vid_de.
//
// Display area: 576x288 (32px border each side + 512 content,
//   16 lines top border + 256 content + 16 lines bottom border).
// Matches vector06sdl emulator defaults. 288x5=1440 fills Pocket's display
// height exactly, and 10:9 aspect fills width (1440*10/9=1600).
//
// HSYNC detected at hc=598 (1 tick after HSync rises at hc=597).
//   pix_cnt 142 = hc 740 (left border start, 32px before content)
//   pix_cnt 174 = hc 4   (content start, adjusted for pipeline delay)
//   pix_cnt 685 = hc 515 (content end)
//   pix_cnt 717 = hc 547 (right border end, 32px after content)
//
// VSYNC detected at vc=271 (line_cnt=0). Display lines by line_cnt:
//   24-39:  top border (vc 296-311)
//   40-295: content (vc 0-255)
//   296-311: bottom border (vc 256-271)
reg [9:0] pix_cnt;
reg [8:0] line_cnt;
reg       pix_hs_prev, pix_vs_prev;
always @(posedge clk_sys) begin
	if (ce_12mp) begin
		pix_hs_prev <= vid_hs;
		pix_vs_prev <= vid_vs;

		if (vid_hs & ~pix_hs_prev)
			pix_cnt <= 0;
		else
			pix_cnt <= pix_cnt + 1'd1;

		if (vid_vs & ~pix_vs_prev)
			line_cnt <= 0;
		else if (vid_hs & ~pix_hs_prev)
			line_cnt <= line_cnt + 1'd1;
	end
end

// To adjust horizontal centering, shift both pix_cnt bounds by the same
// amount: increase to move content left, decrease to move content right.
wire pocket_de = (line_cnt >= 9'd24) & (line_cnt <= 9'd311) &
                 (pix_cnt >= 10'd142) & (pix_cnt <= 10'd717);

/////////////////   OSD / SOFTCPU   /////////////////

wire        softcpu_reset = cold_reset | is_downloading_s;
wire  [3:0] osd_palette_idx;
wire        osd_in_area, osd_enable;
wire [63:0] osd_vkb_keys;
wire  [2:0] osd_vkb_shift;
wire        osd_vkb_active;
wire        osd_vkb_vvod, osd_vkb_sbr;

wire        osd_vkb_active_run = osd_vkb_active & ~reset;
wire [63:0] osd_vkb_keys_run   = osd_vkb_active_run ? osd_vkb_keys : 64'd0;
wire  [2:0] osd_vkb_shift_run  = osd_vkb_active_run ? osd_vkb_shift : 3'd0;
wire        osd_vkb_vvod_run   = osd_vkb_vvod & ~reset;
wire        osd_vkb_sbr_run    = osd_vkb_sbr & ~reset;

softcpu_subsystem softcpu_subsystem
(
	.clk_sys   (clk_sys),
	.clk_74a   (clk_74a),
	.reset     (softcpu_reset),
	.cont1_key (cont1_key_s),
	.pix_cnt   (pix_cnt),
	.line_cnt  (line_cnt),
	.osd_palette_idx(osd_palette_idx),
	.in_osd_area(osd_in_area),
	.osd_enable(osd_enable),
	.vkb_keys  (osd_vkb_keys),
	.vkb_shift (osd_vkb_shift),
	.vkb_active(osd_vkb_active),
	.vkb_vvod  (osd_vkb_vvod),
	.vkb_sbr   (osd_vkb_sbr),
	.rus_led   (ppi1_c[3]),

	.fdd1_sd_lba(fdd1_sd_lba),
	.fdd1_sd_rd(fdd1_sd_rd),
	.fdd1_sd_wr(fdd1_sd_wr),
	.fdd1_busy(fdd1_busy),
	.fdd1_cmd_busy(fdd1_cmd_busy),
	.fdd1_track(fdd1_track),
	.fdd1_sd_buff_din(fdd1_sd_buff_din),
	.fdd2_sd_lba(fdd2_sd_lba),
	.fdd2_sd_rd(fdd2_sd_rd),
	.fdd2_sd_wr(fdd2_sd_wr),
	.fdd2_busy(fdd2_busy),
	.fdd2_cmd_busy(fdd2_cmd_busy),
	.fdd2_track(fdd2_track),
	.fdd2_sd_buff_din(fdd2_sd_buff_din),
	.bridge_wr(bridge_wr),
	.bridge_addr(bridge_addr),
	.bridge_wr_data(bridge_wr_data),
	.target_dataslot_ack(target_dataslot_ack),
	.target_dataslot_done(target_dataslot_done),
	.target_dataslot_err(target_dataslot_err),

	.fdd1_sd_ack(fdd1_sd_ack),
	.fdd2_sd_ack(fdd2_sd_ack),
	.sd_buff_addr(fdd_sd_buff_addr),
	.sd_buff_dout(fdd_sd_buff_dout),
	.sd_buff_wr(fdd_sd_buff_wr),
	.target_dataslot_read(target_dataslot_read),
	.target_dataslot_write(target_dataslot_write),
	.target_dataslot_id(target_dataslot_id),
	.target_dataslot_slotoffset(target_dataslot_slotoffset),
	.target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
	.target_dataslot_length(target_dataslot_length),
	.fdd_bridge_rd_data(fdd_bridge_rd_data)
);

// OSD compositing: palette-based color lookup
// 0: transparent  1: bezel       2: key fill    3: modifier fill
// 4: accent fill  5: shift fill  6: border dark 7: border light
// 8: text dark    9: text bright / cursor
// 10: LED green   11: LED red    12: sticky border  13: sticky+cursor
reg [23:0] osd_color;
always @* begin
	case (osd_palette_idx)
		4'd0:    osd_color = 24'h000000;
		4'd1:    osd_color = 24'haeafa8;
		4'd2:    osd_color = 24'haba594;
		4'd3:    osd_color = 24'h6a6d50;
		4'd4:    osd_color = 24'h8e8660;
		4'd5:    osd_color = 24'h321e0e;
		4'd6:    osd_color = 24'h262626;
		4'd7:    osd_color = 24'h4d4d4d;
		4'd8:    osd_color = 24'h000000;
		4'd9:    osd_color = 24'hffffff;
		4'd10:   osd_color = 24'h33aa33; // LED green (FDD)
		4'd11:   osd_color = 24'hcc3333; // LED red (RUS)
		4'd12:   osd_color = 24'hffcc00; // Sticky key border
		4'd13:   osd_color = 24'h00ffff; // Sticky key + cursor
		default: osd_color = 24'h000000;
	endcase
end

reg [23:0] vid_rgb_pipe;
reg        vid_de_pipe;
reg        vid_hs_pipe;
reg        vid_vs_pipe;

always @(posedge clk_sys) begin
	if (pocket_de && osd_in_area && osd_enable && osd_palette_idx != 4'd0)
		vid_rgb_pipe <= osd_color;
	else
		vid_rgb_pipe <= pocket_de ? {vid_r, vid_g, vid_b} : 24'd0;
	vid_de_pipe  <= pocket_de;
	vid_hs_pipe  <= vid_hs;
	vid_vs_pipe  <= vid_vs;
end

reg [23:0] video_rgb_reg;
reg        video_de_reg;
reg        video_hs_reg;
reg        video_vs_reg;

always @(posedge clk_vid) begin
	video_rgb_reg <= vid_rgb_pipe;
	video_de_reg  <= vid_de_pipe;
	video_hs_reg  <= vid_hs_pipe;
	video_vs_reg  <= vid_vs_pipe;
end

assign video_rgb  = video_rgb_reg;
assign video_de   = video_de_reg;
assign video_hs   = video_hs_reg;
assign video_vs   = video_vs_reg;
assign video_skip = 0;


always @(posedge clk_sys) begin
	reg old_retrace;
	int z80_delay;
	old_retrace <= retrace;

	if(!cpu_inte_i80) cpu_int_i80 <= 0;
		else if(~old_retrace & retrace) cpu_int_i80 <= 1;

	if(!cpu_inte_z80) {z80_delay,cpu_int_z80} <= 0;
	else begin
		if(~old_retrace & retrace) z80_delay <= 1;
		if(ce_12mp && z80_delay) z80_delay <= z80_delay + 1;
		if(z80_delay == 700) begin
			z80_delay   <= 0;
			cpu_int_z80 <= 1;
		end
	end
end


/////////////////////   KBD   /////////////////////

wire [15:0] cont1_key_s;
wire        gamepad_joy_s;
synch_3 #(.WIDTH(16)) cont1_sync(cont1_key, cont1_key_s, clk_sys);
synch_3 gamepad_joy_sync(gamepad_joy, gamepad_joy_s, clk_sys);

// Suppress gamepad buttons from reaching V06C during VKB transitions.
// Without this, mapped buttons leak keypresses during VKB open/close transitions.
reg btn_suppress = 0;
reg osd_vkb_active_d;
reg [15:0] cont1_key_d;
always @(posedge clk_sys) begin
	osd_vkb_active_d <= osd_vkb_active_run;
	cont1_key_d <= cont1_key_s;
	if (cont1_key_s[8] & ~cont1_key_d[8])  // L1 rising edge: suppress immediately
		btn_suppress <= 1;
	else if (osd_vkb_active_d & ~osd_vkb_active_run)  // VKB just closed
		btn_suppress <= 1;
	else if (cont1_key_s == 16'd0)  // all buttons released
		btn_suppress <= 0;
end

wire btn_gate = gamepad_joy_s | osd_vkb_active_run | btn_suppress;

wire [1:0] cpu_setting_s;
synch_3 #(.WIDTH(2)) cpu_setting_sync(cpu_setting, cpu_setting_s, clk_sys);
wire cpu_turbo_s = cpu_setting_s[0];
wire cpu_type_s  = cpu_setting_s[1];

wire [1:0] audio_mix_s;
synch_3 #(.WIDTH(2)) audio_mix_sync(audio_mix_setting, audio_mix_s, clk_sys);

wire [41:0] kbd_cfg_bus = {kbd_cfg_a, kbd_cfg_b, kbd_cfg_x, kbd_cfg_y, kbd_cfg_select, kbd_cfg_r1};
wire [41:0] kbd_cfg_s;
synch_3 #(.WIDTH(42)) kbd_cfg_sync(kbd_cfg_bus, kbd_cfg_s, clk_sys);

wire [7:0] btn_odata;
wire [2:0] btn_shift;
pocket_keys pocket_keys_inst
(
	.buttons(btn_gate ? 16'd0 : cont1_key_s),
	.addr(~ppi1_a),
	.cfg_a(kbd_cfg_s[41:35]),      .cfg_b(kbd_cfg_s[34:28]),
	.cfg_x(kbd_cfg_s[27:21]),      .cfg_y(kbd_cfg_s[20:14]),
	.cfg_select(kbd_cfg_s[13:7]),  .cfg_r1(kbd_cfg_s[6:0]),
	.odata(btn_odata),
	.shift(btn_shift)
);

// MiSTer joyA: {X, X, .., fire2, fire1, up, down, left, right}
wire [15:0] joyA = (gamepad_joy_s & ~osd_vkb_active_run & ~btn_suppress) ?
	{10'd0, cont1_key_s[7], cont1_key_s[4], cont1_key_s[0],
	 cont1_key_s[1], cont1_key_s[2], cont1_key_s[3]} : 16'd0;
wire [15:0] joyB = 0;

wire [31:0] cont3_joy_s;
wire [15:0] cont3_trig_s;
wire [15:0] cont3_key_s;
synch_3 #(.WIDTH(32)) cont3_joy_sync(cont3_joy, cont3_joy_s, clk_sys);
synch_3 #(.WIDTH(16)) cont3_trig_sync(cont3_trig, cont3_trig_s, clk_sys);
synch_3 #(.WIDTH(16)) cont3_key_sync(cont3_key, cont3_key_s, clk_sys);

wire [10:0] ps2_key;
hid_to_ps2 hid_to_ps2_inst
(
	.clk(clk_sys),
	.reset(cold_reset),
	.joy(cont3_joy_s),
	.trig(cont3_trig_s),
	.mods(cont3_key_s[15:8]),
	.ps2_key(ps2_key)
);

wire [7:0] kbd_o_key;
wire [2:0] kbd_shift_key;

keyboard kbd
(
	.clk(clk_sys),
	.reset(cold_reset),
	.ps2_key(ps2_key),
	.addr(~ppi1_a),
	.odata(kbd_o_key),
	.shift(kbd_shift_key),
	.reset_key()
);

// F11 = ВВОД, F12 = СБР
wire vkb_vvod_rise, vkb_sbr_rise;
synch_3 vkb_vvod_sync(.clk(clk_sys), .i(osd_vkb_vvod_run), .rise(vkb_vvod_rise));
synch_3 vkb_sbr_sync(.clk(clk_sys), .i(osd_vkb_sbr_run), .rise(vkb_sbr_rise));

reg key_vvod = 0, key_sbr = 0;
always @(posedge clk_sys) begin
	reg old_stb;
	reg old_start;
	old_stb <= ps2_key[10];
	old_start  <= cont1_key_s[15];
	key_vvod <= 0;
	key_sbr  <= 0;
	if(old_stb != ps2_key[10] && ps2_key[9]) begin
		if(ps2_key[7:0] == 8'h78) key_vvod <= 1; // F11
		if(ps2_key[7:0] == 8'h07) key_sbr  <= 1; // F12
	end
	if(~old_start & cont1_key_s[15] & ~osd_vkb_active_run) key_sbr <= 1; // Start
	if(vkb_vvod_rise) key_vvod <= 1;
	if(vkb_sbr_rise) key_sbr <= 1;
end

// Virtual keyboard matrix decode (same addr pattern as pocket_keys/keyboard)
wire [7:0] vkb_addr = ~ppi1_a;
wire [7:0] vkb_odata =
	({8{vkb_addr[0]}} & osd_vkb_keys_run[7:0])   |
	({8{vkb_addr[1]}} & osd_vkb_keys_run[15:8])  |
	({8{vkb_addr[2]}} & osd_vkb_keys_run[23:16]) |
	({8{vkb_addr[3]}} & osd_vkb_keys_run[31:24]) |
	({8{vkb_addr[4]}} & osd_vkb_keys_run[39:32]) |
	({8{vkb_addr[5]}} & osd_vkb_keys_run[47:40]) |
	({8{vkb_addr[6]}} & osd_vkb_keys_run[55:48]) |
	({8{vkb_addr[7]}} & osd_vkb_keys_run[63:56]);

wire [7:0] kbd_o     = kbd_o_key | btn_odata | vkb_odata;
wire [2:0] kbd_shift = kbd_shift_key | btn_shift | osd_vkb_shift_run;


/////////////////   PPI1 (SYS)   //////////////////
wire [7:0] ppi1_o;
wire [7:0] ppi1_a;
wire [7:0] ppi1_b;
wire [7:0] ppi1_c;

k580vv55 ppi1
(
	.clk_sys(clk_sys),
	.reset(0),
	.addr(~addr[1:0]),
	.we_n(~(io_wr & ppi1_sel)),
	.idata(cpu_o),
	.odata(ppi1_o),
	.opa(ppi1_a),
	.ipb(~kbd_o),
	.opb(ppi1_b),
	.ipc({~kbd_shift,tapein,4'b1111}),
	.opc(ppi1_c)
);


/////////////////   Joystick Zoo   /////////////////
wire [7:0] joyPU   = joyA[7:0] | joyB[7:0];
wire [7:0] joyPU_o = {joyPU[3], joyPU[0], joyPU[2], joyPU[1], joyPU[4], joyPU[5], 2'b00};

wire [7:0] joyA_o  = ~{joyA[5], joyA[4], 2'b00, joyA[2], joyA[3], joyA[1], joyA[0]};
wire [7:0] joyB_o  = ~{joyB[5], joyB[4], 2'b00, joyB[2], joyB[3], joyB[1], joyB[0]};

reg  [7:0] joy_port;
wire       joy_we = io_wr & joy_sel;

always @(posedge clk_sys) begin
	reg old_we;

	old_we <= joy_we;
	if(reset) joy_port <= 0;
	else if(~old_we & joy_we) begin
		if(addr[0]) joy_port <= cpu_o;
			else if(!cpu_o[7]) joy_port[cpu_o[3:1]] <= cpu_o[0];
	end
end

reg  [7:0] joyP_o;
always_comb begin
	case(joy_port[6:5])
		2'b00: joyP_o = joyA_o & joyB_o;
		2'b01: joyP_o = joyA_o;
		2'b10: joyP_o = joyB_o;
		2'b11: joyP_o = 255;
	endcase
end


////////////////////   SOUND   ////////////////////
wire       tapein = 0;

wire [7:0] pit_o;
wire [2:0] pit_out;
wire [2:0] pit_active;
wire [2:0] pit_snd = pit_out & pit_active;

k580vi53 pit
(
	.reset(reset),
	.clk_sys(clk_sys),
	.clk_timer({clk_pit,clk_pit,clk_pit}),
	.addr(~addr[1:0]),
	.wr(io_wr & pit_sel),
	.rd(io_rd & pit_sel),
	.din(cpu_o),
	.dout(pit_o),
	.gate(3'b111),
	.out(pit_out),
	.sound_active(pit_active)
);

wire [1:0] legacy_audio = 2'd0 + ppi1_c[0] + pit_snd[0] + pit_snd[1] + pit_snd[2];

wire [7:0] psg_o;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire [5:0] psg_active;

ym2149 ym2149
(
	.CLK(clk_sys),
	.CE(ce_psg),
	.RESET(reset),
	.BDIR(io_wr & psg_sel),
	.BC(addr[0]),
	.DI(cpu_o),
	.DO(psg_o),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.ACTIVE(psg_active),
	.SEL(0),
	.MODE(0)
);

reg  [7:0] covox;
integer    covox_timeout;
wire       vox_we = io_wr & vox_sel & !covox_timeout;

always @(posedge clk_sys) begin
	reg old_we;

	if(reset | rom_enable) covox_timeout <= 200000000;
		else if(covox_timeout) covox_timeout <= covox_timeout - 1;

	old_we <= vox_we;
	if(reset) covox <= 0;
		else if(~old_we & vox_we) covox <= cpu_o;
end

wire [15:0] audio_l = {psg_active ? {1'b0, psg_ch_a, 1'b0} + {2'b00, psg_ch_b} + {1'b0, legacy_audio, 7'd0} : {1'b0, legacy_audio, 8'd0} + {1'b0, covox, 1'b0}, 5'd0};
wire [15:0] audio_r = {psg_active ? {1'b0, psg_ch_c, 1'b0} + {2'b00, psg_ch_b} + {1'b0, legacy_audio, 7'd0} : {1'b0, legacy_audio, 8'd0} + {1'b0, covox, 1'b0}, 5'd0};

// Stereo mix (replaces MiSTer framework AUDIO_MIX handling)
reg [15:0] audio_out_l, audio_out_r;
always @(*) begin
	case(audio_mix_s)
		2'd1: begin // 25%
			audio_out_l = audio_l - audio_l[15:3] + audio_r[15:3];
			audio_out_r = audio_r - audio_r[15:3] + audio_l[15:3];
		end
		2'd2: begin // 50%
			audio_out_l = audio_l - audio_l[15:2] + audio_r[15:2];
			audio_out_r = audio_r - audio_r[15:2] + audio_l[15:2];
		end
		2'd3: begin // mono
			audio_out_l = audio_l[15:1] + audio_r[15:1];
			audio_out_r = audio_l[15:1] + audio_r[15:1];
		end
		default: begin // no mix
			audio_out_l = audio_l;
			audio_out_r = audio_r;
		end
	endcase
end

sound_i2s #(
	.CHANNEL_WIDTH(15)
) sound_i2s (
	.clk_74a  (clk_74a),
	.clk_audio(clk_sys),

	.audio_l(audio_out_l[15:1]),
	.audio_r(audio_out_r[15:1]),

	.audio_mclk(audio_mclk),
	.audio_lrck(audio_lrck),
	.audio_dac (audio_dac)
);


/////////////////////////////////////////////////

wire        force_erase = (cold_reset | force_cold_restart | force_erase_post_dl) & sdram_init_done;
reg         erasing = 0;
reg         erase_wr;
reg  [18:0] erase_addr;

reg  [18:0] erase_mask;
wire [18:0] next_erase = (erase_addr + 1'd1) & erase_mask;

always @(posedge clk_sys) begin
	reg        old_force = 0;
	reg  [5:0] erase_clk_div;
	reg [18:0] end_addr;
	reg        wr;

	erase_wr <= wr;
	wr <= 0;

	old_force <= force_erase;

	if(~old_force & force_erase) begin
		if(force_erase_post_dl) begin
			erase_mask <= 19'h0FFFF;
			end_addr   <= {3'b0, 16'h0100};
			erase_addr <= {3'b0, dl_addr_max};
		end else begin
			erase_addr <= 19'h7FFFF;
			erase_mask <= 19'h7FFFF;
			end_addr   <= 19'h50000;
		end
		erase_clk_div  <= 1;
		erasing        <= 1;
	end else if(erasing) begin
		if(!is_downloading_s) begin
			erase_clk_div <= erase_clk_div + 1'd1;
			if(!erase_clk_div) begin
				if(next_erase == end_addr) erasing <= 0;
				else begin
					erase_addr <= next_erase;
					wr <= 1;
				end
			end
		end else begin
			erase_clk_div <= 1;
		end
	end
end

endmodule

module dpram #(parameter DATAWIDTH_A=8, ADDRWIDTH_A=8, NUMWORDS_A=1<<ADDRWIDTH_A,
                         DATAWIDTH_B=8, ADDRWIDTH_B=8, NUMWORDS_B=1<<ADDRWIDTH_B,
                         MEM_INIT_FILE="" )
(
	input	                       clock,

	input	     [ADDRWIDTH_A-1:0] address_a,
	input	     [DATAWIDTH_A-1:0] data_a,
	input	                       wren_a,
	output reg [DATAWIDTH_A-1:0] q_a,

	input	     [ADDRWIDTH_B-1:0] address_b,
	input	     [DATAWIDTH_B-1:0] data_b,
	input	                       wren_b,
	output reg [DATAWIDTH_B-1:0] q_b
);

altsyncram	altsyncram_component
(
			.address_a (address_a),
			.address_b (address_b),
			.clock0 (clock),
			.data_a (data_a),
			.data_b (data_b),
			.wren_a (wren_a),
			.wren_b (wren_b),
			.q_a (q_a),
			.q_b (q_b),
			.aclr0 (1'b0),
			.aclr1 (1'b0),
			.addressstall_a (1'b0),
			.addressstall_b (1'b0),
			.byteena_a (1'b1),
			.byteena_b (1'b1),
			.clock1 (1'b1),
			.clocken0 (1'b1),
			.clocken1 (1'b1),
			.clocken2 (1'b1),
			.clocken3 (1'b1),
			.eccstatus (),
			.rden_a (1'b1),
			.rden_b (1'b1));
defparam
	altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0",
	altsyncram_component.address_reg_b = "CLOCK0",
	altsyncram_component.indata_reg_b = "CLOCK0",
	altsyncram_component.numwords_a = NUMWORDS_A,
	altsyncram_component.numwords_b = NUMWORDS_B,
	altsyncram_component.widthad_a = ADDRWIDTH_A,
	altsyncram_component.widthad_b = ADDRWIDTH_B,
	altsyncram_component.width_a = DATAWIDTH_A,
	altsyncram_component.width_b = DATAWIDTH_B,
	altsyncram_component.width_byteena_a = 1,
	altsyncram_component.width_byteena_b = 1,

	altsyncram_component.init_file = MEM_INIT_FILE,
	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.outdata_reg_a = "UNREGISTERED",
	altsyncram_component.outdata_reg_b = "UNREGISTERED",
	altsyncram_component.power_up_uninitialized = "FALSE",
	altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ";


endmodule

module dpram_dc #(parameter DATAWIDTH=8, ADDRWIDTH=8)
(
	input                        clock_a,
	input      [ADDRWIDTH-1:0]   address_a,
	input      [DATAWIDTH-1:0]   data_a,
	input                        wren_a,
	output reg [DATAWIDTH-1:0]   q_a,

	input                        clock_b,
	input      [ADDRWIDTH-1:0]   address_b,
	output reg [DATAWIDTH-1:0]   q_b
);

altsyncram	altsyncram_component
(
			.address_a (address_a),
			.address_b (address_b),
			.clock0 (clock_a),
			.clock1 (clock_b),
			.data_a (data_a),
			.data_b ({DATAWIDTH{1'b0}}),
			.wren_a (wren_a),
			.wren_b (1'b0),
			.q_a (q_a),
			.q_b (q_b),
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
			.rden_b (1'b1));
defparam
	altsyncram_component.operation_mode = "DUAL_PORT",
	altsyncram_component.width_a = DATAWIDTH,
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.width_b = DATAWIDTH,
	altsyncram_component.widthad_b = ADDRWIDTH,
	altsyncram_component.address_reg_b = "CLOCK1",
	altsyncram_component.outdata_reg_b = "CLOCK1",
	altsyncram_component.numwords_a = 1 << ADDRWIDTH,
	altsyncram_component.numwords_b = 1 << ADDRWIDTH,
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.intended_device_family = "Cyclone V";
endmodule
