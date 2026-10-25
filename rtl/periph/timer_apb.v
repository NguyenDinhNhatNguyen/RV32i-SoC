// timer_apb.v - simplified CLINT-style timer, APB3 slave (RTL-04)
// Base: 0x2000_0000 (4 KB window). Word access only, other addresses -> PSLVERR.
//   0x00 MTIME_LO     RW  reset 0
//   0x04 MTIME_HI     RW  reset 0
//   0x08 MTIMECMP_LO  RW  reset 0xFFFFFFFF
//   0x0C MTIMECMP_HI  RW  reset 0xFFFFFFFF
//   0x10 MSIP         RW  bit0 -> irq_software, reset 0
// irq_timer = (mtime >= mtimecmp), level, registered by 1 flop (1 cycle late).
// Writing the 64-bit mtimecmp: write HI=0xFFFFFFFF, then LO, then HI to avoid a false interrupt.
// Reading the 64-bit mtime: read HI, LO, HI, then compare HI to catch a carry in between.
//
// Optimizations (no change in behavior visible to firmware):
//  - mtime is split into two 32-bit halves. The high half updates only on (write) or
//    (low half wrap): ~32 flops with an enable, so the tool infers clock gating, and the
//    64-bit adder becomes two 32-bit adders with a shorter path.
//  - Every register is written as "if (enable) reg <= ..." so clock gating covers it.
`timescale 1ns/1ps
module timer_apb (
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
    output reg         irq_timer,
    output wire        irq_software,
    output wire [63:0] mtime_o        // To the core mtime_i (CSR time, RTL-09)
);
    reg [31:0] mtime_lo;
    reg [31:0] mtime_hi;
    reg [31:0] mtimecmp_lo;
    reg [31:0] mtimecmp_hi;
    reg        msip;

    wire [9:0] widx    = PADDR[11:2];
    wire       addr_ok = (PADDR[1:0] == 2'b00) && (widx <= 10'd4);
    wire       access  = PSEL & PENABLE;
    wire       wr_ok   = access & PWRITE & addr_ok;

    wire wr_mtime_lo = wr_ok && (widx == 10'd0);
    wire wr_mtime_hi = wr_ok && (widx == 10'd1);
    wire wr_cmp_lo   = wr_ok && (widx == 10'd2);
    wire wr_cmp_hi   = wr_ok && (widx == 10'd3);
    wire wr_msip     = wr_ok && (widx == 10'd4);

    // The low half counts all the time. The high half increments only when the low half
    // wraps (and is not being written).
    wire lo_wrap = (&mtime_lo) & ~wr_mtime_lo;

    assign PREADY       = 1'b1;
    assign PSLVERR      = access & ~addr_ok;
    assign irq_software = msip;
    assign mtime_o      = {mtime_hi, mtime_lo};

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)         mtime_lo <= 32'd0;
        else if (wr_mtime_lo) mtime_lo <= PWDATA;
        else                  mtime_lo <= mtime_lo + 32'd1;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)         mtime_hi <= 32'd0;
        else if (wr_mtime_hi) mtime_hi <= PWDATA;
        else if (lo_wrap)     mtime_hi <= mtime_hi + 32'd1;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)        mtimecmp_lo <= 32'hFFFF_FFFF;
        else if (wr_cmp_lo)  mtimecmp_lo <= PWDATA;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)        mtimecmp_hi <= 32'hFFFF_FFFF;
        else if (wr_cmp_hi)  mtimecmp_hi <= PWDATA;
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)        msip <= 1'b0;
        else if (wr_msip)    msip <= PWDATA[0];
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) irq_timer <= 1'b0;
        else          irq_timer <= ({mtime_hi, mtime_lo} >= {mtimecmp_hi, mtimecmp_lo});
    end

    always @(*) begin
        case (widx)
            10'd0:   PRDATA = mtime_lo;
            10'd1:   PRDATA = mtime_hi;
            10'd2:   PRDATA = mtimecmp_lo;
            10'd3:   PRDATA = mtimecmp_hi;
            10'd4:   PRDATA = {31'd0, msip};
            default: PRDATA = 32'd0;
        endcase
    end
endmodule
