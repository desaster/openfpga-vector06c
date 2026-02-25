//
// Analogue Pocket gamepad buttons to Vector-06C keyboard matrix
//

module pocket_keys
(
	input  [15:0] buttons,
	input   [7:0] addr,
	input   [6:0] cfg_a, cfg_b, cfg_x, cfg_y, cfg_select, cfg_r1,
	output  [7:0] odata,
	output  [2:0] shift
);

wire btn_up     = buttons[0];
wire btn_down   = buttons[1];
wire btn_left   = buttons[2];
wire btn_right  = buttons[3];
wire btn_a      = buttons[4];
wire btn_b      = buttons[5];
wire btn_x      = buttons[6];
wire btn_y      = buttons[7];
wire btn_r1     = buttons[9];
wire btn_select = buttons[14];

// Hardcoded: D-pad arrows (row 0)
//            col7    col6       col5     col4     col3  col2  col1  col0
wire [7:0] row0_fixed = {btn_down, btn_right, btn_up, btn_left, 4'd0};

// Decode a configurable button: cfg value -> matrix position or modifier
// Returns {matrix[7:0], mods[2:0]}
function automatic [10:0] decode_btn;
	input [6:0] cfg;
	input pressed;
	input [7:0] addr;
	reg [5:0] pos;
	begin
		decode_btn = 11'd0;
		if (pressed) begin
			if (cfg >= 7'd1 && cfg <= 7'd64) begin
				pos = cfg[5:0] - 6'd1;
				if (addr[pos[5:3]])
					decode_btn[10:3] = 8'd1 << pos[2:0];
			end else case (cfg)
				7'd65: decode_btn[2:0] = 3'b001;  // Shift
				7'd66: decode_btn[2:0] = 3'b010;  // Ctrl
				7'd67: decode_btn[2:0] = 3'b100;  // Alt
				default: ;
			endcase
		end
	end
endfunction

wire [10:0] dec_a      = decode_btn(cfg_a,      btn_a,      addr);
wire [10:0] dec_b      = decode_btn(cfg_b,      btn_b,      addr);
wire [10:0] dec_x      = decode_btn(cfg_x,      btn_x,      addr);
wire [10:0] dec_y      = decode_btn(cfg_y,      btn_y,      addr);
wire [10:0] dec_select = decode_btn(cfg_select,  btn_select, addr);
wire [10:0] dec_r1     = decode_btn(cfg_r1,      btn_r1,     addr);
wire [10:0] all = dec_a | dec_b | dec_x | dec_y | dec_select | dec_r1;

assign odata =
	(row0_fixed & {8{addr[0]}})|
	all[10:3];

assign shift = all[2:0];

endmodule
