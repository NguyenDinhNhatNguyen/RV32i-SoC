`timescale 1ns/1ps
`default_nettype none
// rv32_decoder - giải mã lệnh RV32I + Zicsr + Zifencei (+ M).
// Thuần tổ hợp. Mọi tổ hợp funct3/funct7 dành riêng đều báo illegal. Khi
// illegal_o=1 mọi ngõ ra có tác dụng phụ bị ép về 0, nên core chỉ cần xét
// illegal_o.
// Việc kiểm tra địa chỉ CSR có tồn tại hay chỉ đọc nằm ở rv32_csr, không ở đây.
`include "rv32_defs.vh"

module rv32_decoder #(
    parameter ENABLE_M = 0
) (
    input  wire [31:0] instr_i,

    // Trường thanh ghi
    output wire [4:0]  rs1_addr_o,
    output wire [4:0]  rs2_addr_o,
    output wire [4:0]  rd_addr_o,
    output wire [2:0]  funct3_o,     // điều kiện nhánh / kích thước+dấu bộ nhớ / phép CSR / phép M
    output wire [11:0] csr_addr_o,

    output reg         illegal_o,
    output reg         rd_we_o,      // ghi rd, đã bằng 0 khi rd = x0
    output reg  [2:0]  imm_type_o,   // RV_IMM_*
    output reg  [3:0]  alu_op_o,     // RV_ALU_*
    output reg  [1:0]  alu_a_sel_o,  // RV_ALU_A_*
    output reg         alu_b_sel_o,  // RV_ALU_B_*
    output reg  [1:0]  wb_sel_o,     // RV_WB_*

    output reg         branch_o,     // nhánh có điều kiện, đích = kết quả ALU
    output reg         jal_o,        // đích = kết quả ALU (pc + imm)
    output reg         jalr_o,       // đích = kết quả ALU (rs1 + imm), core xoá bit 0
    output reg         load_o,
    output reg         store_o,
    output reg         md_o,         // lệnh RV32M (chỉ khi ENABLE_M)

    output reg         csr_o,        // CSRRW/S/C[I]
    output reg         csr_we_o,     // lệnh CSR có ghi CSR thật
    output reg         ecall_o,
    output reg         ebreak_o,
    output reg         mret_o,
    output reg         wfi_o,
    output reg         fence_i_o     // FENCE là NOP nên không có cờ
);

    wire [6:0] opcode = instr_i[6:0];
    wire [2:0] funct3 = instr_i[14:12];
    wire [6:0] funct7 = instr_i[31:25];

    assign rs1_addr_o = instr_i[19:15];
    assign rs2_addr_o = instr_i[24:20];
    assign rd_addr_o  = instr_i[11:7];
    assign funct3_o   = funct3;
    assign csr_addr_o = instr_i[31:20];

    wire rd_nz  = (instr_i[11:7] != 5'd0);
    wire rs1_nz = (instr_i[19:15] != 5'd0);   // cũng là uimm != 0 với CSR*I
    wire m_en   = (ENABLE_M != 0);

    // Giải mã thô trước khi chặn theo illegal
    reg       ill;
    reg       wr_rd;

    always @(*) begin
        // Mặc định: một lệnh ADD vô hại, không bật gì
        ill         = 1'b0;
        wr_rd       = 1'b0;
        imm_type_o  = `RV_IMM_I;
        alu_op_o    = `RV_ALU_ADD;
        alu_a_sel_o = `RV_ALU_A_RS1;
        alu_b_sel_o = `RV_ALU_B_IMM;
        wb_sel_o    = `RV_WB_ALU;
        branch_o    = 1'b0;
        jal_o       = 1'b0;
        jalr_o      = 1'b0;
        load_o      = 1'b0;
        store_o     = 1'b0;
        md_o        = 1'b0;
        csr_o       = 1'b0;
        csr_we_o    = 1'b0;
        ecall_o     = 1'b0;
        ebreak_o    = 1'b0;
        mret_o      = 1'b0;
        wfi_o       = 1'b0;
        fence_i_o   = 1'b0;

        case (opcode)
            `RV_OPC_LUI: begin
                wr_rd       = 1'b1;
                imm_type_o  = `RV_IMM_U;
                alu_a_sel_o = `RV_ALU_A_ZERO;
            end

            `RV_OPC_AUIPC: begin
                wr_rd       = 1'b1;
                imm_type_o  = `RV_IMM_U;
                alu_a_sel_o = `RV_ALU_A_PC;
            end

            `RV_OPC_JAL: begin
                wr_rd       = 1'b1;
                jal_o       = 1'b1;
                imm_type_o  = `RV_IMM_J;
                alu_a_sel_o = `RV_ALU_A_PC;
                wb_sel_o    = `RV_WB_PC4;
            end

            `RV_OPC_JALR: begin
                ill         = (funct3 != 3'b000);
                wr_rd       = 1'b1;
                jalr_o      = 1'b1;
                wb_sel_o    = `RV_WB_PC4;
            end

            `RV_OPC_BRANCH: begin
                ill         = (funct3 == 3'b010) || (funct3 == 3'b011);
                branch_o    = 1'b1;
                imm_type_o  = `RV_IMM_B;
                alu_a_sel_o = `RV_ALU_A_PC;
            end

            `RV_OPC_LOAD: begin
                ill         = !((funct3 == `RV_F3_LB)  || (funct3 == `RV_F3_LH) ||
                                (funct3 == `RV_F3_LW)  || (funct3 == `RV_F3_LBU) ||
                                (funct3 == `RV_F3_LHU));
                wr_rd       = 1'b1;
                load_o      = 1'b1;
                wb_sel_o    = `RV_WB_LOAD;
            end

            `RV_OPC_STORE: begin
                ill         = !((funct3 == `RV_F3_SB) || (funct3 == `RV_F3_SH) ||
                                (funct3 == `RV_F3_SW));
                store_o     = 1'b1;
                imm_type_o  = `RV_IMM_S;
            end

            `RV_OPC_OP_IMM: begin
                wr_rd       = 1'b1;
                // Chỉ lệnh dịch dùng instr[30] làm bit alt. Với lệnh khác
                // đây là bit immediate (ADDI không được thành SUB).
                alu_op_o    = {(funct3 == `RV_F3_SRL_SRA) & instr_i[30], funct3};
                if (funct3 == `RV_F3_SLL)
                    ill = (funct7 != `RV_F7_BASE);
                else if (funct3 == `RV_F3_SRL_SRA)
                    ill = (funct7 != `RV_F7_BASE) && (funct7 != `RV_F7_ALT);
            end

            `RV_OPC_OP: begin
                wr_rd       = 1'b1;
                alu_b_sel_o = `RV_ALU_B_RS2;
                alu_op_o    = {instr_i[30], funct3};
                if (funct7 == `RV_F7_MULDIV) begin
                    ill  = !m_en;
                    md_o = 1'b1;
                end else if (funct7 == `RV_F7_ALT) begin
                    ill  = (funct3 != `RV_F3_ADD_SUB) && (funct3 != `RV_F3_SRL_SRA);
                end else begin
                    ill  = (funct7 != `RV_F7_BASE);
                end
            end

            `RV_OPC_MISC_MEM: begin
                // Bỏ qua trường rs1/rd/imm để tương thích về sau
                // (đặc tả Unprivileged, mục FENCE và FENCE.I).
                if (funct3 == `RV_F3_FENCE_I)
                    fence_i_o = 1'b1;
                else
                    ill = (funct3 != `RV_F3_FENCE);
            end

            `RV_OPC_SYSTEM: begin
                if (funct3 == `RV_F3_PRIV) begin
                    // Lệnh privileged phải khớp nguyên word (rs1 = rd = 0)
                    case (instr_i)
                        `RV_INSTR_ECALL:  ecall_o  = 1'b1;
                        `RV_INSTR_EBREAK: ebreak_o = 1'b1;
                        `RV_INSTR_MRET:   mret_o   = 1'b1;
                        `RV_INSTR_WFI:    wfi_o    = 1'b1;
                        default:          ill      = 1'b1;
                    endcase
                end else if (funct3 == 3'b100) begin
                    ill = 1'b1;
                end else begin
                    wr_rd      = 1'b1;
                    csr_o      = 1'b1;
                    imm_type_o = `RV_IMM_Z;
                    wb_sel_o   = `RV_WB_CSR;
                    // CSRRW[I] luôn ghi, CSRRS/C[I] chỉ ghi khi rs1/uimm != 0
                    csr_we_o   = (funct3[1:0] == `RV_CSR_RW) || rs1_nz;
                end
            end

            default: ill = 1'b1;
        endcase

        // Không hỗ trợ lệnh nén 16 bit
        if (instr_i[1:0] != 2'b11)
            ill = 1'b1;

        illegal_o = ill;
        rd_we_o   = wr_rd & rd_nz & ~ill;
        if (ill) begin
            branch_o  = 1'b0;
            jal_o     = 1'b0;
            jalr_o    = 1'b0;
            load_o    = 1'b0;
            store_o   = 1'b0;
            md_o      = 1'b0;
            csr_o     = 1'b0;
            csr_we_o  = 1'b0;
            ecall_o   = 1'b0;
            ebreak_o  = 1'b0;
            mret_o    = 1'b0;
            wfi_o     = 1'b0;
            fence_i_o = 1'b0;
        end
    end

endmodule

`default_nettype wire
