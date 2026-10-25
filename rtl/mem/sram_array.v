`timescale 1ns/1ps
`default_nettype none
// sram_array - joins 2^BANK_W sram_2k_macro macros into one word array (RTL-08).
// Active-high interface, synchronous read: rdata arrives the cycle after en && !we.
// The high address bits select a macro, and only the selected macro has CEN = 0. The Q
// mux uses the select bits latched in the read cycle, because Q appears one cycle later
// (docs/macro_notes.md section 3.1).
// rdata is valid only in the cycle right after a read, and users must account for that.

module sram_array #(
    parameter BANK_W = 2,               // Macro count = 2^BANK_W, 4 KB each
    parameter AW     = 10 + BANK_W      // Word address width, do not override
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          en,
    input  wire          we,
    input  wire [AW-1:0] addr,          // Word address
    input  wire [31:0]   wdata,
    output wire [31:0]   rdata
);

    generate
        if (BANK_W == 0) begin : g_one
            sram_2k_macro u_mac (
                .CLK (clk),
                .CEN (~en),
                .WEN (~we),
                .A   (addr[9:0]),
                .D   (wdata),
                .Q   (rdata)
            );
            wire unused_rst = rst_n;    // With 1 macro there is no select register
        end else begin : g_multi
            wire [BANK_W-1:0]            bank = addr[AW-1:10];
            reg  [BANK_W-1:0]            bank_q;
            wire [32*(1<<BANK_W)-1:0]    q_all;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    bank_q <= {BANK_W{1'b0}};
                else if (en & ~we)
                    bank_q <= bank;
            end

            genvar b;
            for (b = 0; b < (1 << BANK_W); b = b + 1) begin : g_bank
                sram_2k_macro u_mac (
                    .CLK (clk),
                    .CEN (~(en & (bank == b))),
                    .WEN (~we),
                    .A   (addr[9:0]),
                    .D   (wdata),
                    .Q   (q_all[b*32 +: 32])
                );
            end

            assign rdata = q_all[bank_q*32 +: 32];
        end
    endgenerate

endmodule

`default_nettype wire
