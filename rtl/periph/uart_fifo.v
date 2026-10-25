// uart_fifo.v - small synchronous FIFO for the UART (RTL-10)
// Depth = 2**AW. Pointers are AW+1 bits (the top bit tells full from empty).
// The storage has no reset (read only when not empty) -> smaller flops, no functional effect.
// A push when full and a pop when empty are ignored, the caller reports its own error flag.
`timescale 1ns/1ps
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
