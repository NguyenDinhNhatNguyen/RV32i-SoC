`timescale 1ns/1ps
`default_nettype none
// rv32_csr - thanh ghi CSR machine mode (docs/spec/core.md mục 4.7, 4.8).
//
// Hai cổng truy cập:
//   - Cổng kiểm tra (tổ hợp, dùng ở EX): địa chỉ có tồn tại không, có ghi
//     vào CSR chỉ đọc không. Lệnh CSR sai được gắn ngoại lệ illegal ngay ở
//     EX như mọi ngoại lệ khác.
//   - Cổng đọc/ghi (dùng ở WB): đọc giá trị cũ, ghi giá trị mới theo phép
//     RW/RS/RC khi wr_en_i = 1.
// Trap và MRET cập nhật mstatus, mepc, mcause, mtval tại WB.
// mcycle tăng mỗi chu kỳ, minstret tăng khi instret_i = 1. Lệnh ghi bộ đếm
// (cả nửa thấp lẫn nửa cao) thay cho lần tăng trong chu kỳ đó.
`include "rv32_defs.vh"

module rv32_csr #(
    parameter ENABLE_M = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    // Cổng kiểm tra (EX)
    input  wire [11:0] chk_addr_i,
    input  wire        chk_we_i,       // lệnh CSR có ghi (csr_we của decoder)
    output reg         chk_illegal_o,

    // Cổng đọc/ghi (WB)
    input  wire [11:0] addr_i,
    input  wire [1:0]  op_i,           // RV_CSR_RW / RS / RC
    input  wire [31:0] wdata_i,        // rs1 hoặc uimm
    input  wire        wr_en_i,        // ghi trong chu kỳ này
    output reg  [31:0] rdata_o,

    // Trap, MRET, đếm lệnh (WB)
    input  wire        trap_i,
    input  wire [31:2] trap_pc_i,      // PC luôn thẳng hàng 4 byte
    input  wire        trap_int_i,     // ngắt: mcause bit 31 = 1
    input  wire [4:0]  trap_cause_i,
    input  wire [31:0] trap_tval_i,
    input  wire        mret_i,
    input  wire        instret_i,
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,

    // Ngắt
    input  wire        irq_software_i,
    input  wire        irq_timer_i,
    input  wire        irq_external_i,
    input  wire [63:0] mtime_i,
    output wire        irq_pending_o,  // (mip & mie) != 0, đánh thức WFI
    output wire        irq_take_o,     // pending và mstatus.MIE = 1
    output wire [4:0]  irq_cause_o     // MEI > MSI > MTI
);

    // ---- Thanh ghi ------------------------------------------------------------
    reg        mstatus_mie_q, mstatus_mpie_q;
    reg        mie_msie_q, mie_mtie_q, mie_meie_q;
    reg [31:2] mtvec_q;
    reg [31:0] mscratch_q;
    reg [31:2] mepc_q;
    reg        mcause_int_q;
    reg [4:0]  mcause_code_q;    // WLRL: chỉ giữ mã hợp lệ (0..11)
    reg [31:0] mtval_q;
    reg [63:0] mcycle_q, minstret_q;

    wire [31:0] misa = `RV_MISA_BASE | ((ENABLE_M != 0) ? `RV_MISA_M : 32'h0);

    // MPP cố định 11 (chỉ có M-mode), bit khác đọc 0
    reg [31:0] mstatus, mip, mie;

    always @(*) begin
        mstatus = 32'h0;
        mstatus[`RV_MSTATUS_MIE]                         = mstatus_mie_q;
        mstatus[`RV_MSTATUS_MPIE]                        = mstatus_mpie_q;
        mstatus[`RV_MSTATUS_MPP_HI:`RV_MSTATUS_MPP_LO]   = 2'b11;
        mip = 32'h0;
        mip[`RV_MI_MSI] = irq_software_i;
        mip[`RV_MI_MTI] = irq_timer_i;
        mip[`RV_MI_MEI] = irq_external_i;
        mie = 32'h0;
        mie[`RV_MI_MSI] = mie_msie_q;
        mie[`RV_MI_MTI] = mie_mtie_q;
        mie[`RV_MI_MEI] = mie_meie_q;
    end

    assign mtvec_o = {mtvec_q, 2'b00};
    assign mepc_o  = {mepc_q, 2'b00};

    // ---- Cổng kiểm tra: CSR có tồn tại không ----------------------------------
    always @(*) begin
        case (chk_addr_i)
            `RV_CSR_MSTATUS, `RV_CSR_MISA, `RV_CSR_MIE, `RV_CSR_MTVEC,
            `RV_CSR_MSCRATCH, `RV_CSR_MEPC, `RV_CSR_MCAUSE, `RV_CSR_MTVAL,
            `RV_CSR_MIP, `RV_CSR_MCYCLE, `RV_CSR_MINSTRET, `RV_CSR_MCYCLEH,
            `RV_CSR_MINSTRETH, `RV_CSR_CYCLE, `RV_CSR_TIME, `RV_CSR_INSTRET,
            `RV_CSR_CYCLEH, `RV_CSR_TIMEH, `RV_CSR_INSTRETH, `RV_CSR_MVENDORID,
            `RV_CSR_MARCHID, `RV_CSR_MIMPID, `RV_CSR_MHARTID:
                chk_illegal_o = 1'b0;
            default:
                chk_illegal_o = 1'b1;
        endcase
        // addr[11:10] = 11: CSR chỉ đọc
        if (chk_we_i && (chk_addr_i[11:10] == 2'b11))
            chk_illegal_o = 1'b1;
    end

    // ---- Cổng đọc ----------------------------------------------------------------
    // Lệnh tới đây đã qua cổng kiểm tra, địa chỉ không tồn tại đọc 0.
    always @(*) begin
        case (addr_i)
            `RV_CSR_MSTATUS:   rdata_o = mstatus;
            `RV_CSR_MISA:      rdata_o = misa;
            `RV_CSR_MIE:       rdata_o = mie;
            `RV_CSR_MTVEC:     rdata_o = mtvec_o;
            `RV_CSR_MSCRATCH:  rdata_o = mscratch_q;
            `RV_CSR_MEPC:      rdata_o = mepc_o;
            `RV_CSR_MCAUSE:    rdata_o = {mcause_int_q, 26'h0, mcause_code_q};
            `RV_CSR_MTVAL:     rdata_o = mtval_q;
            `RV_CSR_MIP:       rdata_o = mip;
            `RV_CSR_MCYCLE,
            `RV_CSR_CYCLE:     rdata_o = mcycle_q[31:0];
            `RV_CSR_MCYCLEH,
            `RV_CSR_CYCLEH:    rdata_o = mcycle_q[63:32];
            `RV_CSR_MINSTRET,
            `RV_CSR_INSTRET:   rdata_o = minstret_q[31:0];
            `RV_CSR_MINSTRETH,
            `RV_CSR_INSTRETH:  rdata_o = minstret_q[63:32];
            `RV_CSR_TIME:      rdata_o = mtime_i[31:0];
            `RV_CSR_TIMEH:     rdata_o = mtime_i[63:32];
            default:           rdata_o = 32'h0;   // mvendorid, marchid, mimpid, mhartid
        endcase
    end

    // ---- Giá trị ghi --------------------------------------------------------------
    reg [31:0] wval;

    always @(*) begin
        case (op_i)
            `RV_CSR_RS: wval = rdata_o | wdata_i;
            `RV_CSR_RC: wval = rdata_o & ~wdata_i;
            default:    wval = wdata_i;
        endcase
    end

    wire wr_mstatus   = wr_en_i & (addr_i == `RV_CSR_MSTATUS);
    wire wr_mie       = wr_en_i & (addr_i == `RV_CSR_MIE);
    wire wr_mtvec     = wr_en_i & (addr_i == `RV_CSR_MTVEC);
    wire wr_mscratch  = wr_en_i & (addr_i == `RV_CSR_MSCRATCH);
    wire wr_mepc      = wr_en_i & (addr_i == `RV_CSR_MEPC);
    wire wr_mcause    = wr_en_i & (addr_i == `RV_CSR_MCAUSE);
    wire wr_mtval     = wr_en_i & (addr_i == `RV_CSR_MTVAL);
    wire wr_mcycle    = wr_en_i & (addr_i == `RV_CSR_MCYCLE);
    wire wr_mcycleh   = wr_en_i & (addr_i == `RV_CSR_MCYCLEH);
    wire wr_minstret  = wr_en_i & (addr_i == `RV_CSR_MINSTRET);
    wire wr_minstreth = wr_en_i & (addr_i == `RV_CSR_MINSTRETH);

    // ---- mstatus ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie_q  <= 1'b0;
            mstatus_mpie_q <= 1'b0;
        end else if (trap_i) begin
            mstatus_mpie_q <= mstatus_mie_q;
            mstatus_mie_q  <= 1'b0;
        end else if (mret_i) begin
            mstatus_mie_q  <= mstatus_mpie_q;
            mstatus_mpie_q <= 1'b1;
        end else if (wr_mstatus) begin
            mstatus_mie_q  <= wval[`RV_MSTATUS_MIE];
            mstatus_mpie_q <= wval[`RV_MSTATUS_MPIE];
        end
    end

    // ---- mie, mtvec, mscratch -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mie_msie_q <= 1'b0;
            mie_mtie_q <= 1'b0;
            mie_meie_q <= 1'b0;
        end else if (wr_mie) begin
            mie_msie_q <= wval[`RV_MI_MSI];
            mie_mtie_q <= wval[`RV_MI_MTI];
            mie_meie_q <= wval[`RV_MI_MEI];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mtvec_q <= 30'h0;
        else if (wr_mtvec)
            mtvec_q <= wval[31:2];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mscratch_q <= 32'h0;
        else if (wr_mscratch)
            mscratch_q <= wval;
    end

    // ---- mepc, mcause, mtval: trap ưu tiên hơn lệnh ghi (không xảy ra cùng lúc) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mepc_q        <= 30'h0;
            mcause_int_q  <= 1'b0;
            mcause_code_q <= 5'd0;
            mtval_q       <= 32'h0;
        end else if (trap_i) begin
            mepc_q        <= trap_pc_i;
            mcause_int_q  <= trap_int_i;
            mcause_code_q <= trap_cause_i;
            mtval_q       <= trap_tval_i;
        end else begin
            if (wr_mepc)
                mepc_q <= wval[31:2];
            if (wr_mcause) begin
                mcause_int_q  <= wval[`RV_MCAUSE_INT_BIT];
                mcause_code_q <= wval[4:0];
            end
            if (wr_mtval)
                mtval_q <= wval;
        end
    end

    // ---- Bộ đếm 64 bit ---------------------------------------------------------------
    wire [63:0] mcycle_inc   = mcycle_q + 64'd1;
    wire [63:0] minstret_inc = minstret_q + 64'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mcycle_q <= 64'h0;
        else if (wr_mcycle)
            mcycle_q[31:0] <= wval;
        else if (wr_mcycleh)
            mcycle_q[63:32] <= wval;
        else
            mcycle_q <= mcycle_inc;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            minstret_q <= 64'h0;
        else if (wr_minstret)
            minstret_q[31:0] <= wval;
        else if (wr_minstreth)
            minstret_q[63:32] <= wval;
        else if (instret_i)
            minstret_q <= minstret_inc;
    end

    // ---- Ngắt ----------------------------------------------------------------------
    wire msi = irq_software_i & mie_msie_q;
    wire mti = irq_timer_i    & mie_mtie_q;
    wire mei = irq_external_i & mie_meie_q;

    assign irq_pending_o = msi | mti | mei;
    assign irq_take_o    = irq_pending_o & mstatus_mie_q;

    assign irq_cause_o = mei ? `RV_INT_MEI :
                         msi ? `RV_INT_MSI : `RV_INT_MTI;

endmodule

`default_nettype wire
