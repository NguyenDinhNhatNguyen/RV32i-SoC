`timescale 1ns/1ps
`default_nettype none
// tb_rv32_decoder - testbench tự kiểm tra cho rv32_decoder.
// Mô hình tham chiếu: bảng MASK/MATCH của mọi lệnh được hỗ trợ (giá trị lấy
// từ riscv-opcodes) kèm tín hiệu điều khiển kỳ vọng theo tên lệnh. Word nào
// không khớp mục nào trong bảng phải là illegal.
// Kích thích: mọi lệnh với trường tự do ngẫu nhiên (thêm biến thể rd=x0 và
// rs1=x0), mã illegal viết tay, word ngẫu nhiên có opcode hợp lệ, word ngẫu
// nhiên hoàn toàn. Coverage: mọi mục trong bảng phải được chạm tới.
// Tham số ENABLE_M: chạy với 0 (mã lệnh M là illegal) và 1.
// Plusarg: +seed=<n> +n=<số word ngẫu nhiên> +timeout=<ns>
`include "rv32_defs.vh"

module tb_rv32_decoder;

    parameter ENABLE_M = 0;

    reg  [31:0] instr;
    wire [4:0]  rs1_addr, rs2_addr, rd_addr;
    wire [2:0]  funct3;
    wire [11:0] csr_addr;
    wire        illegal, rd_we;
    wire [2:0]  imm_type;
    wire [3:0]  alu_op;
    wire [1:0]  alu_a_sel;
    wire        alu_b_sel;
    wire [1:0]  wb_sel;
    wire        branch, jal, jalr, load, store, md;
    wire        csr, csr_we, ecall, ebreak, mret, wfi, fence_i;

    rv32_decoder #(.ENABLE_M(ENABLE_M)) dut (
        .instr_i(instr),
        .rs1_addr_o(rs1_addr), .rs2_addr_o(rs2_addr), .rd_addr_o(rd_addr),
        .funct3_o(funct3), .csr_addr_o(csr_addr),
        .illegal_o(illegal), .rd_we_o(rd_we), .imm_type_o(imm_type),
        .alu_op_o(alu_op), .alu_a_sel_o(alu_a_sel), .alu_b_sel_o(alu_b_sel),
        .wb_sel_o(wb_sel),
        .branch_o(branch), .jal_o(jal), .jalr_o(jalr), .load_o(load),
        .store_o(store), .md_o(md),
        .csr_o(csr), .csr_we_o(csr_we), .ecall_o(ecall), .ebreak_o(ebreak),
        .mret_o(mret), .wfi_o(wfi), .fence_i_o(fence_i)
    );

    // ------------------------------------------------------------------
    // Bảng lệnh
    // ------------------------------------------------------------------
    localparam C_LUI = 0, C_AUIPC = 1, C_JAL = 2, C_JALR = 3, C_BRANCH = 4,
               C_LOAD = 5, C_STORE = 6, C_OPIMM = 7, C_OP = 8, C_MD = 9,
               C_FENCE = 10, C_FENCEI = 11, C_ECALL = 12, C_EBREAK = 13,
               C_MRET = 14, C_WFI = 15, C_CSR = 16, C_CSRI = 17;
    localparam MAXN = 64;

    reg [8*8-1:0] t_name  [0:MAXN-1];
    reg [31:0]    t_mask  [0:MAXN-1];
    reg [31:0]    t_match [0:MAXN-1];
    integer       t_cls   [0:MAXN-1];
    reg [3:0]     t_alu   [0:MAXN-1];
    integer       t_hits  [0:MAXN-1];
    integer       n_instr = 0;

    task add(input [8*8-1:0] nm, input [31:0] mk, input [31:0] mt,
             input integer cl, input [3:0] al);
        begin
            t_name[n_instr] = nm; t_mask[n_instr] = mk; t_match[n_instr] = mt;
            t_cls[n_instr] = cl; t_alu[n_instr] = al; t_hits[n_instr] = 0;
            n_instr = n_instr + 1;
        end
    endtask

    localparam [31:0] M_OPC = 32'h0000_007F, M_F3 = 32'h0000_707F,
                      M_F7 = 32'hFE00_707F, M_ALL = 32'hFFFF_FFFF;

    task build_table;
        begin
            add("lui",     M_OPC, 32'h0000_0037, C_LUI,    `RV_ALU_ADD);
            add("auipc",   M_OPC, 32'h0000_0017, C_AUIPC,  `RV_ALU_ADD);
            add("jal",     M_OPC, 32'h0000_006F, C_JAL,    `RV_ALU_ADD);
            add("jalr",    M_F3,  32'h0000_0067, C_JALR,   `RV_ALU_ADD);
            add("beq",     M_F3,  32'h0000_0063, C_BRANCH, `RV_ALU_ADD);
            add("bne",     M_F3,  32'h0000_1063, C_BRANCH, `RV_ALU_ADD);
            add("blt",     M_F3,  32'h0000_4063, C_BRANCH, `RV_ALU_ADD);
            add("bge",     M_F3,  32'h0000_5063, C_BRANCH, `RV_ALU_ADD);
            add("bltu",    M_F3,  32'h0000_6063, C_BRANCH, `RV_ALU_ADD);
            add("bgeu",    M_F3,  32'h0000_7063, C_BRANCH, `RV_ALU_ADD);
            add("lb",      M_F3,  32'h0000_0003, C_LOAD,   `RV_ALU_ADD);
            add("lh",      M_F3,  32'h0000_1003, C_LOAD,   `RV_ALU_ADD);
            add("lw",      M_F3,  32'h0000_2003, C_LOAD,   `RV_ALU_ADD);
            add("lbu",     M_F3,  32'h0000_4003, C_LOAD,   `RV_ALU_ADD);
            add("lhu",     M_F3,  32'h0000_5003, C_LOAD,   `RV_ALU_ADD);
            add("sb",      M_F3,  32'h0000_0023, C_STORE,  `RV_ALU_ADD);
            add("sh",      M_F3,  32'h0000_1023, C_STORE,  `RV_ALU_ADD);
            add("sw",      M_F3,  32'h0000_2023, C_STORE,  `RV_ALU_ADD);
            add("addi",    M_F3,  32'h0000_0013, C_OPIMM,  `RV_ALU_ADD);
            add("slti",    M_F3,  32'h0000_2013, C_OPIMM,  `RV_ALU_SLT);
            add("sltiu",   M_F3,  32'h0000_3013, C_OPIMM,  `RV_ALU_SLTU);
            add("xori",    M_F3,  32'h0000_4013, C_OPIMM,  `RV_ALU_XOR);
            add("ori",     M_F3,  32'h0000_6013, C_OPIMM,  `RV_ALU_OR);
            add("andi",    M_F3,  32'h0000_7013, C_OPIMM,  `RV_ALU_AND);
            add("slli",    M_F7,  32'h0000_1013, C_OPIMM,  `RV_ALU_SLL);
            add("srli",    M_F7,  32'h0000_5013, C_OPIMM,  `RV_ALU_SRL);
            add("srai",    M_F7,  32'h4000_5013, C_OPIMM,  `RV_ALU_SRA);
            add("add",     M_F7,  32'h0000_0033, C_OP,     `RV_ALU_ADD);
            add("sub",     M_F7,  32'h4000_0033, C_OP,     `RV_ALU_SUB);
            add("sll",     M_F7,  32'h0000_1033, C_OP,     `RV_ALU_SLL);
            add("slt",     M_F7,  32'h0000_2033, C_OP,     `RV_ALU_SLT);
            add("sltu",    M_F7,  32'h0000_3033, C_OP,     `RV_ALU_SLTU);
            add("xor",     M_F7,  32'h0000_4033, C_OP,     `RV_ALU_XOR);
            add("srl",     M_F7,  32'h0000_5033, C_OP,     `RV_ALU_SRL);
            add("sra",     M_F7,  32'h4000_5033, C_OP,     `RV_ALU_SRA);
            add("or",      M_F7,  32'h0000_6033, C_OP,     `RV_ALU_OR);
            add("and",     M_F7,  32'h0000_7033, C_OP,     `RV_ALU_AND);
            add("fence",   M_F3,  32'h0000_000F, C_FENCE,  `RV_ALU_ADD);
            add("fence.i", M_F3,  32'h0000_100F, C_FENCEI, `RV_ALU_ADD);
            add("ecall",   M_ALL, 32'h0000_0073, C_ECALL,  `RV_ALU_ADD);
            add("ebreak",  M_ALL, 32'h0010_0073, C_EBREAK, `RV_ALU_ADD);
            add("mret",    M_ALL, 32'h3020_0073, C_MRET,   `RV_ALU_ADD);
            add("wfi",     M_ALL, 32'h1050_0073, C_WFI,    `RV_ALU_ADD);
            add("csrrw",   M_F3,  32'h0000_1073, C_CSR,    `RV_ALU_ADD);
            add("csrrs",   M_F3,  32'h0000_2073, C_CSR,    `RV_ALU_ADD);
            add("csrrc",   M_F3,  32'h0000_3073, C_CSR,    `RV_ALU_ADD);
            add("csrrwi",  M_F3,  32'h0000_5073, C_CSRI,   `RV_ALU_ADD);
            add("csrrsi",  M_F3,  32'h0000_6073, C_CSRI,   `RV_ALU_ADD);
            add("csrrci",  M_F3,  32'h0000_7073, C_CSRI,   `RV_ALU_ADD);
            add("mul",     M_F7,  32'h0200_0033, C_MD,     `RV_ALU_ADD);
            add("mulh",    M_F7,  32'h0200_1033, C_MD,     `RV_ALU_ADD);
            add("mulhsu",  M_F7,  32'h0200_2033, C_MD,     `RV_ALU_ADD);
            add("mulhu",   M_F7,  32'h0200_3033, C_MD,     `RV_ALU_ADD);
            add("div",     M_F7,  32'h0200_4033, C_MD,     `RV_ALU_ADD);
            add("divu",    M_F7,  32'h0200_5033, C_MD,     `RV_ALU_ADD);
            add("rem",     M_F7,  32'h0200_6033, C_MD,     `RV_ALU_ADD);
            add("remu",    M_F7,  32'h0200_7033, C_MD,     `RV_ALU_ADD);
        end
    endtask

    // ------------------------------------------------------------------
    // Kiểm tra
    // ------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer n_legal = 0;
    integer n_illegal = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 200000;
    integer timeout_ns = 50000000;

    task cmp(input [31:0] got, input [31:0] exp, input [8*10-1:0] sig);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("FAIL: instr=%h %0s got=%h exp=%h", instr, sig, got, exp);
            end
        end
    endtask

    task check(input [31:0] w);
        integer k, id, cl;
        reg e_ill, e_rdwe, e_br, e_jal, e_jalr, e_ld, e_st, e_md;
        reg e_csr, e_csrwe, e_ecall, e_ebreak, e_mret, e_wfi, e_fencei;
        reg c_imm, c_alu;              // cờ có quan tâm
        reg [2:0] e_imm;
        reg [3:0] e_alu;
        reg [1:0] e_a, e_wb;
        reg       e_b;
        reg       rd_nz, rs1_nz;
        begin
            instr = w;
            #1;
            id = -1;
            for (k = 0; k < n_instr; k = k + 1)
                if ((w & t_mask[k]) == t_match[k]) begin
                    if (id != -1) begin
                        errors = errors + 1;
                        $display("FAIL: table overlap %h", w);
                    end
                    id = k;
                end
            if (id >= 0) t_hits[id] = t_hits[id] + 1;
            cl = (id >= 0) ? t_cls[id] : -1;
            if (cl == C_MD && ENABLE_M == 0) cl = -1;

            rd_nz  = (w[11:7] != 5'd0);
            rs1_nz = (w[19:15] != 5'd0);
            e_ill = (cl < 0);
            {e_rdwe, e_br, e_jal, e_jalr, e_ld, e_st, e_md} = 7'b0;
            {e_csr, e_csrwe, e_ecall, e_ebreak, e_mret, e_wfi, e_fencei} = 7'b0;
            c_imm = 1'b0; c_alu = 1'b0;
            e_imm = `RV_IMM_I; e_alu = `RV_ALU_ADD;
            e_a = `RV_ALU_A_RS1; e_b = `RV_ALU_B_IMM; e_wb = `RV_WB_ALU;

            case (cl)
                C_LUI:    begin e_rdwe = rd_nz; c_imm = 1; e_imm = `RV_IMM_U; c_alu = 1;
                                e_a = `RV_ALU_A_ZERO; end
                C_AUIPC:  begin e_rdwe = rd_nz; c_imm = 1; e_imm = `RV_IMM_U; c_alu = 1;
                                e_a = `RV_ALU_A_PC; end
                C_JAL:    begin e_rdwe = rd_nz; e_jal = 1; c_imm = 1; e_imm = `RV_IMM_J; c_alu = 1;
                                e_a = `RV_ALU_A_PC; e_wb = `RV_WB_PC4; end
                C_JALR:   begin e_rdwe = rd_nz; e_jalr = 1; c_imm = 1; c_alu = 1;
                                e_wb = `RV_WB_PC4; end
                C_BRANCH: begin e_br = 1; c_imm = 1; e_imm = `RV_IMM_B; c_alu = 1;
                                e_a = `RV_ALU_A_PC; end
                C_LOAD:   begin e_rdwe = rd_nz; e_ld = 1; c_imm = 1; c_alu = 1;
                                e_wb = `RV_WB_LOAD; end
                C_STORE:  begin e_st = 1; c_imm = 1; e_imm = `RV_IMM_S; c_alu = 1; end
                C_OPIMM:  begin e_rdwe = rd_nz; c_imm = 1; c_alu = 1; e_alu = t_alu[id]; end
                C_OP:     begin e_rdwe = rd_nz; c_alu = 1; e_alu = t_alu[id]; e_b = `RV_ALU_B_RS2; end
                C_MD:     begin e_rdwe = rd_nz; e_md = 1; end
                C_FENCE:  ;
                C_FENCEI: e_fencei = 1;
                C_ECALL:  e_ecall = 1;
                C_EBREAK: e_ebreak = 1;
                C_MRET:   e_mret = 1;
                C_WFI:    e_wfi = 1;
                C_CSR:    begin e_rdwe = rd_nz; e_csr = 1; e_wb = `RV_WB_CSR;
                                e_csrwe = (w[13:12] == 2'b01) || rs1_nz; end
                C_CSRI:   begin e_rdwe = rd_nz; e_csr = 1; e_wb = `RV_WB_CSR;
                                c_imm = 1; e_imm = `RV_IMM_Z;
                                e_csrwe = (w[13:12] == 2'b01) || rs1_nz; end
                default:  ;
            endcase

            if (e_ill) n_illegal = n_illegal + 1; else n_legal = n_legal + 1;

            cmp(illegal,  e_ill,    "illegal");
            cmp(rd_we,    e_rdwe,   "rd_we");
            cmp(branch,   e_br,     "branch");
            cmp(jal,      e_jal,    "jal");
            cmp(jalr,     e_jalr,   "jalr");
            cmp(load,     e_ld,     "load");
            cmp(store,    e_st,     "store");
            cmp(md,       e_md,     "md");
            cmp(csr,      e_csr,    "csr");
            cmp(csr_we,   e_csrwe,  "csr_we");
            cmp(ecall,    e_ecall,  "ecall");
            cmp(ebreak,   e_ebreak, "ebreak");
            cmp(mret,     e_mret,   "mret");
            cmp(wfi,      e_wfi,    "wfi");
            cmp(fence_i,  e_fencei, "fence_i");
            cmp(rs1_addr, w[19:15], "rs1_addr");
            cmp(rs2_addr, w[24:20], "rs2_addr");
            cmp(rd_addr,  w[11:7],  "rd_addr");
            cmp(funct3,   w[14:12], "funct3");
            cmp(csr_addr, w[31:20], "csr_addr");
            if (!e_ill) begin
                if (c_imm) cmp(imm_type, e_imm, "imm_type");
                if (c_alu) begin
                    cmp(alu_op,    e_alu, "alu_op");
                    cmp(alu_a_sel, e_a,   "alu_a_sel");
                    cmp(alu_b_sel, e_b,   "alu_b_sel");
                end
                if (e_rdwe) cmp(wb_sel, e_wb, "wb_sel");
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Kích thích
    // ------------------------------------------------------------------
    reg [6:0] opcodes [0:10];
    integer i, k;
    reg [31:0] r, w;

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        build_table;
        opcodes[0] = 7'h37; opcodes[1] = 7'h17; opcodes[2] = 7'h6F; opcodes[3] = 7'h67;
        opcodes[4] = 7'h63; opcodes[5] = 7'h03; opcodes[6] = 7'h23; opcodes[7] = 7'h13;
        opcodes[8] = 7'h33; opcodes[9] = 7'h0F; opcodes[10] = 7'h73;

        // 1. Mọi lệnh, trường tự do ngẫu nhiên, thêm rd = x0 và rs1 = x0
        for (k = 0; k < n_instr; k = k + 1)
            for (i = 0; i < 300; i = i + 1) begin
                r = $random(seed);
                w = t_match[k] | (r & ~t_mask[k]);
                if (i % 3 == 1 && t_mask[k] != M_ALL) w[11:7]  = 5'd0;
                if (i % 3 == 2 && t_mask[k] != M_ALL) w[19:15] = 5'd0;
                check(w);
            end

        // 2. Mã illegal và mã gần đúng viết tay
        check(32'h0000_0000);              // toàn 0
        check(32'hFFFF_FFFF);              // toàn 1
        check(32'h0000_0001);              // lệnh nén
        check(32'h0000_4501);              // c.li
        check(32'h0200_1013);              // slli có shamt[5] = 1 (chỉ RV64)
        check(32'h0200_5013);              // srli có shamt[5] = 1
        check(32'h6000_5013);              // srai có funct7 sai
        check(32'h4000_1013);              // slli có funct7 = 0100000
        check(32'h4000_1033);              // sll có funct7 = 0100000
        check(32'h4000_7033);              // and có funct7 = 0100000
        check(32'h8000_0033);              // add có funct7 = 1000000
        check(32'h0000_2063);              // branch funct3 = 010
        check(32'h0000_3063);              // branch funct3 = 011
        check(32'h0000_3003);              // ld (RV64)
        check(32'h0000_6003);              // lwu (RV64)
        check(32'h0000_7003);
        check(32'h0000_3023);              // sd (RV64)
        check(32'h0000_1067);              // jalr có funct3 = 001
        check(32'h0000_200F);              // misc-mem funct3 = 010
        check(32'h0000_00F3);              // ecall có rd != 0
        check(32'h0000_8073);              // ecall có rs1 != 0
        check(32'h0020_0073);              // uret
        check(32'h1020_0073);              // sret
        check(32'h7B20_0073);              // dret
        check(32'h1200_0073);              // sfence.vma
        check(32'h3020_00F3);              // mret có rd != 0
        check(32'h0000_4073);              // SYSTEM funct3 = 100
        check(32'h0000_001B);              // OP-IMM-32 (RV64)
        check(32'h0000_003B);              // OP-32 (RV64)
        check(32'h0000_0007);              // FLW
        check(32'h0000_002F);              // AMO
        check(32'h0FF0_000F);              // fence iorw, iorw  (hợp lệ)
        check(32'h8330_000F);              // fence.tso         (hợp lệ)
        check(32'h0000_100F);              // fence.i           (hợp lệ)
        check(32'h0000_0013);              // nop               (hợp lệ)
        check(32'h3000_2073);              // csrr x0, mstatus  (hợp lệ, rd = x0)

        // 3. Word ngẫu nhiên có opcode chính hợp lệ
        for (i = 0; i < n_rand; i = i + 1) begin
            r = $random(seed);
            w = {r[31:7], opcodes[{$random(seed)} % 11]};
            // Thiên funct7 về các giá trị đã định nghĩa để có lệnh R-type hợp lệ
            case (r[2:0])
                3'd0: w[31:25] = 7'b0000000;
                3'd1: w[31:25] = 7'b0100000;
                3'd2: w[31:25] = 7'b0000001;
                default: ;
            endcase
            check(w);
        end

        // 4. Word ngẫu nhiên hoàn toàn
        for (i = 0; i < n_rand; i = i + 1)
            check($random(seed));

        // Coverage: mọi mục trong bảng đều đã gặp
        for (k = 0; k < n_instr; k = k + 1)
            if (t_hits[k] == 0) begin
                errors = errors + 1;
                $display("FAIL: no coverage for %0s", t_name[k]);
            end

        if (errors == 0)
            $display("PASS: tb_rv32_decoder ENABLE_M=%0d (%0d checks, %0d legal / %0d illegal words, seed %0d)",
                     ENABLE_M, checks, n_legal, n_illegal, seed0);
        else
            $display("FAIL: tb_rv32_decoder ENABLE_M=%0d (%0d errors / %0d checks, seed %0d)",
                     ENABLE_M, errors, checks, seed0);
        $finish;
    end

    initial begin
        #1;
        #(timeout_ns);
        $display("FAIL: tb_rv32_decoder timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
