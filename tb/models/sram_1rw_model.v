`timescale 1ns/1ps
`default_nettype none
// sram_1rw_model - single-port SRAM behavioral model, FOR SIMULATION ONLY.
// Synchronous read (rdata_o arrives the cycle after ce_i && !we_i), writes use
// byte enables, and rdata_o holds its old value on writes and when idle.
// Contents start at 0, then load with $readmemh from the plusarg named
// INIT_PLUSARG (for example +imem=tb/core/out/x.imem.hex). This is the only file
// that uses `initial`, because it is not RTL.

module sram_1rw_model #(
    parameter DEPTH        = 4096,           // Number of words
    parameter AW           = $clog2(DEPTH),
    parameter INIT_PLUSARG = "imem"
) (
    input  wire          clk,
    input  wire          ce_i,
    input  wire          we_i,
    input  wire [3:0]    be_i,
    input  wire [AW-1:0] addr_i,             // Word address
    input  wire [31:0]   wdata_i,
    output reg  [31:0]   rdata_o
);

    reg [31:0] mem [0:DEPTH-1];

    reg [8*512-1:0] init_file;
    integer i;
    integer b;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h0;
        if ($value$plusargs({INIT_PLUSARG, "=%s"}, init_file))
            $readmemh(init_file, mem);
    end

    always @(posedge clk) begin
        if (ce_i) begin
            if (we_i) begin
                for (b = 0; b < 4; b = b + 1)
                    if (be_i[b])
                        mem[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
            end else begin
                rdata_o <= mem[addr_i];
            end
        end
    end

endmodule

`default_nettype wire
