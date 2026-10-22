`timescale 1ns/1ps
`default_nettype none
// imem_port - IMEM (mảng SRAM macro) dùng chung cho cổng lệnh của core và bus
// dữ liệu, kèm boot ROM (RTL-08).
//
// Cổng lệnh (docs/spec/core.md mục 4.3, 4.10): địa chỉ được nhận khi
// if_req && if_gnt, lệnh và lỗi có ở chu kỳ sau.
//   IMEM      0x0000_0000, 4 KB << BANK_W   if_gnt = 0 khi bus đang dùng IMEM
//   Boot ROM  0x0001_0000, 1 KB             if_gnt = 1 luôn (không chung với bus)
//   còn lại                                 if_gnt = 1, chu kỳ sau if_err = 1
//
// Cổng dữ liệu (slave của sys_bus): đọc/ghi IMEM để nạp chương trình và cho
// FENCE.I. Bus được ưu tiên, IF mất 1 chu kỳ mỗi lần bus dùng IMEM (2 chu kỳ
// với ghi byte/half vì đọc-sửa-ghi). Giống mô hình IMEM trong tb_core.
`include "soc_map.vh"

module imem_port #(
    parameter BANK_W = `SOC_IMEM_BANK_W,    // phải bằng IMEM_BANK_W của sys_bus
    parameter AW     = 10 + BANK_W          // độ rộng địa chỉ word, không đặt lại
) (
    input  wire        clk,
    input  wire        rst_n,

    // Cổng lệnh của core
    input  wire        if_req,
    input  wire [31:0] if_addr,
    output wire        if_gnt,
    output wire [31:0] if_rdata,
    output wire        if_err,

    // Cổng dữ liệu (sys_bus)
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire        req_we,
    input  wire [3:0]  req_be,
    input  wire [31:0] req_wdata,
    output wire        rsp_valid,
    output wire [31:0] rsp_rdata
);

    localparam [31:0] BOOT_BASE = `SOC_BOOT_BASE;

    // Giải mã địa chỉ lấy lệnh
    wire f_imem = (if_addr[31:AW+2] == {(30-AW){1'b0}});
    wire f_boot = (if_addr[31:10] == BOOT_BASE[31:10]);

    wire        sram_f_gnt;
    wire [31:0] sram_q;
    wire [31:0] rom_q;

    assign if_gnt = f_imem ? sram_f_gnt : 1'b1;
    wire   f_acc  = if_req & if_gnt;

    sram_wrap #(.BANK_W(BANK_W)) u_sram (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_we    (req_we),
        .req_be    (req_be),
        .req_wdata (req_wdata),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata),
        .f_req     (if_req & f_imem),
        .f_gnt     (sram_f_gnt),
        .f_addr    (if_addr[AW+1:2]),
        .f_rdata   (sram_q)
    );

    boot_rom u_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (f_acc & f_boot),
        .addr  (if_addr[9:2]),
        .q     (rom_q)
    );

    // Nguồn của lệnh ở chu kỳ sau
    reg rom_sel_q;
    reg err_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_sel_q <= 1'b0;
            err_q     <= 1'b0;
        end else begin
            rom_sel_q <= f_acc & f_boot;
            err_q     <= f_acc & ~f_imem & ~f_boot;
        end
    end

    assign if_err   = err_q;
    assign if_rdata = rom_sel_q ? rom_q :
                      err_q     ? 32'h0 : sram_q;

    // Bit 1:0 của địa chỉ lệnh: core đã bẫy nhảy lệch
    wire unused_if = &{1'b0, if_addr[1:0]};

endmodule

`default_nettype wire
