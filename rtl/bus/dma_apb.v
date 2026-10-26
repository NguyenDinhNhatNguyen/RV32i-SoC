`timescale 1ns/1ps
`default_nettype none
// dma_apb - word DMA with an APB3 config port and a sys_bus master port (RTL-15).
// Copies LEN words from SRC to DST without the CPU, for example DMEM <-> accelerator buffers.
// Base 0x4000_0000 (APB slot 8, 4 KB window). Word access only, other offsets -> PSLVERR.
//   0x00 SRC     RW  Source byte address, bits 1:0 read 0 (word aligned)
//   0x04 DST     RW  Destination byte address, bits 1:0 read 0
//   0x08 LEN     RW  Number of words [15:0]. LEN = 0 sets DONE at once
//   0x0C CTRL    W   bit0 START (taken only when idle), bit1 IRQ_EN.  R: bit1 IRQ_EN
//   0x10 STATUS  R   bit0 BUSY, bit1 DONE, bit2 ERR.  W: write 1 to bit1 or bit2 to clear it
// Writes to SRC, DST, LEN and CTRL while BUSY are ignored. SRC, DST and LEN keep the
// programmed values, the running addresses and count are internal.
// START clears DONE and ERR. A bus error on a read or a write stops the transfer with
// ERR = 1 and DONE = 1. irq (level, registered by 1 flop) = DONE & IRQ_EN, wired to IRQC bit 4.
//
// Master port: protocol of docs/spec/core.md section 5.1, one request at a time, full words
// (be = 4'b1111). Each word is a read then a write, and both addresses go up by 4.
// req_valid comes from the state flops, or from rsp_valid when the next request is issued
// in the response cycle (rule 3). It never depends on req_ready (rule 5). A request that is
// not accepted moves to a state flop with the same address and data (rule 1).
// With SRAM on both sides one word takes 2 cycles.

