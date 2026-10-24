// gpio_apb.v - GPIO APB3 slave (RTL-04), W <= 32
// Base: 0x2000_2000 (cua so 4 KB). Chi truy cap word, dia chi khac -> PSLVERR.
//   0x00 DATA_OUT  RW  gia tri xuat ra chan, reset 0
//   0x04 DATA_IN   RO  gia tri chan (qua dong bo 2 flop); ghi -> PSLVERR
//   0x08 DIR       RW  1 = output, 0 = input, reset 0
// Khong dung tri-state ben trong: gpio_o / gpio_oe / gpio_i tach rieng, noi pad o top.
`timescale 1ns/1ps
module gpio_apb #(
    parameter W = 32
) (
    input  wire         PCLK,
    input  wire         PRESETn,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [11:0]  PADDR,
    input  wire [31:0]  PWDATA,
    output reg  [31:0]  PRDATA,
    output wire         PREADY,
    output wire         PSLVERR,
    input  wire [W-1:0] gpio_i,
    output wire [W-1:0] gpio_o,
    output wire [W-1:0] gpio_oe
);
    reg [W-1:0] data_out;
    reg [W-1:0] dir;
    reg [W-1:0] in_s1;
    reg [W-1:0] in_s2;

    wire [31:0] data_out_ext = data_out;
    wire [31:0] dir_ext      = dir;
    wire [31:0] data_in_ext  = in_s2;

    wire [9:0] widx    = PADDR[11:2];
    wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd2);
    wire       access  = PSEL & PENABLE;
    wire       ro_wr   = access & PWRITE & (widx == 10'd1);
    wire       wr_ok   = access & PWRITE & addr_ok & ~ro_wr;

    assign PREADY  = 1'b1;
    assign PSLVERR = access & (~addr_ok | ro_wr);

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            data_out <= {W{1'b0}};
            dir      <= {W{1'b0}};
            in_s1    <= {W{1'b0}};
            in_s2    <= {W{1'b0}};
        end else begin
            in_s1 <= gpio_i;
            in_s2 <= in_s1;
            if (wr_ok && widx == 10'd0) data_out <= PWDATA[W-1:0];
            if (wr_ok && widx == 10'd2) dir      <= PWDATA[W-1:0];
        end
    end

    assign gpio_o  = data_out;
    assign gpio_oe = dir;

    always @(*) begin
        case (widx)
            10'd0:   PRDATA = data_out_ext;
            10'd1:   PRDATA = data_in_ext;
            10'd2:   PRDATA = dir_ext;
            default: PRDATA = 32'd0;
        endcase
    end
endmodule
