`timescale 1ns/1ps
`default_nettype none
// rv32_lsu_align - byte lane handling for load/store (purely combinational).
// Request side (EX): byte enables, write data per lane, misalignment check.
// Response side (WB): pick the selected byte/half, then sign- or zero-extend.
// Both sides use the load/store funct3 code (bit 2 = unsigned load,
// bits 1:0 = size). Size 2'b11 never gets here because the decoder already
// flagged it as illegal.
`include "rv32_defs.vh"

module rv32_lsu_align (
    // Request side
    input  wire [1:0]  req_size_i,       // funct3[1:0], RV_MEM_*
    input  wire [1:0]  req_addr_lo_i,    // addr[1:0]
    input  wire [31:0] req_wdata_i,      // rs2
    output reg  [3:0]  req_be_o,
    output reg  [31:0] req_wdata_o,
    output reg         req_misaligned_o,
    // Response side
    input  wire [2:0]  rsp_funct3_i,
    input  wire [1:0]  rsp_addr_lo_i,
    input  wire [31:0] rsp_rdata_i,      // Raw word from the bus
    output reg  [31:0] rsp_data_o        // Value written to rd
);

    // Write data is replicated to every lane instead of shifted. The selected lane always
    // gets the right byte without a shifter, and req_be_o tells the slave which lanes are real.
    always @(*) begin
        req_be_o         = 4'b0000;
        req_wdata_o      = req_wdata_i;
        req_misaligned_o = 1'b0;
        case (req_size_i)
            `RV_MEM_B: begin
                req_be_o    = 4'b0001 << req_addr_lo_i;
                req_wdata_o = {4{req_wdata_i[7:0]}};
            end
            `RV_MEM_H: begin
                req_be_o         = req_addr_lo_i[1] ? 4'b1100 : 4'b0011;
                req_wdata_o      = {2{req_wdata_i[15:0]}};
                req_misaligned_o = req_addr_lo_i[0];
            end
            `RV_MEM_W: begin
                req_be_o         = 4'b1111;
                req_misaligned_o = (req_addr_lo_i != 2'b00);
            end
            default: begin
                req_be_o         = 4'b0000;
                req_misaligned_o = 1'b0;
            end
        endcase
    end

    // Move the selected byte/half down to bit 0 (accesses are always aligned, so
    // a half never crosses two words).
    wire [31:0] rsp_shifted = rsp_rdata_i >> {rsp_addr_lo_i, 3'b000};
    wire        rsp_signed  = ~rsp_funct3_i[2];

    always @(*) begin
        rsp_data_o = rsp_shifted;
        case (rsp_funct3_i[1:0])
            `RV_MEM_B: rsp_data_o = {{24{rsp_signed & rsp_shifted[7]}},  rsp_shifted[7:0]};
            `RV_MEM_H: rsp_data_o = {{16{rsp_signed & rsp_shifted[15]}}, rsp_shifted[15:0]};
            default:   rsp_data_o = rsp_shifted;
        endcase
    end

endmodule

`default_nettype wire
