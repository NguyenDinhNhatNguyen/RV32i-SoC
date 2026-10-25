`timescale 1ns/1ps
`default_nettype none
// rv32_alu - RV32I integer ALU (purely combinational).
// The core also uses the ALU (ADD) for load/store/JALR addresses and branch/JAL
// targets. Branch conditions use a separate comparator in the core.
`include "rv32_defs.vh"

module rv32_alu (
    input  wire [3:0]  op_i,      // RV_ALU_*
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    output reg  [31:0] result_o
);

    wire [4:0]  shamt = b_i[4:0];
    // One subtractor shared by SUB, SLT and SLTU.
    wire [32:0] diff  = {1'b0, a_i} - {1'b0, b_i};
    // a < b (unsigned) when the 33-bit subtraction borrows.
    wire        lt_u  = diff[32];
    // Signed: with equal signs use the borrow, with different signs a negative a is smaller.
    wire        lt_s  = (a_i[31] == b_i[31]) ? diff[32] : a_i[31];

    always @(*) begin
        result_o = 32'h0;
        case (op_i)
            `RV_ALU_ADD:  result_o = a_i + b_i;
            `RV_ALU_SUB:  result_o = diff[31:0];
            `RV_ALU_SLL:  result_o = a_i << shamt;
            `RV_ALU_SLT:  result_o = {31'b0, lt_s};
            `RV_ALU_SLTU: result_o = {31'b0, lt_u};
            `RV_ALU_XOR:  result_o = a_i ^ b_i;
            `RV_ALU_SRL:  result_o = a_i >> shamt;
            `RV_ALU_SRA:  result_o = $unsigned($signed(a_i) >>> shamt);
            `RV_ALU_OR:   result_o = a_i | b_i;
            `RV_ALU_AND:  result_o = a_i & b_i;
            default:      result_o = 32'h0;
        endcase
    end

endmodule

`default_nettype wire
