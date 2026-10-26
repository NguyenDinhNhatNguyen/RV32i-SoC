`timescale 1ns/1ps
`default_nettype none
// rv32_core - 3-stage RV32I pipeline IF / EX / WB, machine mode only.
//
//   IF : if_pc_q drives the IMEM address straight from a flop.
//   EX : the instruction comes straight from the synchronous IMEM output (or from
//        ex_instr_hold_q while EX is stalled). Decode, register file read, forward
//        WB->EX, ALU, branch compare, and bus requests for load/store.
//   WB : align load data, write the register file, execute CSRs, and handle
//        traps, MRET, FENCE.I and WFI (PC redirect from WB).
//
// Stalls: WB waiting for d_rsp_valid_i, or an EX bus request not yet accepted,
// holds IF and EX (and also WB in the first case).
//
// Exceptions are detected in EX (or as a bus error in WB). The instruction carries
// the flag to WB and traps there. Interrupts are attached to the instruction in EX
// (section 4.8). RV32M instructions run in rv32_muldiv inside EX (ENABLE_M=1), and
// EX stalls until the result is ready.
`include "rv32_defs.vh"

module rv32_core #(
    parameter        ENABLE_M         = 0,
    parameter        ENABLE_WFI_SLEEP = 1,
    parameter [31:0] RESET_PC         = `RV_RESET_PC_DEFAULT
) (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction port: the address is accepted when if_req_o && if_gnt_i,
    // instruction and error arrive one cycle later.
    output wire        if_req_o,
    output wire [31:0] if_addr_o,
    input  wire        if_gnt_i,
    input  wire [31:0] if_rdata_i,
    input  wire        if_err_i,

    // Data bus request channel (docs/spec/core.md section 5.1)
    output wire        d_req_valid_o,
    input  wire        d_req_ready_i,
    output wire [31:0] d_addr_o,
    output wire        d_we_o,
    output wire [3:0]  d_be_o,
    output wire [31:0] d_wdata_o,

    // Data bus response channel
    input  wire        d_rsp_valid_i,
    input  wire [31:0] d_rsp_rdata_i,
    input  wire        d_rsp_err_i,

    // Level interrupts, timer, sleep state
    input  wire        irq_software_i,
    input  wire        irq_timer_i,
    input  wire        irq_external_i,
    input  wire [63:0] mtime_i,
    output wire        core_sleep_o     // Sleeping in WFI, IMEM is not read
);

    // =======================================================================
    // Pipeline control (declared first because every stage uses it)
    // =======================================================================
    wire wb_wait;      // WB holds a load/store waiting for its response
    wire ex_wait;      // EX bus request not accepted yet, or the M-unit is busy
    wire pipe_stall = wb_wait | ex_wait;
    wire ex_go      = ~pipe_stall;   // EX passes its instruction (or a bubble) to WB

    // Redirect from WB (trap, MRET, FENCE.I, WFI): kill the instruction in EX, including
    // its bus request in the same cycle (section 4.4).
    wire        wb_redirect;
    wire [31:0] wb_target;
    reg         sleep_q;         // Sleeping in WFI

    // =======================================================================
    // IF
    // =======================================================================
    reg  [31:0] if_pc_q;
    wire        ex_redirect;        // A taken branch or jump leaves EX this cycle
    wire [31:0] ex_target;

    // Always fetch unless sleeping. sleep_q is a flop, so the IMEM enable pin does not
    // depend combinationally on the bus or on interrupts.
    assign if_req_o     = ~sleep_q;
    assign if_addr_o    = if_pc_q;
    assign core_sleep_o = sleep_q;

    wire if_fire = if_req_o & if_gnt_i;

    // Redirects go into the flop and never combinationally to if_addr_o.
    // Without a grant, the same address is issued again next cycle.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            if_pc_q <= RESET_PC;
        else if (wb_redirect)
            if_pc_q <= wb_target;
        else if (ex_redirect)
            if_pc_q <= ex_target;
        else if (ex_go & if_fire)
            if_pc_q <= if_pc_q + 32'd4;
    end

    // =======================================================================
    // EX
    // =======================================================================
    reg         ex_fetch_q;       // The IMEM output holds a real instruction
    reg  [31:0] ex_pc_q;
    reg         ex_hold_q;        // The instruction sits in the hold register
    reg  [31:0] ex_instr_hold_q;
    reg         ex_ferr_hold_q;

    wire        ex_valid = ex_fetch_q | ex_hold_q;
    wire [31:0] ex_instr = ex_hold_q ? ex_instr_hold_q : if_rdata_i;
    wire        ex_ferr  = ex_hold_q ? ex_ferr_hold_q  : if_err_i;

    // The instruction fetched while a jump leaves EX is the wrong-path PC+4 and is
    // killed here (1-cycle penalty). An instruction fetched during a stall is also
    // killed because it is fetched again from the unchanged if_pc_q. A redirect from
    // WB also kills the instruction being fetched.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_fetch_q <= 1'b0;
        else
            ex_fetch_q <= ex_go & if_fire & ~ex_redirect & ~wb_redirect;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_pc_q <= 32'h0;
        else if (ex_go & if_fire)
            ex_pc_q <= if_pc_q;
    end

    // The IMEM output is valid for one cycle only (if_pc_q already points to the next
    // instruction), so a stalled instruction is latched on the first stall cycle and
    // read back from here until the stall ends.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_hold_q <= 1'b0;
        else
            ex_hold_q <= pipe_stall & ex_valid & ~wb_redirect;
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

    // ---- Decode --------------------------------------------------------------
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
    wire        ex_csr_illegal;   // CSR address does not exist, or write to a read-only CSR

    rv32_imm_gen u_imm_gen (
        .instr_i    (ex_instr[31:7]),
        .imm_type_i (ex_imm_type),
        .imm_o      (ex_imm)
    );

    // ---- Register file and forward WB->EX -------------------------------------
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

    // wb_rd_we_q is already 0 when rd = x0 and when the instruction carries a flag.
    // The WB value is still forwarded while a load waits for its response. EX is
    // stalled then, so nothing uses the stale value.
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

    // ---- Branch / jump ---------------------------------------------------------
    // A dedicated comparator runs in parallel with the target adder (D-007).
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

    // ALU computes pc+imm (branch/JAL, always even) or rs1+imm (JALR, bit 0
    // cleared as the spec requires).
    wire ex_jump = ex_jal | ex_jalr | (ex_branch & ex_br_cond);
    assign ex_target = {ex_alu_res[31:1], 1'b0};

    // ---- Load/store byte lanes -------------------------------------------------
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

    // ---- Exceptions detected in EX (priority as in the Privileged spec) -------
    reg       ex_exc;
    reg [4:0] ex_cause;

    always @(*) begin
        ex_exc   = 1'b1;
        ex_cause = `RV_EXC_ILLEGAL;
        if (ex_ferr)
            ex_cause = `RV_EXC_INSTR_ACCESS;
        else if (ex_illegal | (ex_csr & ex_csr_illegal))
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

    // ---- Interrupts (section 4.8) ----------------------------------------------
    // A valid instruction in EX is marked "interrupted" when MIE = 1 and an enabled
    // interrupt is pending. It does not execute or issue a bus request, and traps in WB
    // with mepc = its PC. Interrupts are not taken when:
    //   - WB is writing mstatus or mie, so enabling or disabling takes effect from the
    //     next instruction,
    //   - the instruction's bus request appeared last cycle and was not accepted yet
    //     (bus rule 1 requires the request to stay unchanged).
    // When WB redirects, the instruction in EX is killed, so nothing else is needed.
    wire       csr_irq_take;
    wire [4:0] csr_irq_cause;
    wire       wb_csr_fwd;
    reg        ex_req_wait_q;   // The EX bus request was in a wait state last cycle

    wire ex_irq = ex_valid & csr_irq_take & ~ex_req_wait_q;
    wire ex_trap = ex_exc | ex_irq;

    // ---- Data bus request ------------------------------------------------------
    // Only one request is outstanding. A new request is issued in the same cycle the
    // previous response returns (wb_wait = 0 then). It does not depend on
    // d_req_ready_i (bus rule 5).
    assign d_req_valid_o = ex_valid & (ex_load | ex_store) & ~ex_trap & ~wb_wait & ~wb_redirect;
    assign d_addr_o      = ex_alu_res;
    assign d_we_o        = ex_store;
    assign d_be_o        = ex_be;
    assign d_wdata_o     = ex_wdata;

    // ---- RV32M --------------------------------------------------------------------
    // The M-unit starts only when WB is not waiting for a response, because a
    // forwarded operand from a load in WB is not ready yet. If the instruction is
    // killed or traps, req = 0 and the M-unit returns to idle.
    wire        md_req = ex_valid & ex_md & ~ex_trap & ~wb_redirect;
    wire        md_done;
    wire [31:0] md_result;

    generate
        if (ENABLE_M != 0) begin : g_md
            rv32_muldiv u_muldiv (
                .clk      (clk),
                .rst_n    (rst_n),
                .req_i    (md_req),
                .hold_i   (wb_wait),
                .go_i     (ex_go),
                .op_i     (ex_funct3),
                .a_i      (ex_rs1),
                .b_i      (ex_rs2),
                .done_o   (md_done),
                .result_o (md_result)
            );
        end else begin : g_no_md
            // The decoder flags M instructions as illegal, so md_req is always 0
            assign md_done   = 1'b0;
            assign md_result = 32'h0;
        end
    endgenerate

    // A bus request in a wait state is the only thing that blocks interrupts (ex_req_wait_q).
    // A running M instruction can still be interrupted. It is dropped and rerun after MRET.
    wire ex_bus_wait = d_req_valid_o & ~d_req_ready_i;

    assign ex_wait     = ex_bus_wait | (md_req & ~md_done);
    assign ex_redirect = ex_go & ex_valid & ex_jump & ~ex_trap & ~wb_redirect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ex_req_wait_q <= 1'b0;
        else
            ex_req_wait_q <= ex_bus_wait;
    end

    // Value carried to WB (wb_result_q):
    //   - JAL/JALR: the return address, or the jump target when the instruction
    //     raises an exception (used as mtval for instruction misaligned),
    //   - CSR: the write operand (rs1 or uimm),
    //   - RV32M: the M-unit result,
    //   - otherwise: the ALU result (also the load/store address for mtval).
    wire [31:0] ex_csr_wdata = ex_funct3[2] ? ex_imm : ex_rs1;
    wire [31:0] ex_result    = ex_csr ? ex_csr_wdata :
                               ex_md  ? md_result :
                               (ex_wb_sel == `RV_WB_PC4) ? (ex_exc ? ex_target : ex_pc_q + 32'd4) :
                               ex_alu_res;

    // =======================================================================
    // WB
    // =======================================================================
    reg  [31:0] wb_pc_q;
    reg  [31:0] wb_instr_q;
    reg  [31:0] wb_result_q;      // ALU result / return address / load-store address
    reg         wb_load_q;
    reg         wb_mem_q;         // Request issued, waiting for the response
    reg         wb_exc_q;         // Exception from EX or interrupted
    reg         wb_int_q;         // Interrupted (mcause bit 31)
    reg  [4:0]  wb_cause_q;
    reg         wb_csr_q;
    reg         wb_csr_we_q;
    reg         wb_mret_q;
    reg         wb_fence_i_q;
    reg         wb_wfi_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_valid_q <= 1'b0;
        else if (ex_go)
            wb_valid_q <= ex_valid & ~wb_redirect;
        else if (!wb_wait)
            wb_valid_q <= 1'b0;   // WB retires while EX waits for d_req_ready_i
    end

    // Load only when a real instruction arrives (acts as the clock gating enable, and
    // keeps X from the idle IMEM output out of these flops).
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
            wb_int_q     <= 1'b0;
            wb_cause_q   <= 5'd0;
            wb_csr_q     <= 1'b0;
            wb_csr_we_q  <= 1'b0;
            wb_mret_q    <= 1'b0;
            wb_fence_i_q <= 1'b0;
            wb_wfi_q     <= 1'b0;
        end else if (ex_go & ex_valid) begin
            wb_pc_q      <= ex_pc_q;
            wb_instr_q   <= ex_instr;
            wb_rd_q      <= ex_rd_addr;
            wb_rd_we_q   <= ex_rd_we & ~ex_trap;
            wb_result_q  <= ex_result;
            wb_load_q    <= ex_load;
            wb_mem_q     <= d_req_valid_o;   // ex_go means the request was accepted
            wb_funct3_q  <= ex_funct3;
            wb_addr_lo_q <= ex_alu_res[1:0];
            wb_exc_q     <= ex_trap;
            wb_int_q     <= ex_irq;
            wb_cause_q   <= ex_irq ? csr_irq_cause : ex_cause;
            wb_csr_q     <= ex_csr & ~ex_trap;
            wb_csr_we_q  <= ex_csr_we;
            wb_mret_q    <= ex_mret & ~ex_trap;
            wb_fence_i_q <= ex_fence_i & ~ex_trap;
            wb_wfi_q     <= ex_wfi & ~ex_trap;
        end
    end

    assign wb_wait = wb_valid_q & wb_mem_q & ~d_rsp_valid_i;

    // The instruction leaves WB this cycle, retiring or trapping (tb_core traces
    // from here).
    wire wb_retire = wb_valid_q & ~wb_wait;

    // ---- Trap ---------------------------------------------------------------------
    // A load/store bus error becomes an access fault in WB.
    wire wb_bus_err = wb_mem_q & d_rsp_err_i;
    wire wb_trap    = wb_retire & (wb_exc_q | wb_bus_err);

    reg  [4:0]  wb_trap_cause;
    reg  [31:0] wb_trap_tval;

    always @(*) begin
        if (wb_exc_q)
            wb_trap_cause = wb_cause_q;
        else
            wb_trap_cause = wb_load_q ? `RV_EXC_LOAD_ACCESS : `RV_EXC_STORE_ACCESS;
    end

    // mtval: illegal = instruction bits, instruction access fault and breakpoint = PC,
    // load/store misaligned and access fault = address (already in wb_result_q),
    // otherwise 0.
    always @(*) begin
        wb_trap_tval = 32'h0;
        if (!wb_int_q) begin
            case (wb_trap_cause)
                `RV_EXC_ILLEGAL:     wb_trap_tval = wb_instr_q;
                `RV_EXC_INSTR_ACCESS, `RV_EXC_BREAKPOINT:
                                     wb_trap_tval = wb_pc_q;
                `RV_EXC_INSTR_MISALIGNED, `RV_EXC_LOAD_MISALIGNED, `RV_EXC_LOAD_ACCESS,
                `RV_EXC_STORE_MISALIGNED, `RV_EXC_STORE_ACCESS:
                                     wb_trap_tval = wb_result_q;
                default:             wb_trap_tval = 32'h0;
            endcase
        end
    end

    // ---- Serializing instructions in WB ---------------------------------------
    wire wb_ok      = wb_retire & ~wb_trap;
    wire wb_mret    = wb_ok & wb_mret_q;
    wire wb_fence_i = wb_ok & wb_fence_i_q;
    // ENABLE_WFI_SLEEP = 0: WFI is a NOP
    wire wb_wfi     = wb_ok & wb_wfi_q & (ENABLE_WFI_SLEEP != 0);
    wire wb_csr_wr  = wb_ok & wb_csr_q & wb_csr_we_q;

    wire [31:0] csr_rdata, csr_mtvec, csr_mepc;
    wire        csr_irq_pending;
    wire [11:0] wb_csr_addr = wb_instr_q[31:20];

    assign wb_redirect = wb_trap | wb_mret | wb_fence_i | wb_wfi;
    assign wb_target   = wb_trap ? csr_mtvec :
                         wb_mret ? csr_mepc  : (wb_pc_q + 32'd4);

    // WB holds a CSR write: the CSR file forwards the new mstatus.MIE and mie to the interrupt
    // check of EX (D-038), so an enable or a disable applies from the very next instruction.
    assign wb_csr_fwd = wb_valid_q & wb_csr_q & wb_csr_we_q;

    rv32_csr #(
        .ENABLE_M (ENABLE_M)
    ) u_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .chk_addr_i     (ex_csr_addr),
        .chk_we_i       (ex_csr_we),
        .chk_illegal_o  (ex_csr_illegal),
        .addr_i         (wb_csr_addr),
        .op_i           (wb_funct3_q[1:0]),
        .wdata_i        (wb_result_q),
        .wr_en_i        (wb_csr_wr),
        .fwd_i          (wb_csr_fwd),
        .rdata_o        (csr_rdata),
        .trap_i         (wb_trap),
        .trap_pc_i      (wb_pc_q[31:2]),
        .trap_int_i     (wb_int_q),
        .trap_cause_i   (wb_trap_cause),
        .trap_tval_i    (wb_trap_tval),
        .mret_i         (wb_mret),
        .instret_i      (wb_ok),
        .mtvec_o        (csr_mtvec),
        .mepc_o         (csr_mepc),
        .irq_software_i (irq_software_i),
        .irq_timer_i    (irq_timer_i),
        .irq_external_i (irq_external_i),
        .mtime_i        (mtime_i),
        .irq_pending_o  (csr_irq_pending),
        .irq_take_o     (csr_irq_take),
        .irq_cause_o    (csr_irq_cause)
    );

    // ---- WFI sleep (section 4.11) ----------------------------------------------
    // WFI in WB: redirect to PC+4, then sleep. Wake up when (mip & mie) != 0,
    // regardless of mstatus.MIE. If that already holds when WFI is in WB, the core does not
    // sleep at all (D-038). While asleep if_req_o = 0, and EX and WB are empty,
    // so every pipeline flop holds its value.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sleep_q <= 1'b0;
        else if (wb_wfi & ~csr_irq_pending)
            sleep_q <= 1'b1;
        else if (csr_irq_pending)
            sleep_q <= 1'b0;
    end

    // ---- Ghi rd ------------------------------------------------------------------------
    // The old CSR value is forwarded to EX like an ALU result.
    wire [31:0] wb_nonload_data = wb_csr_q ? csr_rdata : wb_result_q;
    assign wb_rd_data = wb_load_q ? wb_load_data : wb_nonload_data;
    // An instruction that traps (including a load with a bus error) does not write rd.
    assign wb_rf_we   = wb_retire & wb_rd_we_q & ~wb_trap;

endmodule

`default_nettype wire
