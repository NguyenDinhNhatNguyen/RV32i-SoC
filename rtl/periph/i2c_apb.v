// i2c_apb.v - I2C Master APB3 slave (RTL-14)
// Operates on Open-Drain mechanism: Logic 1 = High-Z (Pulled up by external resistor)
module i2c_apb #(
    parameter ENABLE_I2C = 1
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
    
    // I2C Open-Drain signals
    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_oe,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_oe
);

    generate
        if (ENABLE_I2C) begin : gen_i2c
            reg [7:0]  tx_data, rx_data;
            reg [15:0] ctrl_div;
            
            // FSM Commands
            reg cmd_start, cmd_stop, cmd_read, cmd_write, ack_out;
            reg busy, ack_in;

            wire [9:0] widx    = PADDR[11:2];
            wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd2);
            wire       access  = PSEL & PENABLE;
            wire       wr_ok   = access & PWRITE & addr_ok;
            
            wire wr_data = wr_ok && (widx == 10'd0);
            wire wr_cmd  = wr_ok && (widx == 10'd1);
            wire wr_ctrl = wr_ok && (widx == 10'd2);

            assign PREADY  = 1'b1;
            assign PSLVERR = access & ~addr_ok;

            // Handle APB Write
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    ctrl_div  <= 16'd0;
                    tx_data   <= 8'd0;
                    cmd_start <= 1'b0;
                    cmd_stop  <= 1'b0;
                    cmd_read  <= 1'b0;
                    cmd_write <= 1'b0;
                    ack_out   <= 1'b0;
                end else begin
                    // Automatically clear command flags when FSM starts processing (busy = 1)
                    if (busy) begin
                        cmd_start <= 1'b0;
                        cmd_stop  <= 1'b0;
                        cmd_read  <= 1'b0;
                        cmd_write <= 1'b0;
                    end else if (wr_ok) begin
                        if (wr_data) tx_data <= PWDATA[7:0];
                        if (wr_ctrl) ctrl_div <= PWDATA[15:0];
                        if (wr_cmd) begin
                            cmd_start <= PWDATA[0];
                            cmd_stop  <= PWDATA[1];
                            cmd_read  <= PWDATA[2];
                            cmd_write <= PWDATA[3];
                            ack_out   <= PWDATA[4];
                        end
                    end
                end
            end

            // I2C FSM States
            localparam [3:0] IDLE  = 4'd0,
                             START = 4'd1,
                             WRITE = 4'd2,
                             READ  = 4'd3,
                             ACK_W = 4'd4, // Wait for ACK from Slave during Write
                             ACK_R = 4'd5, // Send ACK to Slave during Read
                             STOP  = 4'd6;

            reg [3:0]  state;
            reg [15:0] clk_cnt;
            reg [1:0]  tick_cnt; // Divide 1 SCL clock period into 4 phases (Low, Rise, High, Fall)
            reg [2:0]  bit_cnt;
            reg        scl_reg, sda_reg;

            wire tick = (clk_cnt == 16'd0);

            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    state    <= IDLE;
                    clk_cnt  <= 16'd0;
                    tick_cnt <= 2'd0;
                    bit_cnt  <= 3'd7;
                    busy     <= 1'b0;
                    ack_in   <= 1'b1; // Default NACK
                    rx_data  <= 8'd0;
                    scl_reg  <= 1'b1;
                    sda_reg  <= 1'b1;
                end else begin
                    // Baud rate generator for I2C
                    if (state == IDLE && !cmd_start && !cmd_stop && !cmd_read && !cmd_write) begin
                        busy <= 1'b0;
                    end else begin
                        busy <= 1'b1;
                        if (clk_cnt != 16'd0) begin
                            clk_cnt <= clk_cnt - 16'd1;
                        end else begin
                            clk_cnt <= ctrl_div;
                            tick_cnt <= tick_cnt + 2'd1;
                            
                            case (state)
                                IDLE: begin
                                    if (cmd_start) state <= START;
                                    else if (cmd_write) state <= WRITE;
                                    else if (cmd_read) state <= READ;
                                    else if (cmd_stop) state <= STOP;
                                end
                                
                                START: begin
                                    // Generate START condition: SDA pulled low while SCL is high
                                    if (tick_cnt == 2'd0) sda_reg <= 1'b0;
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b0;
                                    if (tick_cnt == 2'd3) begin
                                        if (cmd_write) state <= WRITE;
                                        else if (cmd_read) state <= READ;
                                        else state <= IDLE;
                                    end
                                end

                                WRITE: begin
                                    if (tick_cnt == 2'd0) sda_reg <= tx_data[bit_cnt];
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                    if (tick_cnt == 2'd3) begin
                                        scl_reg <= 1'b0;
                                        if (bit_cnt == 3'd0) begin
                                            bit_cnt <= 3'd7;
                                            state <= ACK_W;
                                        end else begin
                                            bit_cnt <= bit_cnt - 3'd1;
                                        end
                                    end
                                end

                                READ: begin
                                    if (tick_cnt == 2'd0) sda_reg <= 1'b1; // Release SDA for Slave to transmit
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                    if (tick_cnt == 2'd2) rx_data[bit_cnt] <= sda_i; // Sample
                                    if (tick_cnt == 2'd3) begin
                                        scl_reg <= 1'b0;
                                        if (bit_cnt == 3'd0) begin
                                            bit_cnt <= 3'd7;
                                            state <= ACK_R;
                                        end else begin
                                            bit_cnt <= bit_cnt - 3'd1;
                                        end
                                    end
                                end

                                ACK_W: begin
                                    if (tick_cnt == 2'd0) sda_reg <= 1'b1; // Release SDA to wait for Slave ACK
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                    if (tick_cnt == 2'd2) ack_in <= sda_i; // Read response
                                    if (tick_cnt == 2'd3) begin
                                        scl_reg <= 1'b0;
                                        if (cmd_stop) state <= STOP;
                                        else state <= IDLE;
                                    end
                                end

                                ACK_R: begin
                                    if (tick_cnt == 2'd0) sda_reg <= ack_out; // Send ACK/NACK
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                    if (tick_cnt == 2'd3) begin
                                        scl_reg <= 1'b0;
                                        if (cmd_stop) state <= STOP;
                                        else state <= IDLE;
                                    end
                                end

                                STOP: begin
                                    // Generate STOP condition: SDA pulled high while SCL is high
                                    if (tick_cnt == 2'd0) sda_reg <= 1'b0;
                                    if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                    if (tick_cnt == 2'd2) sda_reg <= 1'b1;
                                    if (tick_cnt == 2'd3) state <= IDLE;
                                end
                            endcase
                        end
                    end
                end
            end

            // Open-Drain logic
            assign scl_o  = 1'b0; // When Low is needed, output logic 0
            assign scl_oe = ~scl_reg; // OE=1 when reg=0 (pull low), OE=0 when reg=1 (High-Z)
            
            assign sda_o  = 1'b0; 
            assign sda_oe = ~sda_reg;

            // Handle APB Read
            always @(*) begin
                if (!addr_ok) PRDATA = 32'd0;
                else case (widx)
                    10'd0:   PRDATA = {24'd0, rx_data};
                    10'd1:   PRDATA = {30'd0, ack_in, busy};
                    10'd2:   PRDATA = {16'd0, ctrl_div};
                    default: PRDATA = 32'd0;
                endcase
            end

        end else begin : gen_no_i2c
            assign PREADY  = 1'b1;
            assign PSLVERR = (PSEL & PENABLE);
            assign scl_o   = 1'b0;
            assign scl_oe  = 1'b0;
            assign sda_o   = 1'b0;
            assign sda_oe  = 1'b0;
            always @(*) PRDATA = 32'd0;
        end
    endgenerate

endmodule
