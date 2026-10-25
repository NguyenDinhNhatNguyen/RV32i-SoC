`timescale 1ns/1ps
`default_nettype none
// sys_bus - SoC valid/ready interconnect (RTL-03).
// Protocol: docs/spec/core.md section 5.1. Address map: rtl/bus/soc_map.vh.
// Timing diagrams: docs/timing_bus.md. Design notes: docs/bus_mem.md.
//
// Masters: N_MASTER ports (1 is the core data port, 2 with DMA), round-robin
// arbitration. Slaves: the IMEM data port (imem_port), DMEM (sram_wrap), the APB
// bridge (regions 0x2, 0x3, 0x4, apb_bridge) and an internal error slave.
//
// The whole bus has at most 1 request waiting for a response. A new request is accepted
// when nothing is waiting, or in the same cycle the previous response arrives (rule 3).
// With 1 master this adds no cycle compared with wiring the master straight to the
// slave, so back-to-back loads from SRAM still run at 1 per cycle.
//
// Once a request is visible at a slave that has not accepted it (ready = 0), the grant
// stays with that master until acceptance, so the slave always sees a stable request (rule 1).
//
// Error slave: unmapped addresses (beyond the IMEM/DMEM size, data bus reads of the
// boot ROM, regions other than 0x0-0x4) are accepted at once, and the next cycle has
// rsp_valid with err = 1, rdata = 0. Empty APB slots or disabled features get err from apb_bridge.
//
// Combinational paths: m_req_ready depends on m_req_valid and the slave's rsp_valid (from
// a slave flop). There is no path from a slave's ready back to valid (rule 5).
`include "soc_map.vh"

module sys_bus #(
    parameter N_MASTER    = 1,                  // 1, 2 or 4
    parameter IMEM_BANK_W = `SOC_IMEM_BANK_W,   // Must equal BANK_W of imem_port
    parameter DMEM_BANK_W = `SOC_DMEM_BANK_W    // Must equal BANK_W of the DMEM sram_wrap
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Masters, flattened: master i is slice [i] or [i*32 +: 32]
    input  wire [N_MASTER-1:0]    m_req_valid,
    output wire [N_MASTER-1:0]    m_req_ready,
    input  wire [N_MASTER*32-1:0] m_addr,
    input  wire [N_MASTER-1:0]    m_we,
    input  wire [N_MASTER*4-1:0]  m_be,
    input  wire [N_MASTER*32-1:0] m_wdata,
    output wire [N_MASTER-1:0]    m_rsp_valid,
    output wire [31:0]            m_rsp_rdata,  // Shared, valid only for the master with rsp_valid
    output wire [N_MASTER-1:0]    m_rsp_err,    // Per master, 0 without rsp_valid

    // Request channel shared by every slave, each slave has its own valid
    output wire [31:0]            s_addr,
    output wire                   s_we,
    output wire [3:0]             s_be,
    output wire [31:0]            s_wdata,

    // IMEM data port (imem_port)
    output wire                   imem_req_valid,
    input  wire                   imem_req_ready,
    input  wire                   imem_rsp_valid,
    input  wire [31:0]            imem_rsp_rdata,

    // DMEM (sram_wrap)
    output wire                   dmem_req_valid,
    input  wire                   dmem_req_ready,
    input  wire                   dmem_rsp_valid,
    input  wire [31:0]            dmem_rsp_rdata,

    // APB bridge (apb_bridge)
    output wire                   apb_req_valid,
    input  wire                   apb_req_ready,
    input  wire                   apb_rsp_valid,
    input  wire [31:0]            apb_rsp_rdata,
    input  wire                   apb_rsp_err
);

    localparam MW = (N_MASTER > 2) ? 2 : 1;     // Master index width
    localparam [MW-1:0] ONE = 1;

    localparam [31:0] IMEM_SIZE = 32'd4096 << IMEM_BANK_W;
    localparam [31:0] DMEM_SIZE = 32'd4096 << DMEM_BANK_W;

    localparam [1:0] S_IMEM = 2'd0,
                     S_DMEM = 2'd1,
                     S_APB  = 2'd2,
                     S_ERR  = 2'd3;

    reg           pend_q;       // A request was accepted and has no response yet
    reg  [1:0]    pend_slv_q;   // Slave that will return that response
    reg  [MW-1:0] pend_mst_q;   // Master that receives that response
    reg           hold_q;       // Last cycle a request was visible at a slave but not accepted
    reg  [MW-1:0] hold_mst_q;
    reg  [MW-1:0] rr_q;         // Most recently accepted master

    // Round-robin arbiter: scan rr_q, rr_q-1, ... , rr_q+1. The last valid master scanned
    // wins, so rr_q+1 has the highest priority and rr_q the lowest.
    reg  [MW-1:0] rr_pick;
    reg  [MW-1:0] cand;
    integer       k;

    always @(*) begin
        rr_pick = rr_q;
        cand    = rr_q;
        for (k = 0; k < N_MASTER; k = k + 1) begin
            if (m_req_valid[cand])
                rr_pick = cand;
            cand = cand - ONE;
        end
    end

    wire [MW-1:0] g       = hold_q ? hold_mst_q : rr_pick;   // Selected master
    wire          g_valid = m_req_valid[g];

    assign s_addr  = m_addr [g*32 +: 32];
    assign s_we    = m_we   [g];
    assign s_be    = m_be   [g*4 +: 4];
    assign s_wdata = m_wdata[g*32 +: 32];

    // Address decode: addr[31:28] selects the region. Region 0x0 holds only IMEM on the
    // data bus (the boot ROM at 0x0001_0000 is beyond IMEM_SIZE, so it goes to the error slave).
    reg [1:0] slv;
    always @(*) begin
        case (s_addr[31:28])
            `SOC_RGN_MEM0:   slv = ({4'h0, s_addr[27:0]} < IMEM_SIZE) ? S_IMEM : S_ERR;
            `SOC_RGN_DMEM:   slv = ({4'h0, s_addr[27:0]} < DMEM_SIZE) ? S_DMEM : S_ERR;
            `SOC_RGN_PERIPH,
            `SOC_RGN_ACCEL,
            `SOC_RGN_DMA:    slv = S_APB;
            default:         slv = S_ERR;
        endcase
    end

    // Response to the waiting request, the error slave answers in the very next cycle
    reg rsp_src_valid;
    always @(*) begin
        case (pend_slv_q)
            S_IMEM:  rsp_src_valid = imem_rsp_valid;
            S_DMEM:  rsp_src_valid = dmem_rsp_valid;
            S_APB:   rsp_src_valid = apb_rsp_valid;
            default: rsp_src_valid = 1'b1;
        endcase
    end

    wire rsp_fire = pend_q & rsp_src_valid;
    wire rsp_err  = (pend_slv_q == S_APB) ? apb_rsp_err : (pend_slv_q == S_ERR);

    assign m_rsp_rdata = (pend_slv_q == S_IMEM) ? imem_rsp_rdata :
                         (pend_slv_q == S_DMEM) ? dmem_rsp_rdata :
                         (pend_slv_q == S_APB)  ? apb_rsp_rdata  : 32'h0;

    // Request to the slave
    wire can_acc = ~pend_q | rsp_fire;          // Rule 3
    wire vis     = g_valid & can_acc;           // The request is visible at the slave

    assign imem_req_valid = vis & (slv == S_IMEM);
    assign dmem_req_valid = vis & (slv == S_DMEM);
    assign apb_req_valid  = vis & (slv == S_APB);

    reg slv_ready;
    always @(*) begin
        case (slv)
            S_IMEM:  slv_ready = imem_req_ready;
            S_DMEM:  slv_ready = dmem_req_ready;
            S_APB:   slv_ready = apb_req_ready;
            default: slv_ready = 1'b1;
        endcase
    end

    wire acc = vis & slv_ready;                 // The request is accepted this cycle

    // One-hot decode of the master index for ready and rsp_valid
    reg [N_MASTER-1:0] g_oh;
    reg [N_MASTER-1:0] p_oh;
    integer j;
    always @(*) begin
        for (j = 0; j < N_MASTER; j = j + 1) begin
            g_oh[j] = (g          == j[MW-1:0]);
            p_oh[j] = (pend_mst_q == j[MW-1:0]);
        end
    end

    assign m_req_ready = {N_MASTER{acc}} & g_oh;
    assign m_rsp_valid = {N_MASTER{rsp_fire}} & p_oh;
    assign m_rsp_err   = {N_MASTER{rsp_fire & rsp_err}} & p_oh;

    // State
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_q     <= 1'b0;
            pend_slv_q <= S_ERR;
            pend_mst_q <= {MW{1'b0}};
            hold_q     <= 1'b0;
            hold_mst_q <= {MW{1'b0}};
            rr_q       <= {MW{1'b0}};
        end else begin
            hold_q <= vis & ~slv_ready;
            if (vis & ~slv_ready)
                hold_mst_q <= g;
            if (acc) begin
                pend_q     <= 1'b1;
                pend_slv_q <= slv;
                pend_mst_q <= g;
                rr_q       <= g;
            end else if (rsp_fire) begin
                pend_q     <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
