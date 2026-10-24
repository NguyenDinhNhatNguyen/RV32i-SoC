// uart_fifo.v - FIFO dong bo nho cho UART (RTL-10)
// Do sau = 2**AW. Con tro AW+1 bit (bit cao phan biet day/rong).
// Bo nho khong reset (chi doc khi khong rong) -> flop nho hon, khong anh huong chuc nang.
// push khi day va pop khi rong deu bi bo qua; ben ngoai tu bao co loi.
module uart_fifo #(
    parameter DW = 8,
    parameter AW = 3
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          push,
    input  wire [DW-1:0] din,
    input  wire          pop,
    output wire [DW-1:0] dout,
    output wire          full,
    output wire          empty
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    reg [AW:0]   wptr;
    reg [AW:0]   rptr;

    assign empty = (wptr == rptr);
    assign full  = (wptr[AW] != rptr[AW]) && (wptr[AW-1:0] == rptr[AW-1:0]);

    wire do_push = push & ~full;
    wire do_pop  = pop  & ~empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= {(AW+1){1'b0}};
            rptr <= {(AW+1){1'b0}};
        end else begin
            if (do_push) wptr <= wptr + {{AW{1'b0}}, 1'b1};
            if (do_pop)  rptr <= rptr + {{AW{1'b0}}, 1'b1};
        end
    end

    always @(posedge clk) begin
        if (do_push) mem[wptr[AW-1:0]] <= din;
    end

    assign dout = mem[rptr[AW-1:0]];
endmodule
