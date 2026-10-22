`timescale 1ns/1ps
`default_nettype none
// boot_rom - boot ROM 1 KB (256 word) bằng logic tổng hợp, ở 0x0001_0000 (RTL-08). Chủ: Phát.
// Reset vector của rv32_core (RESET_PC mặc định). Chỉ cổng lệnh đọc được.
// Đọc đồng bộ giống SRAM: q có ở chu kỳ sau en, để imem_port trả lệnh cùng timing.
// Nội dung nằm ở boot_rom_init.vh (bản base chỉ nhảy về IMEM).

module boot_rom (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [7:0]  addr,            // địa chỉ word
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
