// pwm_apb.v - PWM APB3 slave (RTL-13)
module pwm_apb #(
    parameter ENABLE_PWM = 1
) (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [11:0] PADDR,
    input  wire [31:0] PWDATA,
    output wire [31:0] PRDATA, 
    output wire        PREADY,
    output wire        PSLVERR,
    output wire        pwm_out
);

    generate
        if (ENABLE_PWM) begin : gen_pwm
            reg [31:0] period;
            reg [31:0] duty;
            reg        enable;
            
            reg [31:0] counter;
            reg        pwm_reg;

            wire [9:0] widx    = PADDR[11:2];
            wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd2);
            wire       access  = PSEL & PENABLE;
            wire       wr_ok   = access & PWRITE & addr_ok;
            
            assign PREADY  = 1'b1;
            assign PSLVERR = access & ~addr_ok;

            // Handle APB register write
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    period <= 32'd0;
                    duty   <= 32'd0;
                    enable <= 1'b0;
                end else if (wr_ok) begin
                    case (widx)
                        10'd0: period <= PWDATA;
                        10'd1: duty   <= PWDATA;
                        10'd2: enable <= PWDATA[0];
                        default: ;
                    endcase
                end
            end

            // Handle counter and PWM generation
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    counter <= 32'd0;
                    pwm_reg <= 1'b0;
                end else if (enable && period > 32'd0) begin
                    if (counter >= period - 1) begin
                        counter <= 32'd0;
                    end else begin
                        counter <= counter + 1;
                    end
                    pwm_reg <= (counter < duty) ? 1'b1 : 1'b0;
                end else begin
                    counter <= 32'd0;
                    pwm_reg <= 1'b0;
                end
            end

            assign pwm_out = pwm_reg;

            // Handle APB register read using assign
            assign PRDATA = (!addr_ok) ? 32'd0 :
                            (widx == 10'd0) ? period :
                            (widx == 10'd1) ? duty :
                            (widx == 10'd2) ? {31'd0, enable} : 32'd0;

        end else begin : gen_no_pwm
            // Dummy logic when PWM configuration is disabled
            assign PREADY  = 1'b1;
            assign PSLVERR = (PSEL & PENABLE);
            assign pwm_out = 1'b0;
            assign PRDATA  = 32'd0; 
        end
    endgenerate

endmodule
