`timescale 1ns/1ps
`default_nettype none
// sram_wrap - slave valid/ready cho mảng SRAM macro (RTL-08).
// Dùng làm DMEM, và là phần lõi của imem_port. Giao thức: docs/spec/core.md mục 5.1.
//
// Đọc và ghi đủ word (be = 4'b1111): req_ready = 1, rsp_valid ở chu kỳ ngay sau.
// Ghi byte/half (SB, SH): macro không có chân ghi theo byte nên đọc, sửa, ghi
// (spec SoC mục 7.3). Chu kỳ 1 đọc word cũ với req_ready = 0 (wait state), chu
// kỳ 2 ghép byte mới theo be và ghi, req_ready = 1. Master giữ nguyên yêu cầu
// trong wait state (luật 1) nên chu kỳ 2 vẫn có đủ addr, be, wdata.
//
// rsp_rdata = Q của macro ở chu kỳ phản hồi của lệnh đọc, bằng 0 với lệnh ghi
// (Q của macro sau chu kỳ ghi không xác định). Không có err: sys_bus đã chặn
// địa chỉ ngoài vùng.
//
// Cổng f_*: cổng đọc ưu tiên thấp cho lấy lệnh (imem_port). Bus luôn thắng:
// f_gnt = 0 trong mọi chu kỳ có req_valid, kể cả wait state của đọc-sửa-ghi.
// DMEM nối f_req = 0, Genus tự bỏ phần logic này.

module sram_wrap #(
    parameter BANK_W = 2,               // số macro = 2^BANK_W, mỗi macro 4 KB
    parameter AW     = 10 + BANK_W      // độ rộng địa chỉ word, không đặt lại
) (
    input  wire          clk,
    input  wire          rst_n,

    // Slave valid/ready
    input  wire          req_valid,
    output wire          req_ready,
    input  wire [31:0]   req_addr,      // dùng addr[AW+1:2]
    input  wire          req_we,
    input  wire [3:0]    req_be,
    input  wire [31:0]   req_wdata,
    output reg           rsp_valid,
    output wire [31:0]   rsp_rdata,

    // Cổng đọc ưu tiên thấp
    input  wire          f_req,
    output wire          f_gnt,
    input  wire [AW-1:0] f_addr,        // địa chỉ word
    output wire [31:0]   f_rdata        // chu kỳ sau f_req && f_gnt
);

    reg  rmw_q;         // chu kỳ trước đã đọc word cũ cho lệnh ghi một phần
    reg  rd_q;          // chu kỳ trước nhận một lệnh đọc

    wire part = req_we & (req_be != 4'hF);
    assign req_ready = ~part | rmw_q;
    wire acc = req_valid & req_ready;

    // Mảng macro. Có req_valid thì bus dùng macro: ghi khi lệnh ghi được nhận,
    // còn lại là đọc (lệnh đọc, hoặc chu kỳ đọc của đọc-sửa-ghi).
    wire [31:0] q;
    wire [31:0] merged;

    assign merged[ 7: 0] = req_be[0] ? req_wdata[ 7: 0] : q[ 7: 0];
    assign merged[15: 8] = req_be[1] ? req_wdata[15: 8] : q[15: 8];
    assign merged[23:16] = req_be[2] ? req_wdata[23:16] : q[23:16];
    assign merged[31:24] = req_be[3] ? req_wdata[31:24] : q[31:24];

    sram_array #(.BANK_W(BANK_W)) u_arr (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (req_valid | f_req),
        .we    (acc & req_we),
        .addr  (req_valid ? req_addr[AW+1:2] : f_addr),
        .wdata (rmw_q ? merged : req_wdata),
        .rdata (q)
    );

    assign f_gnt   = ~req_valid;
    assign f_rdata = q;

    // Phản hồi
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rmw_q     <= 1'b0;
            rd_q      <= 1'b0;
            rsp_valid <= 1'b0;
        end else begin
            rmw_q     <= req_valid & part & ~rmw_q;
            rd_q      <= acc & ~req_we;
            rsp_valid <= acc;
        end
    end

    assign rsp_rdata = {32{rd_q}} & q;

    // Bit địa chỉ ngoài mảng do sys_bus giải mã, bit 1:0 không dùng (truy cập theo word và be)
    wire unused_addr = &{1'b0, req_addr[31:AW+2], req_addr[1:0]};

endmodule

`default_nettype wire
