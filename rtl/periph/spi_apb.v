// spi_apb.v - SPI Master APB3 slave (RTL-13)
`timescale 1ns/1ps
module spi_apb #(
    parameter ENABLE_SPI = 1
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
    // SPI signals
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n
);

    generate
        if (ENABLE_SPI) begin : gen_spi
            reg [7:0]  tx_data, rx_data;
            reg [15:0] ctrl_div;
            reg        ctrl_cpha, ctrl_cpol, ctrl_cs_n;
            
            // FSM & Counters
            reg        busy;
            reg [15:0] clk_cnt;
            reg [2:0]  bit_cnt;
            reg        spi_clk_reg;
            reg        mosi_reg;       // Bit on mosi, changes only on the driving edge
            reg        phase; // 0 = Leading edge, 1 = Trailing edge

            wire [9:0] widx    = PADDR[11:2];
            wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd2);
            wire       access  = PSEL & PENABLE;
            wire       wr_ok   = access & PWRITE & addr_ok;
            
            wire wr_data = wr_ok && (widx == 10'd0);
            wire wr_ctrl = wr_ok && (widx == 10'd2);

            assign PREADY  = 1'b1;
            assign PSLVERR = access & ~addr_ok;
            assign cs_n    = ctrl_cs_n;

            // Handle register write (APB Write)
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    ctrl_div  <= 16'd0;
                    ctrl_cpha <= 1'b0;
                    ctrl_cpol <= 1'b0;
                    ctrl_cs_n <= 1'b1; // Default unselected Slave (Active-Low)
                end else if (wr_ctrl) begin
                    ctrl_div  <= {8'd0, PWDATA[15:8]};
                    ctrl_cpha <= PWDATA[2];
                    ctrl_cpol <= PWDATA[1];
                    ctrl_cs_n <= PWDATA[0];
                end
            end

            // SPI FSM State
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    busy        <= 1'b0;
                    clk_cnt     <= 16'd0;
                    bit_cnt     <= 3'd7;
                    spi_clk_reg <= 1'b0;
                    phase       <= 1'b0;
                    tx_data     <= 8'd0;
                    rx_data     <= 8'd0;
                    mosi_reg    <= 1'b0;
                end else begin
                    if (!busy) begin
                        spi_clk_reg <= ctrl_cpol; // Idle: sclk held according to CPOL
                        if (wr_data) begin
                            tx_data <= PWDATA[7:0];
                            mosi_reg <= PWDATA[7];  // MSB is ready before the first edge
                            busy    <= 1'b1;
                            clk_cnt <= ctrl_div;
                            bit_cnt <= 3'd7;      // MSB first
                            phase   <= 1'b0;
                        end
                    end else begin
                        if (clk_cnt == 16'd0) begin
                            clk_cnt <= ctrl_div;
                            spi_clk_reg <= ~spi_clk_reg; // Toggle sclk state
                            phase <= ~phase;

                            // Sample MISO
                            if ((!ctrl_cpha && phase == 1'b0) || (ctrl_cpha && phase == 1'b1)) begin
                                rx_data[bit_cnt] <= miso;
                            end

                            // Drive MOSI on the edge that is not the sampling edge.
                            // CPHA = 0: next bit on the trailing edge.
                            // CPHA = 1: current bit on the leading edge, so it is stable at
                            // the trailing (sampling) edge.
                            if (!ctrl_cpha && phase == 1'b1 && bit_cnt != 3'd0)
                                mosi_reg <= tx_data[bit_cnt - 3'd1];
                            if (ctrl_cpha && phase == 1'b0)
                                mosi_reg <= tx_data[bit_cnt];

                            // Next bit after the trailing edge
                            if (phase == 1'b1) begin
                                if (bit_cnt == 3'd0) begin
                                    busy <= 1'b0; // Complete 8 bits
                                end else begin
                                    bit_cnt <= bit_cnt - 3'd1;
                                end
                            end
                        end else begin
                            clk_cnt <= clk_cnt - 16'd1;
                        end
                    end
                end
            end

            assign mosi = mosi_reg;
            assign sclk = spi_clk_reg;

            // PWDATA[31:16] is not used by any register, ctrl_div[15:8] is always 0
            wire unused_ok = &{1'b0, PWDATA[31:16]};

            // Read register (APB Read)
            always @(*) begin
                if (!addr_ok) PRDATA = 32'd0;
                else case (widx)
                    10'd0:   PRDATA = {24'd0, rx_data};
                    10'd1:   PRDATA = {31'd0, busy};
                    10'd2:   PRDATA = {16'd0, ctrl_div[7:0], 5'd0, ctrl_cpha, ctrl_cpol, ctrl_cs_n};
                    default: PRDATA = 32'd0;
                endcase
            end

        end else begin : gen_no_spi
            assign PREADY  = 1'b1;
            assign PSLVERR = (PSEL & PENABLE);
            assign sclk    = 1'b0;
            assign mosi    = 1'b0;
            assign cs_n    = 1'b1;
            always @(*) PRDATA = 32'd0;
        end
    endgenerate

endmodule
