`timescale 1ns/1ps
`default_nettype none
// boot_rom - 1 KB (256-word) boot ROM in synthesized logic at 0x0001_0000 (RTL-08). Owner: Phat.
// rv32_core reset vector (default RESET_PC). Only the fetch port can read it.
// Synchronous read like the SRAM: q arrives the cycle after en, so imem_port returns
// instructions with the same timing.
// The contents live in boot_rom_init.vh: the UART bootloader generated from fw/boot/boot.S
// by scripts/gen_boot_rom.py (make boot-gen, docs/boot.md).

module boot_rom (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [7:0]  addr,            // Word address
    output reg  [31:0] q
);

    reg [31:0] word;
    always @(*) begin
        case (addr)
`include "boot_rom_init.vh"
            default: word = 32'h0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= 32'h0;
        else if (en)
            q <= word;
    end

endmodule

`default_nettype wire
