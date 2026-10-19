`timescale 1ns/1ps
// accel_apb.v
// Bộ chuyển APB3 slave -> giao diện valid/ready của accel_wrapper.
// Dùng khi ngoại vi trong SoC nối qua cầu APB3 (đề xuất trong doc kế hoạch).
// APB3 chỉ truy cập word: mọi lệnh ghi dùng đủ 4 byte.
// PSLVERR = 1 khi truy cập vùng không định nghĩa trong 4 KB của accelerator
// (offset >= 0x400, thanh ghi 0x00C-0x0FC, hoặc ghi vào C_BUF), để core bẫy
// access fault thay vì đọc ra 0.

module accel_apb #(
    parameter N      = 4,
    parameter DW     = 8,
    parameter AW     = 20,
    parameter SIGNED = 1
) (
    input  wire        pclk,
    input  wire        presetn,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    output wire        irq
);

    wire [3:0] region = paddr[11:8];
    wire [5:0] widx   = paddr[7:2];
    wire       bad    = (region > 4'h3) ||
                        (region == 4'h0 && widx > 6'd2) ||
                        (region == 4'h3 && pwrite);

    // Chỉ chuyển giao dịch ở pha access và hợp lệ xuống wrapper
    wire access = psel & penable;
    wire unused_s_ready;                 // APB trả PREADY = 1 nên không cần s_ready

    accel_wrapper #(.N(N), .DW(DW), .AW(AW), .SIGNED(SIGNED)) u_wrap (
        .clk     (pclk),
        .rst_n   (presetn),
        .s_valid (access & ~bad),
        .s_we    (pwrite),
        .s_addr  (paddr),
        .s_wdata (pwdata),
        .s_wstrb (4'hF),
        .s_ready (unused_s_ready),
        .s_rdata (prdata),
        .irq     (irq)
    );

    assign pready  = 1'b1;              // wrapper luôn trả lời trong 1 chu kỳ
    assign pslverr = access & bad;

endmodule
