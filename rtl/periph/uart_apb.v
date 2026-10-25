// uart_apb.v - UART 8N1, APB3 slave (RTL-10)
// Base: 0x2000_1000 (4 KB window). Word access only, other offsets -> PSLVERR.
//
//   0x00 DATA     W: push byte [7:0] into the TX FIFO (full -> byte dropped, sets TXOVF)
//                 R: pop byte [7:0] from the RX FIFO (empty -> returns 0, no error)
//   0x04 STATUS   R: [0] TXF  TX FIFO full
//                    [1] TXE  TX FIFO empty
//                    [2] TXB  shifting (TX shifter busy)
//                    [3] RXF  RX FIFO full
//                    [4] RXNE RX FIFO has data
//                    [5] OVR  RX FIFO full when a new byte arrived (sticky)
//                    [6] FE   stop bit = 0 (sticky)
//                    [7] TXOVF DATA written while the TX FIFO was full (sticky)
//                 W: write 1 to bits 5..7 to clear them, other bits are ignored
//   0x08 CTRL     RW [0] TXEN [1] RXEN [2] TXIE [3] RXIE [4] ERRIE   reset = 0x03
//   0x0C BAUDDIV  RW [15:0] DIV: baud = f_clk / (16 * DIV), DIV=0 works as 1
//                 reset = DIV_RESET (27 -> 115200 baud at 50 MHz, error +0.47%)
//
// irq (level, registered by 1 flop) = TXIE&TXE | RXIE&RXNE | ERRIE&(OVR|FE|TXOVF)
// 8N1 frame: start(0), 8 bits LSB first, stop(1). RX samples at 16x, in the middle of each bit.
// The uart_rxd input is asynchronous -> 2-flop synchronizer.
`timescale 1ns/1ps
module uart_apb #(
    parameter        FIFO_AW   = 3,          // FIFO depth = 2**FIFO_AW (TX and RX)
    parameter [15:0] DIV_RESET = 16'd27      // 50 MHz / (16 x 115200)
) (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [11:0] PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,
    output reg         uart_txd,
    input  wire        uart_rxd,
    output reg         irq
);
    // ------------------------------------------------------------------
    // APB
    // ------------------------------------------------------------------
    wire [9:0] widx    = PADDR[11:2];
    wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd3);
    wire       access  = PSEL & PENABLE;
    wire       wr_ok   = access &  PWRITE & addr_ok;
    wire       rd_ok   = access & ~PWRITE & addr_ok;

    wire wr_data   = wr_ok && (widx == 10'd0);
    wire wr_status = wr_ok && (widx == 10'd1);
    wire wr_ctrl   = wr_ok && (widx == 10'd2);
    wire wr_div    = wr_ok && (widx == 10'd3);
    wire rd_data   = rd_ok && (widx == 10'd0);

    assign PREADY  = 1'b1;
    assign PSLVERR = access & ~addr_ok;

    wire unused_ok = &{1'b0, PWDATA[31:16]};

    // ------------------------------------------------------------------
    // Control registers
    // ------------------------------------------------------------------
    reg        tx_en, rx_en, tx_ie, rx_ie, err_ie;
    reg [15:0] div;
    reg        overrun, frame_err, tx_ovf;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_en  <= 1'b1;
            rx_en  <= 1'b1;
            tx_ie  <= 1'b0;
            rx_ie  <= 1'b0;
            err_ie <= 1'b0;
        end else if (wr_ctrl) begin
            tx_en  <= PWDATA[0];
            rx_en  <= PWDATA[1];
            tx_ie  <= PWDATA[2];
            rx_ie  <= PWDATA[3];
            err_ie <= PWDATA[4];
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)      div <= DIV_RESET;
        else if (wr_div)   div <= PWDATA[15:0];
    end

    // ------------------------------------------------------------------
    // Baud generator: tick = 1 pulse every DIV clk cycles (16x the baud rate)
    // Runs only when TX or RX is enabled.
    // ------------------------------------------------------------------
    wire [15:0] div_m1 = (div > 16'd1) ? (div - 16'd1) : 16'd0;
    reg  [15:0] bcnt;
    reg         tick;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            bcnt <= 16'd0;
            tick <= 1'b0;
        end else if (!(tx_en | rx_en)) begin
            bcnt <= 16'd0;
            tick <= 1'b0;
        end else if (bcnt == 16'd0) begin
            bcnt <= div_m1;
            tick <= 1'b1;
        end else begin
            bcnt <= bcnt - 16'd1;
            tick <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // TX FIFO + transmitter
    // ------------------------------------------------------------------
    wire       tx_full, tx_empty;
    wire [7:0] tx_dout;
    reg  [3:0] tx_bits;           // Bits left in the frame (0 = idle)
    reg  [3:0] tx_os;             // Tick counter inside 1 bit
    reg  [8:0] tx_sh;             // {stop, d7..d0}, the start bit is sent directly

    wire tx_start = tick & (tx_bits == 4'd0) & tx_en & ~tx_empty;
    wire tx_bound = tick & (tx_bits != 4'd0) & (tx_os == 4'd15);

    uart_fifo #(.DW(8), .AW(FIFO_AW)) u_txf (
        .clk(PCLK), .rst_n(PRESETn),
        .push(wr_data), .din(PWDATA[7:0]),
        .pop(tx_start), .dout(tx_dout),
        .full(tx_full), .empty(tx_empty)
    );

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            uart_txd <= 1'b1;
            tx_bits  <= 4'd0;
            tx_os    <= 4'd0;
        end else if (tick) begin
            if (tx_bits == 4'd0) begin
                if (tx_start) begin
                    tx_bits  <= 4'd10;
                    tx_os    <= 4'd0;
                    uart_txd <= 1'b0;                 // Start bit
                end
            end else begin
                tx_os <= tx_os + 4'd1;
                if (tx_os == 4'd15) begin
                    tx_bits  <= tx_bits - 4'd1;
                    uart_txd <= tx_sh[0];             // Next bit (1 when done)
                end
            end
        end
    end

    // The shift register has no reset: used only after it is loaded
    always @(posedge PCLK) begin
        if (tx_start)      tx_sh <= {1'b1, tx_dout};
        else if (tx_bound) tx_sh <= {1'b1, tx_sh[8:1]};
    end

    wire tx_busy = (tx_bits != 4'd0);

    // ------------------------------------------------------------------
    // RX: synchronize, 16x sampling, RX FIFO
    // ------------------------------------------------------------------
    localparam [2:0] R_IDLE = 3'd0, R_START = 3'd1, R_DATA = 3'd2,
                     R_STOP = 3'd3, R_WAIT  = 3'd4;

    reg        rx_s1, rx_s2;
    reg  [2:0] rx_st;
    reg  [3:0] rx_os;
    reg  [2:0] rx_bit;
    reg  [7:0] rx_sh;

    wire       rx_full, rx_empty;
    wire [7:0] rx_dout;

    wire rx_stop_smp = tick & (rx_st == R_STOP) & (rx_os == 4'd15);
    wire rx_good     = rx_stop_smp &  rx_s2;
    wire rx_bad      = rx_stop_smp & ~rx_s2;
    wire rx_pop      = rd_data & ~rx_empty;

    uart_fifo #(.DW(8), .AW(FIFO_AW)) u_rxf (
        .clk(PCLK), .rst_n(PRESETn),
        .push(rx_good), .din(rx_sh),
        .pop(rx_pop), .dout(rx_dout),
        .full(rx_full), .empty(rx_empty)
    );

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= uart_rxd;
            rx_s2 <= rx_s1;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_st  <= R_IDLE;
            rx_os  <= 4'd0;
            rx_bit <= 3'd0;
        end else if (tick) begin
            case (rx_st)
                R_IDLE: begin
                    if (rx_en & ~rx_s2) begin       // Falling edge: maybe a start bit
                        rx_st <= R_START;
                        rx_os <= 4'd0;
                    end
                end
                R_START: begin                       // Check again in the middle of the start bit
                    if (rx_os == 4'd7) begin
                        if (~rx_s2) begin
                            rx_st  <= R_DATA;
                            rx_os  <= 4'd0;
                            rx_bit <= 3'd0;
                        end else begin
                            rx_st <= R_IDLE;         // Noise, ignore
                        end
                    end else begin
                        rx_os <= rx_os + 4'd1;
                    end
                end
                R_DATA: begin
                    rx_os <= rx_os + 4'd1;
                    if (rx_os == 4'd15) begin
                        rx_bit <= rx_bit + 3'd1;
                        if (rx_bit == 3'd7) rx_st <= R_STOP;
                    end
                end
                R_STOP: begin
                    rx_os <= rx_os + 4'd1;
                    if (rx_os == 4'd15) rx_st <= rx_s2 ? R_IDLE : R_WAIT;
                end
                default: begin                       // R_WAIT: wait for the line to go high
                    if (rx_s2) rx_st <= R_IDLE;
                end
            endcase
        end
    end

    // The shift register has no reset: all 8 bits are filled before it is pushed to the FIFO
    always @(posedge PCLK) begin
        if (tick && rx_st == R_DATA && rx_os == 4'd15)
            rx_sh <= {rx_s2, rx_sh[7:1]};
    end

    // ------------------------------------------------------------------
    // Sticky error flags (cleared by writing 1 to STATUS[7:5], set wins over clear)
    // ------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            overrun   <= 1'b0;
            frame_err <= 1'b0;
            tx_ovf    <= 1'b0;
        end else begin
            if (wr_status & PWDATA[5]) overrun   <= 1'b0;
            if (wr_status & PWDATA[6]) frame_err <= 1'b0;
            if (wr_status & PWDATA[7]) tx_ovf    <= 1'b0;
            if (rx_good & rx_full)     overrun   <= 1'b1;
            if (rx_bad)                frame_err <= 1'b1;
            if (wr_data & tx_full)     tx_ovf    <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Interrupt and readback
    // ------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) irq <= 1'b0;
        else          irq <= (tx_ie  &  tx_empty)
                           | (rx_ie  & ~rx_empty)
                           | (err_ie & (overrun | frame_err | tx_ovf));
    end

    always @(*) begin
        if (!addr_ok) PRDATA = 32'd0;
        else case (widx)
            10'd0:   PRDATA = {24'd0, (rx_empty ? 8'd0 : rx_dout)};
            10'd1:   PRDATA = {24'd0, tx_ovf, frame_err, overrun, ~rx_empty,
                               rx_full, tx_busy, tx_empty, tx_full};
            10'd2:   PRDATA = {27'd0, err_ie, rx_ie, tx_ie, rx_en, tx_en};
            10'd3:   PRDATA = {16'd0, div};
            default: PRDATA = 32'd0;
        endcase
    end
endmodule
