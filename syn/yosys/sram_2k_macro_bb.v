// sram_2k_macro_bb - empty black box of the SRAM macro for the home Yosys flow (sta-soc-nangate).
// Same pins as tb/models/sram_2k_macro.v. Nangate45 has no macro .lib, so OpenSTA keeps the 8
// instances as black boxes and paths through the macros are not timed at home.
(* blackbox *)
module sram_2k_macro (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        WEN,
    input  wire [9:0]  A,
    input  wire [31:0] D,
    output wire [31:0] Q
);
endmodule
