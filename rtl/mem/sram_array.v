`timescale 1ns/1ps
`default_nettype none
// sram_array - ghép 2^BANK_W macro sram_2k_macro thành một mảng word (RTL-08).
// Giao diện tích cực cao, đọc đồng bộ: rdata có ở chu kỳ sau en && !we.
// Bit địa chỉ cao chọn macro, chỉ macro được chọn có CEN = 0. Mux chọn Q dùng
// bit chọn đã chốt ở chu kỳ đọc, vì Q ra ở chu kỳ sau (docs/macro_notes.md mục 3.1).
// rdata chỉ hợp lệ ở chu kỳ ngay sau một lần đọc, nơi dùng phải tự biết điều đó.

module sram_array #(
    parameter BANK_W = 2,               // số macro = 2^BANK_W, mỗi macro 4 KB
    parameter AW     = 10 + BANK_W      // độ rộng địa chỉ word, không đặt lại
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          en,
    input  wire          we,
    input  wire [AW-1:0] addr,          // địa chỉ word
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
            wire unused_rst = rst_n;    // 1 macro thì không có thanh ghi chọn
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
