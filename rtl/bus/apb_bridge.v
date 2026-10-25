`timescale 1ns/1ps
`default_nettype none
// apb_bridge - bridge from the valid/ready bus to APB3 (RTL-03).
// sys_bus slave for region 0x2 (peripherals), 0x3 (accelerator) and 0x4 (DMA).
// Each peripheral is an APB3 slave with its own PSEL bit, slot indexes are in soc_map.vh.
//
// Slot decode:
//   0x2000_0000 + n*0x1000, n = 0..6   -> slot n (Timer, UART, GPIO, SPI, I2C, PWM, IRQC)
//   0x3000_0000 .. 0x3000_0FFF        -> slot SOC_APB_ACCEL
//   0x4000_0000 .. 0x4000_0FFF        -> slot SOC_APB_DMA
// PADDR is the 12-bit offset inside the 4 KB slot, matching accel_apb, timer_apb, gpio_apb.
//
// Returns err right away (the cycle after acceptance, with no APB transfer) when:
//   - the address belongs to no slot, or the slot is disabled (APB_EN = 0)
//   - the access is not a full word (be != 4'b1111), because APB3 has no PSTRB.
//     Firmware reads and writes peripherals with lw/sw.
// A slave's PSLVERR becomes err.
//
// Timing: the request is accepted in cycle t, t+1 is SETUP (PSEL=1, PENABLE=0), t+2 is
// ACCESS (PENABLE=1) held until PREADY=1, and rsp_valid comes the cycle after. With no
// slave wait state an access takes 3 cycles. Every APB output and response comes from
// a flop. req_ready = 1 when idle, including the cycle with rsp_valid (rule 3).
`include "soc_map.vh"

module apb_bridge #(
    parameter [`SOC_APB_N-1:0] APB_EN = {`SOC_APB_N{1'b1}}   // Bit = 1: the slot has a slave
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // Slave valid/ready (sys_bus)
    input  wire                     req_valid,
    output wire                     req_ready,
    input  wire [31:0]              req_addr,
    input  wire                     req_we,
    input  wire [3:0]               req_be,
    input  wire [31:0]              req_wdata,
    output reg                      rsp_valid,
    output reg  [31:0]              rsp_rdata,
    output reg                      rsp_err,

    // APB3 master, PRDATA of slot i is prdata[i*32 +: 32]
    output reg  [`SOC_APB_N-1:0]    psel,
    output reg                      penable,
    output reg                      pwrite,
    output reg  [11:0]              paddr,
    output reg  [31:0]              pwdata,
    input  wire [`SOC_APB_N*32-1:0] prdata,
    input  wire [`SOC_APB_N-1:0]    pready,
    input  wire [`SOC_APB_N-1:0]    pslverr
);

    localparam [1:0] ST_IDLE   = 2'd0,
                     ST_SETUP  = 2'd1,
                     ST_ACCESS = 2'd2;

    reg [1:0] st;
    reg [3:0] slot_q;           // Slot of the running transfer

    // Slot decode
    reg       hit;
    reg [3:0] slot;
    always @(*) begin
        hit  = 1'b0;
        slot = 4'd0;
        case (req_addr[31:28])
            `SOC_RGN_PERIPH: begin
                slot = req_addr[15:12];
                hit  = (req_addr[27:16] == 12'h0) && (req_addr[15:12] <= 4'd`SOC_APB_IRQC);
            end
            `SOC_RGN_ACCEL: begin
                slot = 4'd`SOC_APB_ACCEL;
                hit  = (req_addr[27:12] == 16'h0);
            end
            `SOC_RGN_DMA: begin
                slot = 4'd`SOC_APB_DMA;
                hit  = (req_addr[27:12] == 16'h0);
            end
            default: ;
        endcase
    end

    wire ok  = hit & APB_EN[slot] & (req_be == 4'hF);
    assign req_ready = (st == ST_IDLE);
    wire acc = req_valid & req_ready;

    wire [31:0] prdata_sel  = prdata[slot_q*32 +: 32];
    wire        pready_sel  = pready[slot_q];
    wire        pslverr_sel = pslverr[slot_q];

    // APB FSM. The data registers load only when needed, so Genus can gate them.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            slot_q    <= 4'd0;
            psel      <= {`SOC_APB_N{1'b0}};
            penable   <= 1'b0;
            pwrite    <= 1'b0;
            paddr     <= 12'h0;
            pwdata    <= 32'h0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'h0;
            rsp_err   <= 1'b0;
        end else begin
            rsp_valid <= 1'b0;
            rsp_err   <= 1'b0;
            case (st)
                ST_IDLE: begin
                    if (acc && ok) begin
                        st     <= ST_SETUP;
                        slot_q <= slot;
                        psel   <= {{(`SOC_APB_N-1){1'b0}}, 1'b1} << slot;
                        pwrite <= req_we;
                        paddr  <= req_addr[11:0];
                        if (req_we)
                            pwdata <= req_wdata;
                    end else if (acc) begin
                        rsp_valid <= 1'b1;          // Error slave: no APB transfer
                        rsp_err   <= 1'b1;
                        rsp_rdata <= 32'h0;
                    end
                end
                ST_SETUP: begin
                    st      <= ST_ACCESS;
                    penable <= 1'b1;
                end
                default: begin                      // ST_ACCESS
                    if (pready_sel) begin
                        st        <= ST_IDLE;
                        psel      <= {`SOC_APB_N{1'b0}};
                        penable   <= 1'b0;
                        rsp_valid <= 1'b1;
                        rsp_err   <= pslverr_sel;
                        rsp_rdata <= (pwrite || pslverr_sel) ? 32'h0 : prdata_sel;
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
