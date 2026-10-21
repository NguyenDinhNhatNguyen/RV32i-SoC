`timescale 1ns/1ps
`default_nettype none
// rv32_core - pipeline RV32I 3 tầng IF / EX / WB, chỉ machine mode.
//
//   IF : if_pc_q đưa thẳng từ flop ra địa chỉ IMEM.
//   EX : lệnh lấy thẳng từ ngõ ra IMEM đọc đồng bộ (hoặc từ ex_instr_hold_q
//        khi EX dừng). Giải mã, đọc register file, forward WB->EX, ALU,
//        so sánh nhánh, phát yêu cầu bus cho load/store.
//   WB : căn chỉnh dữ liệu load, ghi register file.
//
// Dừng: WB chờ d_rsp_valid_i, hoặc yêu cầu bus của EX chưa được nhận, sẽ
// giữ IF và EX (và giữ cả WB trong trường hợp đầu).
//
// Phạm vi P3 (chưa có CSR/trap): ngoại lệ được phát hiện ở EX, lệnh đi tới
// WB mang cờ và không có tác dụng phụ. Lệnh SYSTEM, FENCE.I và RV32M cũng
// được gắn cờ "chưa hỗ trợ" theo cách đó. tb_core dừng mô phỏng khi lệnh
// như vậy tới WB.
`include "rv32_defs.vh"

module rv32_core #(
    parameter        ENABLE_M = 0,
    parameter [31:0] RESET_PC = `RV_RESET_PC_DEFAULT
) (
    input  wire        clk,
    input  wire        rst_n,

    // Cổng lệnh: địa chỉ được nhận khi if_req_o && if_gnt_i,
    // lệnh và lỗi có ở chu kỳ sau.
    output wire        if_req_o,
    output wire [31:0] if_addr_o,
    input  wire        if_gnt_i,
    input  wire [31:0] if_rdata_i,
    input  wire        if_err_i,

    // Kênh yêu cầu bus dữ liệu (docs/spec/core.md mục 5.1)
    output wire        d_req_valid_o,
    input  wire        d_req_ready_i,
    output wire [31:0] d_addr_o,
    output wire        d_we_o,
    output wire [3:0]  d_be_o,
    output wire [31:0] d_wdata_o,

    // Kênh phản hồi bus dữ liệu
    input  wire        d_rsp_valid_i,
    input  wire [31:0] d_rsp_rdata_i,
    input  wire        d_rsp_err_i
);

    // =======================================================================
    // Điều khiển pipeline (khai báo trước vì mọi tầng đều dùng)
    // =======================================================================
    wire wb_wait;      // WB giữ load/store đang chờ phản hồi
    wire ex_wait;      // yêu cầu bus của EX chưa được nhận trong chu kỳ này
    wire pipe_stall = wb_wait | ex_wait;
    wire ex_go      = ~pipe_stall;   // EX chuyển lệnh (hoặc bubble) sang WB

    // =======================================================================
    // IF
    // =======================================================================
    reg  [31:0] if_pc_q;
    wire        ex_redirect;        // nhánh/nhảy có nhảy rời EX trong chu kỳ này
    wire [31:0] ex_target;

    // Luôn lấy lệnh. P4 sẽ xoá khi ngủ do WFI.
    assign if_req_o  = 1'b1;
    assign if_addr_o = if_pc_q;

    wire if_fire = if_req_o & if_gnt_i;

    // Chuyển hướng đi vào flop, không bao giờ đi tổ hợp ra if_addr_o.
    // Không được cấp quyền thì chu kỳ sau phát lại cùng địa chỉ.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            if_pc_q <= RESET_PC;
        else if (ex_redirect)
            if_pc_q <= ex_target;
        else if (ex_go & if_fire)
            if_pc_q <= if_pc_q + 32'd4;
    end

    // =======================================================================
    // EX
    // =======================================================================
    reg         ex_fetch_q;       // ngõ ra IMEM đang chứa lệnh thật
    reg  [31:0] ex_pc_q;
    reg         ex_hold_q;        // lệnh đang nằm trong thanh ghi giữ
    reg  [31:0] ex_instr_hold_q;
    reg         ex_ferr_hold_q;

    wire        ex_valid = ex_fetch_q | ex_hold_q;
    wire [31:0] ex_instr = ex_hold_q ? ex_instr_hold_q : if_rdata_i;
    wire        ex_ferr  = ex_hold_q ? ex_ferr_hold_q  : if_err_i;

    // Lệnh đang được lấy khi lệnh nhảy rời EX là PC+4 sai đường, bị huỷ ở
    // đây (phạt 1 chu kỳ). Lệnh lấy trong lúc dừng cũng bị huỷ vì sau đó
    // được lấy lại từ if_pc_q không đổi.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_fetch_q <= 1'b0;
        else
            ex_fetch_q <= ex_go & if_fire & ~ex_redirect;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_pc_q <= 32'h0;
        else if (ex_go & if_fire)
            ex_pc_q <= if_pc_q;
    end

    // Ngõ ra IMEM chỉ đúng trong một chu kỳ (if_pc_q đã trỏ tới lệnh kế),
    // nên lệnh bị dừng được chốt ở chu kỳ dừng đầu tiên và đọc lại từ đây
    // đến khi hết dừng.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_hold_q <= 1'b0;
        else
            ex_hold_q <= pipe_stall & ex_valid;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_instr_hold_q <= `RV_INSTR_NOP;
            ex_ferr_hold_q  <= 1'b0;
        end else if (pipe_stall & ex_fetch_q) begin
            ex_instr_hold_q <= if_rdata_i;
            ex_ferr_hold_q  <= if_err_i;
        end
    end

    // ---- Giải mã -----------------------------------------------------------
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [2:0]  ex_funct3;
    wire [11:0] ex_csr_addr;
    wire        ex_illegal, ex_rd_we;
    wire [2:0]  ex_imm_type;
    wire [3:0]  ex_alu_op;
    wire [1:0]  ex_alu_a_sel;
    wire        ex_alu_b_sel;
    wire [1:0]  ex_wb_sel;
    wire        ex_branch, ex_jal, ex_jalr, ex_load, ex_store, ex_md;
    wire        ex_csr, ex_csr_we, ex_ecall, ex_ebreak, ex_mret, ex_wfi, ex_fence_i;

    rv32_decoder #(
        .ENABLE_M (ENABLE_M)
    ) u_decoder (
        .instr_i     (ex_instr),
        .rs1_addr_o  (ex_rs1_addr),
        .rs2_addr_o  (ex_rs2_addr),
        .rd_addr_o   (ex_rd_addr),
        .funct3_o    (ex_funct3),
        .csr_addr_o  (ex_csr_addr),
        .illegal_o   (ex_illegal),
        .rd_we_o     (ex_rd_we),
        .imm_type_o  (ex_imm_type),
        .alu_op_o    (ex_alu_op),
        .alu_a_sel_o (ex_alu_a_sel),
        .alu_b_sel_o (ex_alu_b_sel),
        .wb_sel_o    (ex_wb_sel),
        .branch_o    (ex_branch),
        .jal_o       (ex_jal),
        .jalr_o      (ex_jalr),
        .load_o      (ex_load),
        .store_o     (ex_store),
        .md_o        (ex_md),
        .csr_o       (ex_csr),
        .csr_we_o    (ex_csr_we),
        .ecall_o     (ex_ecall),
        .ebreak_o    (ex_ebreak),
        .mret_o      (ex_mret),
        .wfi_o       (ex_wfi),
        .fence_i_o   (ex_fence_i)
    );

    wire [31:0] ex_imm;

    rv32_imm_gen u_imm_gen (
        .instr_i    (ex_instr[31:7]),
        .imm_type_i (ex_imm_type),
        .imm_o      (ex_imm)
    );

    // ---- Register file và forward WB->EX -------------------------------------
    wire        wb_rf_we;
    reg  [4:0]  wb_rd_q;
    wire [31:0] wb_rd_data;
    reg         wb_valid_q;
    reg         wb_rd_we_q;
    wire [31:0] rf_rs1_data, rf_rs2_data;

    rv32_regfile u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .we_i       (wb_rf_we),
        .rd_addr_i  (wb_rd_q),
        .rd_data_i  (wb_rd_data),
        .rs1_addr_i (ex_rs1_addr),
        .rs1_data_o (rf_rs1_data),
        .rs2_addr_i (ex_rs2_addr),
        .rs2_data_o (rf_rs2_data)
    );

    // wb_rd_we_q đã bằng 0 khi rd = x0 và khi lệnh mang cờ.
    // Giá trị WB vẫn được forward khi load đang chờ phản hồi. Lúc đó EX
    // đang dừng nên không có gì dùng giá trị cũ.
    wire wb_fwd_ok   = wb_valid_q & wb_rd_we_q;
    wire ex_fwd_rs1  = wb_fwd_ok & (wb_rd_q == ex_rs1_addr);
    wire ex_fwd_rs2  = wb_fwd_ok & (wb_rd_q == ex_rs2_addr);

    wire [31:0] ex_rs1 = ex_fwd_rs1 ? wb_rd_data : rf_rs1_data;
    wire [31:0] ex_rs2 = ex_fwd_rs2 ? wb_rd_data : rf_rs2_data;

    // ---- ALU ----------------------------------------------------------------
    reg  [31:0] ex_alu_a;
    wire [31:0] ex_alu_b = (ex_alu_b_sel == `RV_ALU_B_IMM) ? ex_imm : ex_rs2;
    wire [31:0] ex_alu_res;

    always @(*) begin
        ex_alu_a = ex_rs1;
        case (ex_alu_a_sel)
            `RV_ALU_A_PC:   ex_alu_a = ex_pc_q;
            `RV_ALU_A_ZERO: ex_alu_a = 32'h0;
            default:        ex_alu_a = ex_rs1;
        endcase
    end

    rv32_alu u_alu (
        .op_i     (ex_alu_op),
        .a_i      (ex_alu_a),
        .b_i      (ex_alu_b),
        .result_o (ex_alu_res)
    );

    // ---- Nhánh / nhảy --------------------------------------------------------
    // Bộ so sánh riêng, chạy song song với bộ cộng đích (D-007).
    wire ex_eq  = (ex_rs1 == ex_rs2);
    wire ex_lt  = ($signed(ex_rs1) < $signed(ex_rs2));
    wire ex_ltu = (ex_rs1 < ex_rs2);
    reg  ex_br_cond;

    always @(*) begin
        ex_br_cond = 1'b0;
        case (ex_funct3)
            `RV_F3_BEQ:  ex_br_cond = ex_eq;
            `RV_F3_BNE:  ex_br_cond = ~ex_eq;
            `RV_F3_BLT:  ex_br_cond = ex_lt;
            `RV_F3_BGE:  ex_br_cond = ~ex_lt;
            `RV_F3_BLTU: ex_br_cond = ex_ltu;
            `RV_F3_BGEU: ex_br_cond = ~ex_ltu;
            default:     ex_br_cond = 1'b0;
        endcase
    end

    // ALU cho pc+imm (branch/JAL, luôn chẵn) hoặc rs1+imm (JALR, bit 0
    // bị xoá theo đặc tả).
    wire ex_jump = ex_jal | ex_jalr | (ex_branch & ex_br_cond);
    assign ex_target = {ex_alu_res[31:1], 1'b0};

    // ---- Làn byte load/store -----------------------------------------------------
    wire [3:0]  ex_be;
    wire [31:0] ex_wdata;
    wire        ex_mem_misaligned;
    reg  [2:0]  wb_funct3_q;
    reg  [1:0]  wb_addr_lo_q;
    wire [31:0] wb_load_data;

    rv32_lsu_align u_lsu_align (
        .req_size_i       (ex_funct3[1:0]),
        .req_addr_lo_i    (ex_alu_res[1:0]),
        .req_wdata_i      (ex_rs2),
        .req_be_o         (ex_be),
        .req_wdata_o      (ex_wdata),
        .req_misaligned_o (ex_mem_misaligned),
        .rsp_funct3_i     (wb_funct3_q),
        .rsp_addr_lo_i    (wb_addr_lo_q),
        .rsp_rdata_i      (d_rsp_rdata_i),
        .rsp_data_o       (wb_load_data)
    );

    // ---- Ngoại lệ phát hiện ở EX (ưu tiên theo đặc tả Privileged) -------------
    reg       ex_exc;
    reg [4:0] ex_cause;

    always @(*) begin
        ex_exc   = 1'b1;
        ex_cause = `RV_EXC_ILLEGAL;
        if (ex_ferr)
            ex_cause = `RV_EXC_INSTR_ACCESS;
        else if (ex_illegal)
            ex_cause = `RV_EXC_ILLEGAL;
        else if (ex_ebreak)
            ex_cause = `RV_EXC_BREAKPOINT;
        else if (ex_ecall)
            ex_cause = `RV_EXC_ECALL_M;
        else if (ex_jump & ex_target[1])
            ex_cause = `RV_EXC_INSTR_MISALIGNED;
        else if (ex_load & ex_mem_misaligned)
            ex_cause = `RV_EXC_LOAD_MISALIGNED;
        else if (ex_store & ex_mem_misaligned)
            ex_cause = `RV_EXC_STORE_MISALIGNED;
        else
            ex_exc = 1'b0;
    end

    // Thực thi ở WB từ P4 (CSR, MRET, WFI, FENCE.I) hoặc ở M-unit (P7).
    wire ex_unsup = ex_csr | ex_mret | ex_wfi | ex_fence_i | ex_md;

    // ---- Yêu cầu bus dữ liệu ---------------------------------------------------
    // Chỉ một yêu cầu đang chờ. Yêu cầu mới được phát ngay trong chu kỳ
    // phản hồi trước về (lúc đó wb_wait = 0). Không phụ thuộc
    // d_req_ready_i (luật bus 5).
    assign d_req_valid_o = ex_valid & (ex_load | ex_store) & ~ex_exc & ~wb_wait;
    assign d_addr_o      = ex_alu_res;
    assign d_we_o        = ex_store;
    assign d_be_o        = ex_be;
    assign d_wdata_o     = ex_wdata;

    assign ex_wait     = d_req_valid_o & ~d_req_ready_i;
    assign ex_redirect = ex_go & ex_valid & ex_jump & ~ex_exc;

    // JAL/JALR ghi địa chỉ trả về, các lệnh khác ghi kết quả ALU.
    wire [31:0] ex_result = (ex_wb_sel == `RV_WB_PC4) ? (ex_pc_q + 32'd4) : ex_alu_res;

    // =======================================================================
    // WB
    // =======================================================================
    reg  [31:0] wb_pc_q;
    reg  [31:0] wb_instr_q;
    reg  [31:0] wb_result_q;      // kết quả ALU / địa chỉ trả về / địa chỉ load-store
    reg         wb_load_q;
    reg         wb_mem_q;         // đã phát yêu cầu, đang chờ phản hồi
    reg         wb_exc_q;
    reg  [4:0]  wb_cause_q;
    reg         wb_unsup_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_valid_q <= 1'b0;
        else if (ex_go)
            wb_valid_q <= ex_valid;
        else if (!wb_wait)
            wb_valid_q <= 1'b0;   // WB hoàn thành lệnh trong lúc EX chờ d_req_ready_i
    end

    // Chỉ nạp khi có lệnh thật (làm enable cho clock gating, và X từ ngõ ra
    // IMEM lúc rảnh không lọt vào các flop này).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_pc_q      <= 32'h0;
            wb_instr_q   <= `RV_INSTR_NOP;
            wb_rd_q      <= 5'd0;
            wb_rd_we_q   <= 1'b0;
            wb_result_q  <= 32'h0;
            wb_load_q    <= 1'b0;
            wb_mem_q     <= 1'b0;
            wb_funct3_q  <= 3'b000;
            wb_addr_lo_q <= 2'b00;
            wb_exc_q     <= 1'b0;
            wb_cause_q   <= 5'd0;
            wb_unsup_q   <= 1'b0;
        end else if (ex_go & ex_valid) begin
            wb_pc_q      <= ex_pc_q;
            wb_instr_q   <= ex_instr;
            wb_rd_q      <= ex_rd_addr;
            wb_rd_we_q   <= ex_rd_we & ~ex_exc & ~ex_unsup;
            wb_result_q  <= ex_result;
            wb_load_q    <= ex_load;
            wb_mem_q     <= d_req_valid_o;   // ex_go nghĩa là yêu cầu đã được nhận
            wb_funct3_q  <= ex_funct3;
            wb_addr_lo_q <= ex_alu_res[1:0];
            wb_exc_q     <= ex_exc;
            wb_cause_q   <= ex_cause;
            wb_unsup_q   <= ex_unsup & ~ex_exc;
        end
    end

    assign wb_wait = wb_valid_q & wb_mem_q & ~d_rsp_valid_i;

    // Lệnh hoàn thành ở WB trong chu kỳ này (tb_core lấy vết từ đây).
    wire wb_retire = wb_valid_q & ~wb_wait;

    assign wb_rd_data = wb_load_q ? wb_load_data : wb_result_q;
    // Load bị lỗi bus không ghi rd (thành access fault ở P4).
    assign wb_rf_we   = wb_retire & wb_rd_we_q & ~(wb_mem_q & d_rsp_err_i);

    // Giữ cho P4 (địa chỉ CSR, mepc/mtval/mcause, thực thi SYSTEM) và cho
    // tb_core đọc để in vết và dừng. Logic P3 chưa dùng.
    wire unused_p4 = ^{ex_csr_addr, ex_csr_we, wb_pc_q, wb_instr_q,
                       wb_exc_q, wb_cause_q, wb_unsup_q, wb_retire};

endmodule

`default_nettype wire
