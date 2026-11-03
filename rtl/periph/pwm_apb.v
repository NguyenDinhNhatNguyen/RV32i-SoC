// pwm_apb.v - PWM APB3 slave (RTL-13)
//   0x00 PERIOD  RW  Chu kỳ PWM (tính bằng số xung nhịp)
//   0x04 DUTY    RW  Thời gian mức cao (phải nhỏ hơn PERIOD)
//   0x08 CTRL    RW  Bit 0: 1 = Enable phát PWM, 0 = Tạm dừng
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
    output reg  [31:0] PRDATA,
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

            // Xử lý ghi thanh ghi APB
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
                    endcase
                end
            end

            // Xử lý bộ đếm và phát xung PWM
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
                    // Nếu duty = 0, chân pwm_reg sẽ luôn ở mức thấp
                    pwm_reg <= (counter < duty) ? 1'b1 : 1'b0;
                end else begin
                    counter <= 32'd0;
                    pwm_reg <= 1'b0;
                end
            end

            assign pwm_out = pwm_reg;

            // Xử lý đọc thanh ghi APB
            always @(*) begin
                if (!addr_ok) PRDATA = 32'd0;
                else case (widx)
                    10'd0:   PRDATA = period;
                    10'd1:   PRDATA = duty;
                    10'd2:   PRDATA = {31'd0, enable};
                    default: PRDATA = 32'd0;
                endcase
            end

        end else begin : gen_no_pwm
            // Dummy logic khi PWM bị disable cấu hình
            assign PREADY  = 1'b1;
            assign PSLVERR = (PSEL & PENABLE); // Báo lỗi nếu CPU cố truy cập
            assign pwm_out = 1'b0;
            always @(PSEL or PENABLE or PADDR) PRDATA = 32'd0;
        end
    endgenerate

endmodule