module dma_apb (
    input  wire        PCLK,
    input  wire        PRESETn,

    // APB3 config port
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [11:0] PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // sys_bus master port
    output wire        m_req_valid,
    input  wire        m_req_ready,
    output wire [31:0] m_addr,
    output wire        m_we,
    output wire [3:0]  m_be,
    output wire [31:0] m_wdata,
    input  wire        m_rsp_valid,
    input  wire [31:0] m_rsp_rdata,
    input  wire        m_rsp_err,

    output reg         irq
);

    localparam [2:0] S_IDLE = 3'd0,
                     S_RD   = 3'd1,     // Read request waits for ready
                     S_RD_W = 3'd2,     // Read accepted, waits for the response
                     S_WR   = 3'd3,     // Write request waits for ready
                     S_WR_W = 3'd4;     // Write accepted, waits for the response

    reg  [2:0]  st;
    reg  [29:0] src, dst;               // Programmed word addresses
    reg  [15:0] len;
    reg         irq_en, done, err;
    reg  [29:0] cur_src, cur_dst;       // Running word addresses
    reg  [15:0] cnt;                    // Words left, including the current one
    reg  [31:0] buf_q;                  // Read data of the current word

    wire busy = (st != S_IDLE);

    // APB decode
    wire [9:0] widx    = PADDR[11:2];
    wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd4);
    wire       access  = PSEL & PENABLE;
    wire       wr_ok   = access & PWRITE & addr_ok;

    wire wr_src    = wr_ok && (widx == 10'd0) && !busy;
    wire wr_dst    = wr_ok && (widx == 10'd1) && !busy;
    wire wr_len    = wr_ok && (widx == 10'd2) && !busy;
    wire wr_ctrl   = wr_ok && (widx == 10'd3) && !busy;
    wire wr_status = wr_ok && (widx == 10'd4);
    wire start     = wr_ctrl & PWDATA[0];

    assign PREADY  = 1'b1;
    assign PSLVERR = access & ~addr_ok;

    // Master side
    wire rd_rsp = (st == S_RD_W) & m_rsp_valid;
    wire wr_rsp = (st == S_WR_W) & m_rsp_valid;
    wire rd_ok  = rd_rsp & ~m_rsp_err;
    wire wr_ok_bus = wr_rsp & ~m_rsp_err;
    wire last   = (cnt == 16'd1);

    // Request in this cycle. The next request may go out in the response cycle.
    wire req_rd = (st == S_RD) | (wr_ok_bus & ~last);
    wire req_wr = (st == S_WR) | rd_ok;
    wire acc    = m_req_valid & m_req_ready;

    assign m_req_valid = req_rd | req_wr;
    assign m_we        = req_wr;
    assign m_be        = 4'hF;
    assign m_addr      = req_wr ? {cur_dst, 2'b00} : {cur_src, 2'b00};
    assign m_wdata     = (st == S_WR) ? buf_q : m_rsp_rdata;

    // Config registers
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            src    <= 30'd0;
            dst    <= 30'd0;
            len    <= 16'd0;
            irq_en <= 1'b0;
        end else begin
            if (wr_src)  src    <= PWDATA[31:2];
            if (wr_dst)  dst    <= PWDATA[31:2];
            if (wr_len)  len    <= PWDATA[15:0];
            if (wr_ctrl) irq_en <= PWDATA[1];
        end
    end

    // Transfer state machine
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            st      <= S_IDLE;
            cur_src <= 30'd0;
            cur_dst <= 30'd0;
            cnt     <= 16'd0;
            buf_q   <= 32'd0;
            done    <= 1'b0;
            err     <= 1'b0;
        end else begin
            if (wr_status & PWDATA[1]) done <= 1'b0;
            if (wr_status & PWDATA[2]) err  <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (start) begin
                        err <= 1'b0;
                        if (len == 16'd0) begin
                            done <= 1'b1;
                        end else begin
                            done    <= 1'b0;
                            cur_src <= src;
                            cur_dst <= dst;
                            cnt     <= len;
                            st      <= S_RD;
                        end
                    end
                end
                S_RD: begin
                    if (acc) begin
                        cur_src <= cur_src + 30'd1;
                        st      <= S_RD_W;
                    end
                end
                S_RD_W: begin
                    if (rd_rsp && m_rsp_err) begin
                        err  <= 1'b1;
                        done <= 1'b1;
                        st   <= S_IDLE;
                    end else if (rd_ok) begin
                        buf_q <= m_rsp_rdata;
                        if (acc) begin
                            cur_dst <= cur_dst + 30'd1;
                            st      <= S_WR_W;
                        end else begin
                            st      <= S_WR;
                        end
                    end
                end
                S_WR: begin
                    if (acc) begin
                        cur_dst <= cur_dst + 30'd1;
                        st      <= S_WR_W;
                    end
                end
                default: begin                  // S_WR_W
                    if (wr_rsp && m_rsp_err) begin
                        err  <= 1'b1;
                        done <= 1'b1;
                        st   <= S_IDLE;
                    end else if (wr_ok_bus) begin
                        cnt <= cnt - 16'd1;
                        if (last) begin
                            done <= 1'b1;
                            st   <= S_IDLE;
                        end else if (acc) begin
                            cur_src <= cur_src + 30'd1;
                            st      <= S_RD_W;
                        end else begin
                            st      <= S_RD;
                        end
                    end
                end
            endcase
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) irq <= 1'b0;
        else          irq <= done & irq_en;
    end

    always @(*) begin
        case (widx)
            10'd0:   PRDATA = {src, 2'b00};
            10'd1:   PRDATA = {dst, 2'b00};
            10'd2:   PRDATA = {16'd0, len};
            10'd3:   PRDATA = {30'd0, irq_en, 1'b0};
            10'd4:   PRDATA = {29'd0, err, done, busy};
            default: PRDATA = 32'd0;
        endcase
    end

endmodule

`default_nettype wire
