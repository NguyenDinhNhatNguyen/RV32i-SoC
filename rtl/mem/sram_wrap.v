`timescale 1ns/1ps
`default_nettype none
// sram_wrap - valid/ready slave for an SRAM macro array (RTL-08).
// Used as DMEM and as the core of imem_port. Protocol: docs/spec/core.md section 5.1.
//
// Full-word reads and writes (be = 4'b1111): req_ready = 1, rsp_valid the very next cycle.
// Byte/half writes (SB, SH): the macro has no byte write pins, so read-modify-write
// (SoC spec section 7.3). Cycle 1 reads the old word with req_ready = 0 (wait state),
// cycle 2 merges the new bytes by be and writes, req_ready = 1. The master keeps its
// request in the wait state (rule 1), so addr, be and wdata are still there in cycle 2.
//
// rsp_rdata = the macro Q in the response cycle of a read, and 0 for a write
// (the macro Q after a write cycle is undefined). There is no err because sys_bus already
// blocks out-of-range addresses.
//
// f_* port: a low-priority read port for instruction fetch (imem_port). The bus always
// wins: f_gnt = 0 in every cycle with req_valid, including read-modify-write wait states.
// DMEM ties f_req = 0, and Genus removes this logic.

module sram_wrap #(
    parameter BANK_W = 2,               // Macro count = 2^BANK_W, 4 KB each
    parameter AW     = 10 + BANK_W      // Word address width, do not override
) (
    input  wire          clk,
    input  wire          rst_n,

    // Slave valid/ready
    input  wire          req_valid,
    output wire          req_ready,
    input  wire [31:0]   req_addr,      // Uses addr[AW+1:2]
    input  wire          req_we,
    input  wire [3:0]    req_be,
    input  wire [31:0]   req_wdata,
    output reg           rsp_valid,
    output wire [31:0]   rsp_rdata,

    // Low-priority read port
    input  wire          f_req,
    output wire          f_gnt,
    input  wire [AW-1:0] f_addr,        // Word address
    output wire [31:0]   f_rdata        // The cycle after f_req && f_gnt
);

    reg  rmw_q;         // Last cycle read the old word for a partial write
    reg  rd_q;          // Last cycle accepted a read

    wire part = req_we & (req_be != 4'hF);
    assign req_ready = ~part | rmw_q;
    wire acc = req_valid & req_ready;

    // Macro array. With req_valid the bus owns the macros: write when a write is accepted,
    // otherwise read (a read, or the read cycle of a read-modify-write).
    wire [31:0] q;
    wire [31:0] merged;

    assign merged[ 7: 0] = req_be[0] ? req_wdata[ 7: 0] : q[ 7: 0];
    assign merged[15: 8] = req_be[1] ? req_wdata[15: 8] : q[15: 8];
    assign merged[23:16] = req_be[2] ? req_wdata[23:16] : q[23:16];
    assign merged[31:24] = req_be[3] ? req_wdata[31:24] : q[31:24];

    sram_array #(.BANK_W(BANK_W)) u_arr (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (req_valid | f_req),
        .we    (acc & req_we),
        .addr  (req_valid ? req_addr[AW+1:2] : f_addr),
        .wdata (rmw_q ? merged : req_wdata),
        .rdata (q)
    );

    assign f_gnt   = ~req_valid;
    assign f_rdata = q;

    // Response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rmw_q     <= 1'b0;
            rd_q      <= 1'b0;
            rsp_valid <= 1'b0;
        end else begin
            rmw_q     <= req_valid & part & ~rmw_q;
            rd_q      <= acc & ~req_we;
            rsp_valid <= acc;
        end
    end

    assign rsp_rdata = {32{rd_q}} & q;

    // Address bits outside the array are decoded by sys_bus, bits 1:0 are unused
    // (word access and be)
    wire unused_addr = &{1'b0, req_addr[31:AW+2], req_addr[1:0]};

endmodule

`default_nettype wire
