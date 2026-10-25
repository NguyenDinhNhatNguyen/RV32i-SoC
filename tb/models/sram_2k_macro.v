`timescale 1ns/1ps
`default_nettype none
// sram_2k_macro - home model of the server SRAM hard macro, FOR SIMULATION ONLY.
// Same name and pins as the real macro (docs/macro_notes.md section 1): 1024 words x 32 bits,
// CEN and WEN active low, no byte write. On the server replace this file with
// ~/PDK_GPDK45/lib/sram_2k_macro.v (never commit that file).
//
// Behavior:
//   - CEN=0, WEN=1: read, Q arrives one cycle later (synchronous read).
//   - CEN=0, WEN=0: write D to A. Q becomes X because the real macro's behavior during
//     a write is unknown (macro_notes section 2). The wrapper must not use Q after a write cycle.
//   - CEN=1: Q holds its value.
// Contents start at 0. Testbenches load programs into mem by hierarchical reference.

module sram_2k_macro (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        WEN,
    input  wire [9:0]  A,
    input  wire [31:0] D,
    output reg  [31:0] Q
);

    reg [31:0] mem [0:1023];
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0;
    end

    always @(posedge CLK) begin
        if (CEN === 1'b0) begin
            if (WEN === 1'b0) begin
                mem[A] <= D;
                Q      <= 32'hxxxx_xxxx;
            end else if (WEN === 1'b1) begin
                Q      <= mem[A];
            end else begin
                Q      <= 32'hxxxx_xxxx;
                $display("ERROR: %m WEN = X while CEN = 0 (t=%0t)", $time);
            end
        end else if (CEN !== 1'b1) begin
            Q <= 32'hxxxx_xxxx;
            $display("ERROR: %m CEN = X (t=%0t)", $time);
        end
    end

endmodule

`default_nettype wire
