// irqc_apb.v - Reduced interrupt controller (IRQC), APB3 slave (RTL-11)
// Base: 0x2000_6000 (4 KB window). Word access only, other addresses -> PSLVERR.
//   0x00 PENDING  RO  Bit i = current level of irq_src[i], a write -> PSLVERR
//   0x04 ENABLE   RW  Bit i = 1 lets source i raise irq, reset 0
// irq (level, registered by 1 flop) = |(PENDING & ENABLE), wired to irq_external_i of the core.
// Sources are level interrupts, so PENDING follows them directly and has no write-1-to-clear
// (docs/spec/soc_spec.md section 5). Software clears an interrupt at the peripheral itself.
// Bit map in soc_top (docs/spec/periph.md section 4): 0 UART, 1 accelerator, 2 GPIO, 3 SPI,
// 4 DMA. N <= 31.
`timescale 1ns/1ps
module irqc_apb #(
    parameter N = 5                         // Number of interrupt sources
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
    input  wire [N-1:0] irq_src,
    output reg          irq
);
    reg [N-1:0] enable;

    wire [9:0] widx    = PADDR[11:2];
    wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd1);
    wire       access  = PSEL & PENABLE;
    wire       ro_wr   = access & PWRITE & (widx == 10'd0);
    wire       wr_en   = access & PWRITE & addr_ok & (widx == 10'd1);

    assign PREADY  = 1'b1;
    assign PSLVERR = access & (~addr_ok | ro_wr);

    wire unused_ok = &{1'b0, PWDATA[31:N]};

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)   enable <= {N{1'b0}};
        else if (wr_en) enable <= PWDATA[N-1:0];
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) irq <= 1'b0;
        else          irq <= |(irq_src & enable);
    end

    always @(*) begin
        case (widx)
            10'd0:   PRDATA = {{(32-N){1'b0}}, irq_src};
            10'd1:   PRDATA = {{(32-N){1'b0}}, enable};
            default: PRDATA = 32'd0;
        endcase
    end
endmodule
