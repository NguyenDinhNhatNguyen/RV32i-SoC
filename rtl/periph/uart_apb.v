// uart_apb.v - UART 8N1, APB3 slave (RTL-10)
// Base: 0x2000_1000 (cua so 4 KB). Chi truy cap word, offset khac -> PSLVERR.
//
//   0x00 DATA     W: day byte [7:0] vao TX FIFO (day -> bo byte, set TXOVF)
//                 R: lay byte [7:0] tu RX FIFO (rong -> tra 0, khong loi)
//   0x04 STATUS   R: [0] TXF  TX FIFO day
//                    [1] TXE  TX FIFO rong
//                    [2] TXB  dang dich (TX shifter ban)
//                    [3] RXF  RX FIFO day
//                    [4] RXNE RX FIFO co du lieu
//                    [5] OVR  RX FIFO day khi co byte moi (sticky)
//                    [6] FE   stop bit = 0 (sticky)
//                    [7] TXOVF ghi DATA khi TX FIFO day (sticky)
//                 W: ghi 1 vao bit 5..7 de xoa; cac bit khac bo qua
//   0x08 CTRL     RW [0] TXEN [1] RXEN [2] TXIE [3] RXIE [4] ERRIE   reset = 0x03
//   0x0C BAUDDIV  RW [15:0] DIV: baud = f_clk / (16 * DIV); DIV=0 hoat dong nhu 1
//                 reset = DIV_RESET (27 -> 115200 baud tai 50 MHz, sai so +0.47%)
//
// irq (muc, dang ky 1 flop) = TXIE&TXE | RXIE&RXNE | ERRIE&(OVR|FE|TXOVF)
// Khung 8N1: start(0), 8 bit LSB truoc, stop(1). RX lay mau 16x, o giua bit.
// Dau vao uart_rxd bat dong bo -> dong bo 2 flop.
module uart_apb #(
    parameter        FIFO_AW   = 3,          // do sau FIFO = 2**FIFO_AW (TX va RX)
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
    // Thanh ghi dieu khien
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
    // Baud generator: tick = 1 xung / DIV chu ky clk (tan so 16x baud)
    // Chi chay khi TX hoac RX duoc bat.
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
    // TX FIFO + bo phat
    // ------------------------------------------------------------------
    wire       tx_full, tx_empty;
    wire [7:0] tx_dout;
    reg  [3:0] tx_bits;           // so bit con lai cua khung (0 = ranh)
    reg  [3:0] tx_os;             // dem tick trong 1 bit
    reg  [8:0] tx_sh;             // {stop, d7..d0}; start bit duoc phat truc tiep

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
                    uart_txd <= 1'b0;                 // start bit
                end
            end else begin
                tx_os <= tx_os + 4'd1;
                if (tx_os == 4'd15) begin
                    tx_bits  <= tx_bits - 4'd1;
                    uart_txd <= tx_sh[0];             // bit ke tiep (1 khi het)
                end
            end
        end
    end

    // thanh ghi dich khong reset: chi duoc dung sau khi nap
    always @(posedge PCLK) begin
        if (tx_start)      tx_sh <= {1'b1, tx_dout};
        else if (tx_bound) tx_sh <= {1'b1, tx_sh[8:1]};
    end

    wire tx_busy = (tx_bits != 4'd0);

    // ------------------------------------------------------------------
    // RX: dong bo, nhan 16x, RX FIFO
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
                    if (rx_en & ~rx_s2) begin       // canh xuong: co the la start
                        rx_st <= R_START;
                        rx_os <= 4'd0;
                    end
                end
                R_START: begin                       // kiem tra lai o giua start bit
                    if (rx_os == 4'd7) begin
                        if (~rx_s2) begin
                            rx_st  <= R_DATA;
                            rx_os  <= 4'd0;
                            rx_bit <= 3'd0;
                        end else begin
                            rx_st <= R_IDLE;         // nhieu, bo qua
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
                default: begin                       // R_WAIT: cho duong ve muc cao
                    if (rx_s2) rx_st <= R_IDLE;
                end
            endcase
        end
    end

    // thanh ghi dich khong reset: du 8 bit truoc khi duoc day vao FIFO
    always @(posedge PCLK) begin
        if (tick && rx_st == R_DATA && rx_os == 4'd15)
            rx_sh <= {rx_s2, rx_sh[7:1]};
    end

    // ------------------------------------------------------------------
    // Co loi sticky (xoa bang ghi 1 vao STATUS[7:5]; set thang xoa)
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
    // Ngat va doc lai
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
