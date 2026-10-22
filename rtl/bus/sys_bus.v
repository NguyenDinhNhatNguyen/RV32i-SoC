`timescale 1ns/1ps
`default_nettype none
// sys_bus - interconnect valid/ready của SoC (RTL-03).
// Giao thức: docs/spec/core.md mục 5.1. Bản đồ địa chỉ: rtl/bus/soc_map.vh.
// Timing diagram: docs/timing_bus.md. Lý do thiết kế: docs/bus_mem.md.
//
// Master: N_MASTER cổng (1 là cổng dữ liệu của core, 2 khi có DMA), trọng tài
// round-robin. Slave: cổng dữ liệu của IMEM (imem_port), DMEM (sram_wrap),
// cầu APB (vùng 0x2, 0x3, 0x4, apb_bridge) và slave lỗi bên trong.
//
// Cả bus chỉ có tối đa 1 yêu cầu đang chờ phản hồi. Yêu cầu mới được nhận khi
// không có gì chờ, hoặc ngay trong chu kỳ có phản hồi của yêu cầu trước (luật 3).
// Với 1 master, cách này không thêm chu kỳ nào so với nối thẳng master vào
// slave: load liên tiếp vào SRAM vẫn được 1 lệnh mỗi chu kỳ.
//
// Yêu cầu đã hiện ra ở slave mà slave chưa nhận (ready = 0) thì quyền được giữ
// cho master đó đến khi được nhận, để slave luôn thấy yêu cầu giữ nguyên (luật 1).
//
// Slave lỗi: địa chỉ không ánh xạ (ngoài kích thước IMEM/DMEM, bus dữ liệu đọc
// boot ROM, vùng khác 0x0-0x4) được nhận ngay, chu kỳ sau có rsp_valid với
// err = 1, rdata = 0. Khe APB trống hoặc tính năng đang tắt do apb_bridge trả err.
//
// Đường tổ hợp: m_req_ready phụ thuộc m_req_valid và rsp_valid của slave (từ
// flop ở slave). Không có đường từ ready của slave ngược về valid (luật 5).
`include "soc_map.vh"

module sys_bus #(
    parameter N_MASTER    = 1,                  // 1, 2 hoặc 4
    parameter IMEM_BANK_W = `SOC_IMEM_BANK_W,   // phải bằng BANK_W của imem_port
    parameter DMEM_BANK_W = `SOC_DMEM_BANK_W    // phải bằng BANK_W của sram_wrap DMEM
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Master, gộp phẳng: master i ở lát [i] hoặc [i*32 +: 32]
    input  wire [N_MASTER-1:0]    m_req_valid,
    output wire [N_MASTER-1:0]    m_req_ready,
    input  wire [N_MASTER*32-1:0] m_addr,
    input  wire [N_MASTER-1:0]    m_we,
    input  wire [N_MASTER*4-1:0]  m_be,
    input  wire [N_MASTER*32-1:0] m_wdata,
    output wire [N_MASTER-1:0]    m_rsp_valid,
    output wire [31:0]            m_rsp_rdata,  // chung, chỉ có nghĩa với master có rsp_valid
    output wire [N_MASTER-1:0]    m_rsp_err,    // riêng từng master, bằng 0 khi không có rsp_valid

    // Kênh yêu cầu chung cho mọi slave, mỗi slave có valid riêng
    output wire [31:0]            s_addr,
    output wire                   s_we,
    output wire [3:0]             s_be,
    output wire [31:0]            s_wdata,

    // Cổng dữ liệu IMEM (imem_port)
    output wire                   imem_req_valid,
    input  wire                   imem_req_ready,
    input  wire                   imem_rsp_valid,
    input  wire [31:0]            imem_rsp_rdata,

    // DMEM (sram_wrap)
    output wire                   dmem_req_valid,
    input  wire                   dmem_req_ready,
    input  wire                   dmem_rsp_valid,
    input  wire [31:0]            dmem_rsp_rdata,

    // Cầu APB (apb_bridge)
    output wire                   apb_req_valid,
    input  wire                   apb_req_ready,
    input  wire                   apb_rsp_valid,
    input  wire [31:0]            apb_rsp_rdata,
    input  wire                   apb_rsp_err
);

    localparam MW = (N_MASTER > 2) ? 2 : 1;     // độ rộng chỉ số master
    localparam [MW-1:0] ONE = 1;

    localparam [31:0] IMEM_SIZE = 32'd4096 << IMEM_BANK_W;
    localparam [31:0] DMEM_SIZE = 32'd4096 << DMEM_BANK_W;

    localparam [1:0] S_IMEM = 2'd0,
                     S_DMEM = 2'd1,
                     S_APB  = 2'd2,
                     S_ERR  = 2'd3;

    reg           pend_q;       // có yêu cầu đã nhận, chưa có phản hồi
    reg  [1:0]    pend_slv_q;   // slave sẽ trả phản hồi đó
    reg  [MW-1:0] pend_mst_q;   // master nhận phản hồi đó
    reg           hold_q;       // chu kỳ trước yêu cầu hiện ra ở slave mà chưa được nhận
    reg  [MW-1:0] hold_mst_q;
    reg  [MW-1:0] rr_q;         // master được nhận gần nhất

    // Trọng tài round-robin: duyệt rr_q, rr_q-1, ... , rr_q+1. Master hợp lệ
    // duyệt sau cùng thắng, nên ưu tiên cao nhất là rr_q+1, thấp nhất là rr_q.
    reg  [MW-1:0] rr_pick;
    reg  [MW-1:0] cand;
    integer       k;

    always @(*) begin
        rr_pick = rr_q;
        cand    = rr_q;
        for (k = 0; k < N_MASTER; k = k + 1) begin
            if (m_req_valid[cand])
                rr_pick = cand;
            cand = cand - ONE;
        end
    end

    wire [MW-1:0] g       = hold_q ? hold_mst_q : rr_pick;   // master được chọn
    wire          g_valid = m_req_valid[g];

    assign s_addr  = m_addr [g*32 +: 32];
    assign s_we    = m_we   [g];
    assign s_be    = m_be   [g*4 +: 4];
    assign s_wdata = m_wdata[g*32 +: 32];

    // Giải mã địa chỉ: addr[31:28] chọn vùng. Vùng 0x0 chỉ có IMEM ở bus dữ
    // liệu (boot ROM ở 0x0001_0000 nằm ngoài IMEM_SIZE nên vào slave lỗi).
    reg [1:0] slv;
    always @(*) begin
        case (s_addr[31:28])
            `SOC_RGN_MEM0:   slv = ({4'h0, s_addr[27:0]} < IMEM_SIZE) ? S_IMEM : S_ERR;
            `SOC_RGN_DMEM:   slv = ({4'h0, s_addr[27:0]} < DMEM_SIZE) ? S_DMEM : S_ERR;
            `SOC_RGN_PERIPH,
            `SOC_RGN_ACCEL,
            `SOC_RGN_DMA:    slv = S_APB;
            default:         slv = S_ERR;
        endcase
    end

    // Phản hồi của yêu cầu đang chờ, slave lỗi trả lời ở chu kỳ ngay sau
    reg rsp_src_valid;
    always @(*) begin
        case (pend_slv_q)
            S_IMEM:  rsp_src_valid = imem_rsp_valid;
            S_DMEM:  rsp_src_valid = dmem_rsp_valid;
            S_APB:   rsp_src_valid = apb_rsp_valid;
            default: rsp_src_valid = 1'b1;
        endcase
    end

    wire rsp_fire = pend_q & rsp_src_valid;
    wire rsp_err  = (pend_slv_q == S_APB) ? apb_rsp_err : (pend_slv_q == S_ERR);

    assign m_rsp_rdata = (pend_slv_q == S_IMEM) ? imem_rsp_rdata :
                         (pend_slv_q == S_DMEM) ? dmem_rsp_rdata :
                         (pend_slv_q == S_APB)  ? apb_rsp_rdata  : 32'h0;

    // Yêu cầu tới slave
    wire can_acc = ~pend_q | rsp_fire;          // luật 3
    wire vis     = g_valid & can_acc;           // yêu cầu hiện ra ở slave

    assign imem_req_valid = vis & (slv == S_IMEM);
    assign dmem_req_valid = vis & (slv == S_DMEM);
    assign apb_req_valid  = vis & (slv == S_APB);

    reg slv_ready;
    always @(*) begin
        case (slv)
            S_IMEM:  slv_ready = imem_req_ready;
            S_DMEM:  slv_ready = dmem_req_ready;
            S_APB:   slv_ready = apb_req_ready;
            default: slv_ready = 1'b1;
        endcase
    end

    wire acc = vis & slv_ready;                 // yêu cầu được nhận chu kỳ này

    // Giải mã one-hot chỉ số master cho ready và rsp_valid
    reg [N_MASTER-1:0] g_oh;
    reg [N_MASTER-1:0] p_oh;
    integer j;
    always @(*) begin
        for (j = 0; j < N_MASTER; j = j + 1) begin
            g_oh[j] = (g          == j[MW-1:0]);
            p_oh[j] = (pend_mst_q == j[MW-1:0]);
        end
    end

    assign m_req_ready = {N_MASTER{acc}} & g_oh;
    assign m_rsp_valid = {N_MASTER{rsp_fire}} & p_oh;
    assign m_rsp_err   = {N_MASTER{rsp_fire & rsp_err}} & p_oh;

    // Trạng thái
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_q     <= 1'b0;
            pend_slv_q <= S_ERR;
            pend_mst_q <= {MW{1'b0}};
            hold_q     <= 1'b0;
            hold_mst_q <= {MW{1'b0}};
            rr_q       <= {MW{1'b0}};
        end else begin
            hold_q <= vis & ~slv_ready;
            if (vis & ~slv_ready)
                hold_mst_q <= g;
            if (acc) begin
                pend_q     <= 1'b1;
                pend_slv_q <= slv;
                pend_mst_q <= g;
                rr_q       <= g;
            end else if (rsp_fire) begin
                pend_q     <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
