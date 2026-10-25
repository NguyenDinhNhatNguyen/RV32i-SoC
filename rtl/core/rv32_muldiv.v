`timescale 1ns/1ps
`default_nettype none
// rv32_muldiv - RV32M unit in the EX stage (docs/spec/core.md section 4.9).
//
//   MUL, MULH, MULHSU, MULHU: 2 cycles (EX stalls 1 cycle). The first cycle multiplies
//     the 33-bit operand (sign-extended as the op needs) by the two 17-bit halves of
//     the other operand and latches both partial products. The next cycle adds them
//     into the 64-bit product. Each cycle uses only half a multiplier, so no
//     multicycle path is needed in the SDC.
//   DIV, DIVU, REM, REMU: restoring division (trial subtract, keep the old remainder
//     when negative), 1 bit per cycle on absolute values, sign fixed in the last cycle.
//     The instruction stays in EX for 34 cycles (load, 32 steps, result), so EX stalls 33.
//   Divide by 0 and the -2^31 / -1 overflow give the spec results without a special
//   path: the unsigned quotient is all ones and keeps its sign when the divisor is 0,
//   and |-2^31| / 1 = 2^31 negated is still -2^31.
//
// Interface to EX: req_i = 1 for as long as the M instruction sits in EX (0 when the
// instruction is killed or traps, and the unit returns to idle). The op starts in the
// cycle with req_i = 1 and hold_i = 0 (operands are valid). done_o = 1 when result_o
// is valid, and the unit is idle again after the cycle with done_o && go_i.
`include "rv32_defs.vh"

module rv32_muldiv (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_i,
    input  wire        hold_i,     // Not allowed to start yet (forwarded operand not ready)
    input  wire        go_i,       // EX passes the instruction to WB this cycle
    input  wire [2:0]  op_i,       // funct3, RV_F3_MUL ... RV_F3_REMU
    input  wire [31:0] a_i,        // rs1
    input  wire [31:0] b_i,        // rs2
    output wire        done_o,
    output wire [31:0] result_o
);

    wire is_div   = op_i[2];
    // MULH, MULHSU: rs1 is signed. MULH: rs2 is signed. DIV, REM: both are signed.
    wire a_signed = is_div ? ~op_i[0] : (op_i[1:0] == 2'b01) | (op_i[1:0] == 2'b10);
    wire b_signed = is_div ? ~op_i[0] : (op_i[1:0] == 2'b01);

    // ---- State --------------------------------------------------------------------
    reg        busy_q;
    reg        div_q;          // The running op is a divide
    reg        hi_q;           // MUL: take the high half. DIV: take the remainder
    reg [5:0]  cnt_q;          // Division steps left

    wire start = req_i & ~busy_q & ~hold_i;
    assign done_o = busy_q & (~div_q | (cnt_q == 6'd0));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            div_q  <= 1'b0;
            hi_q   <= 1'b0;
            cnt_q  <= 6'd0;
        end else if (!req_i) begin
            busy_q <= 1'b0;                   // Instruction killed or trapped
        end else if (start) begin
            busy_q <= 1'b1;
            div_q  <= is_div;
            // MULH/MULHSU/MULHU take the high half, REM/REMU take the remainder (op_i[1] = 1)
            hi_q   <= is_div ? op_i[1] : (op_i[1:0] != 2'b00);
            cnt_q  <= 6'd32;
        end else if (done_o & go_i) begin
            busy_q <= 1'b0;
        end else if (busy_q & div_q & (cnt_q != 6'd0)) begin
            cnt_q  <= cnt_q - 6'd1;
        end
    end

    // ---- Multiply: two 33 x 17 bit partial products ----------------------------------
    // A and B are 33-bit signed operands. Product = A * B[15:0] + (A * B[32:16]) << 16.
    // Only the low 64 bits of the product are needed, so the high partial keeps 48 bits.
    wire [32:0] ma = {a_signed & a_i[31], a_i};
    wire [32:0] mb = {b_signed & b_i[31], b_i};

    wire [48:0] p_lo = $signed({{16{ma[32]}}, ma}) * $signed({33'h0, mb[15:0]});
    wire [47:0] p_hi = $signed({{15{ma[32]}}, ma}) * $signed({{31{mb[32]}}, mb[32:16]});

    reg  [48:0] p_lo_q;
    reg  [47:0] p_hi_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_lo_q <= 49'h0;
            p_hi_q <= 48'h0;
        end else if (start & ~is_div) begin
            p_lo_q <= p_lo;
            p_hi_q <= p_hi;
        end
    end

    wire [63:0] prod = {{15{p_lo_q[48]}}, p_lo_q} + {p_hi_q, 16'h0};

    // ---- Chia ---------------------------------------------------------------------------
    reg  [31:0] rem_q;         // Partial remainder
    reg  [31:0] quo_q;         // Dividend shifts out while the quotient shifts in
    reg  [31:0] dvs_q;         // |divisor|
    reg         neg_q_q;       // Negate the quotient
    reg         neg_r_q;       // Negate the remainder

    wire [31:0] a_abs = (a_signed & a_i[31]) ? (32'h0 - a_i) : a_i;
    wire [31:0] b_abs = (b_signed & b_i[31]) ? (32'h0 - b_i) : b_i;

    // One step: shift {rem, quo} left by 1 bit, then try subtracting the divisor
    wire [32:0] rem_sh = {rem_q, quo_q[31]};
    wire [32:0] trial  = rem_sh - {1'b0, dvs_q};
    wire        fits   = ~trial[32];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rem_q   <= 32'h0;
            quo_q   <= 32'h0;
            dvs_q   <= 32'h0;
            neg_q_q <= 1'b0;
            neg_r_q <= 1'b0;
        end else if (start & is_div) begin
            rem_q   <= 32'h0;
            quo_q   <= a_abs;
            dvs_q   <= b_abs;
            // Divide by 0: the quotient stays all ones and is not negated
            neg_q_q <= a_signed & (a_i[31] ^ b_i[31]) & (b_i != 32'h0);
            neg_r_q <= a_signed & a_i[31];
        end else if (busy_q & div_q & (cnt_q != 6'd0)) begin
            rem_q   <= fits ? trial[31:0] : rem_sh[31:0];
            quo_q   <= {quo_q[30:0], fits};
        end
    end

    wire [31:0] quo_res = neg_q_q ? (32'h0 - quo_q) : quo_q;
    wire [31:0] rem_res = neg_r_q ? (32'h0 - rem_q) : rem_q;

    assign result_o = div_q ? (hi_q ? rem_res : quo_res) :
                              (hi_q ? prod[63:32] : prod[31:0]);

endmodule

`default_nettype wire
