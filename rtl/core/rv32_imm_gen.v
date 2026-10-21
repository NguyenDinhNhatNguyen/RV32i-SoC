`timescale 1ns/1ps
`default_nettype none
// rv32_imm_gen - sinh immediate cho các dạng lệnh RV32I (thuần tổ hợp).
// Dạng immediate lấy từ rv32_decoder nên không cần các bit opcode ở đây.
`include "rv32_defs.vh"

module rv32_imm_gen (
    input  wire [31:7] instr_i,   // không dùng instr[6:0] (opcode)
    input  wire [2:0]  imm_type_i, // RV_IMM_*
    output reg  [31:0] imm_o
);

    wire sign = instr_i[31];

    always @(*) begin
        imm_o = 32'h0;
        case (imm_type_i)
            `RV_IMM_I: imm_o = {{21{sign}}, instr_i[30:20]};
            `RV_IMM_S: imm_o = {{21{sign}}, instr_i[30:25], instr_i[11:7]};
            `RV_IMM_B: imm_o = {{20{sign}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
            `RV_IMM_U: imm_o = {instr_i[31:12], 12'h0};
            `RV_IMM_J: imm_o = {{12{sign}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
            `RV_IMM_Z: imm_o = {27'h0, instr_i[19:15]};
            default:   imm_o = 32'h0;
        endcase
    end

endmodule

`default_nettype wire
