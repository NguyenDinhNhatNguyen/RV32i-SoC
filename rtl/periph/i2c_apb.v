// i2c_apb.v - I2C Master APB3 slave (RTL-14)
`timescale 1ns/1ps

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
    output wire [31:0] PRDATA, // Wire for assign
    output wire        PREADY,
    output wire        PSLVERR,
    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_oe,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_oe
);

    // FSM states. Declared outside generate, because Genus reads Verilog-2001 and rejects a
    // localparam inside a generate block (VLOGPT-9)
    localparam [2:0] IDLE  = 3'd0,
                     START = 3'd1,
                     WRITE = 3'd2,
                     READ  = 3'd3,
                     ACK_W = 3'd4,
                     ACK_R = 3'd5,
                     STOP  = 3'd6;

    generate
        if (ENABLE_I2C) begin : gen_i2c
            reg [7:0]  tx_data, rx_data;
            reg [15:0] ctrl_div;
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
                    if (wr_ok && wr_cmd) begin
                        cmd_start <= PWDATA[0];
                        cmd_stop  <= PWDATA[1];
                        cmd_read  <= PWDATA[2];
                        cmd_write <= PWDATA[3];
                        ack_out   <= PWDATA[4];
                    end else if (busy) begin
                        cmd_start <= 1'b0;
                        cmd_stop  <= 1'b0;
                        cmd_read  <= 1'b0;
                        cmd_write <= 1'b0;
                    end else if (wr_ok) begin
                        if (wr_data) tx_data <= PWDATA[7:0];
                        if (wr_ctrl) ctrl_div <= PWDATA[15:0];
                    end
                end
            end

            reg [2:0]  state;          // 7 states fit in 3 bits
            reg [15:0] clk_cnt;
            reg [1:0]  tick_cnt; 
            reg [2:0]  bit_cnt;
            reg        scl_reg, sda_reg;
            reg        op_write, op_read, op_stop;

            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    state    <= IDLE;
                    clk_cnt  <= 16'd0;
                    tick_cnt <= 2'd0;
                    bit_cnt  <= 3'd7;
                    busy     <= 1'b0;
                    ack_in   <= 1'b1; 
                    rx_data  <= 8'd0;
                    scl_reg  <= 1'b1;
                    sda_reg  <= 1'b1;
                    op_write <= 1'b0;
                    op_read  <= 1'b0;
                    op_stop  <= 1'b0;
                end else begin
                    if (state == IDLE && !cmd_start && !cmd_stop && !cmd_read && !cmd_write) begin
                        busy     <= 1'b0;
                        clk_cnt  <= 16'd0;
                        tick_cnt <= 2'd0; 
                        bit_cnt  <= 3'd7; 
                    end else begin
                        busy <= 1'b1;
                        
                        if (state == IDLE) begin
                            op_write <= cmd_write;
                            op_read  <= cmd_read;
                            op_stop  <= cmd_stop;

                            clk_cnt  <= 16'd0; // Trigger exactly on next PCLK
                            tick_cnt <= 2'd0;  // Reset phase perfectly
                            bit_cnt  <= 3'd7;

                            if (cmd_start) state <= START;
                            else if (cmd_write) state <= WRITE;
                            else if (cmd_read) state <= READ;
                            else if (cmd_stop) state <= STOP;
                        end else begin
                            if (clk_cnt != 16'd0) begin
                                clk_cnt <= clk_cnt - 16'd1;
                            end else begin
                                clk_cnt <= ctrl_div;
                                tick_cnt <= tick_cnt + 2'd1;
                                
                                case (state)
                                    // Release SDA, raise SCL, then pull SDA low while SCL is
                                    // high. Works from an idle bus and as a repeated START
                                    // after an ACK (SCL low).
                                    START: begin
                                        if (tick_cnt == 2'd0) sda_reg <= 1'b1;
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd2) sda_reg <= 1'b0;
                                        if (tick_cnt == 2'd3) begin
                                            scl_reg <= 1'b0;
                                            if (op_write) state <= WRITE;
                                            else if (op_read) state <= READ;
                                            else state <= IDLE;
                                        end
                                    end

                                    WRITE: begin
                                        if (tick_cnt == 2'd0) sda_reg <= tx_data[bit_cnt];
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd3) begin
                                            scl_reg <= 1'b0;
                                            if (bit_cnt == 3'd0) begin
                                                state <= ACK_W;
                                                bit_cnt <= 3'd7;
                                            end else begin
                                                bit_cnt <= bit_cnt - 3'd1;
                                            end
                                        end
                                    end

                                    READ: begin
                                        if (tick_cnt == 2'd0) sda_reg <= 1'b1; 
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd2) rx_data[bit_cnt] <= sda_i; 
                                        if (tick_cnt == 2'd3) begin
                                            scl_reg <= 1'b0;
                                            if (bit_cnt == 3'd0) begin
                                                state <= ACK_R;
                                                bit_cnt <= 3'd7;
                                            end else begin
                                                bit_cnt <= bit_cnt - 3'd1;
                                            end
                                        end
                                    end

                                    ACK_W: begin
                                        if (tick_cnt == 2'd0) sda_reg <= 1'b1; 
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd2) ack_in <= sda_i; 
                                        if (tick_cnt == 2'd3) begin
                                            scl_reg <= 1'b0;
                                            if (op_stop) state <= STOP;
                                            else state <= IDLE;
                                        end
                                    end

                                    ACK_R: begin
                                        if (tick_cnt == 2'd0) sda_reg <= ack_out; 
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd3) begin
                                            scl_reg <= 1'b0;
                                            if (op_stop) state <= STOP;
                                            else state <= IDLE;
                                        end
                                    end

                                    STOP: begin
                                        if (tick_cnt == 2'd0) sda_reg <= 1'b0;
                                        if (tick_cnt == 2'd1) scl_reg <= 1'b1;
                                        if (tick_cnt == 2'd2) sda_reg <= 1'b1;
                                        if (tick_cnt == 2'd3) state <= IDLE;
                                    end

                                    default: state <= IDLE;
                                endcase
                            end
                        end
                    end
                end
            end

            // No clock stretching: scl_i is not read. CTRL uses PWDATA[15:0] only.
            wire unused_ok = &{1'b0, PWDATA[31:16], scl_i};

            assign scl_o  = 1'b0; 
            assign scl_oe = ~scl_reg; 
            assign sda_o  = 1'b0; 
            assign sda_oe = ~sda_reg;

            assign PRDATA = (!addr_ok) ? 32'd0 :
                            (widx == 10'd0) ? {24'd0, rx_data} :
                            (widx == 10'd1) ? {30'd0, ack_in, busy} :
                            (widx == 10'd2) ? {16'd0, ctrl_div} : 32'd0;

        end else begin : gen_no_i2c
            assign PREADY  = 1'b1;
            assign PSLVERR = (PSEL & PENABLE);
            assign scl_o   = 1'b0;
            assign scl_oe  = 1'b0;
            assign sda_o   = 1'b0;
            assign sda_oe  = 1'b0;
            assign PRDATA  = 32'd0;
        end
    endgenerate

endmodule
