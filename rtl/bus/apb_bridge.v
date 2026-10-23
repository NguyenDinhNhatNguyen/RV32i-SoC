`timescale 1ns/1ps
`default_nettype none
// apb_bridge - cầu từ bus valid/ready sang APB3 (RTL-03).
// Slave của sys_bus cho vùng 0x2 (ngoại vi), 0x3 (accelerator), 0x4 (DMA).
// Mỗi ngoại vi là một APB3 slave với một bit PSEL riêng, chỉ số khe ở soc_map.vh.
//
// Giải mã khe:
//   0x2000_0000 + n*0x1000, n = 0..6   -> khe n (Timer, UART, GPIO, SPI, I2C, PWM, IRQC)
//   0x3000_0000 .. 0x3000_0FFF        -> khe SOC_APB_ACCEL
//   0x4000_0000 .. 0x4000_0FFF        -> khe SOC_APB_DMA
// PADDR là 12 bit offset trong khe 4 KB, khớp accel_apb, timer_apb, gpio_apb.
//
// Trả err ngay (chu kỳ sau khi nhận, không có giao dịch APB) khi:
//   - địa chỉ không thuộc khe nào, hoặc khe đang tắt (APB_EN = 0)
//   - truy cập không đủ word (be != 4'b1111), vì APB3 không có PSTRB.
//     Firmware đọc/ghi ngoại vi bằng lw/sw.
// PSLVERR của slave thành err.
//
// Timing: chu kỳ t nhận yêu cầu, t+1 SETUP (PSEL=1, PENABLE=0), t+2 ACCESS
// (PENABLE=1) giữ tới khi PREADY=1, chu kỳ sau đó có rsp_valid. Không có wait
// state ở slave thì một truy cập mất 3 chu kỳ. Mọi ngõ ra APB và phản hồi đều
// lấy từ flop. req_ready = 1 khi rảnh, kể cả ở chu kỳ có rsp_valid (luật 3).
`include "soc_map.vh"

module apb_bridge #(
    parameter [`SOC_APB_N-1:0] APB_EN = {`SOC_APB_N{1'b1}}   // bit = 1: khe có slave
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

    // APB3 master, PRDATA của khe i ở prdata[i*32 +: 32]
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
    reg [3:0] slot_q;           // khe của giao dịch đang chạy

    // Giải mã khe
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

    // FSM APB. Thanh ghi dữ liệu chỉ nạp khi cần để Genus gate clock.
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
                        rsp_valid <= 1'b1;          // slave lỗi: không có giao dịch APB
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
