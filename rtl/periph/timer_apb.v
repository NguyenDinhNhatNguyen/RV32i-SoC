// timer_apb.v - Timer kieu CLINT rut gon, APB3 slave (RTL-04)
// Base: 0x2000_0000 (cua so 4 KB). Chi truy cap word, dia chi khac -> PSLVERR.
//   0x00 MTIME_LO     RW  reset 0
//   0x04 MTIME_HI     RW  reset 0
//   0x08 MTIMECMP_LO  RW  reset 0xFFFFFFFF
//   0x0C MTIMECMP_HI  RW  reset 0xFFFFFFFF
//   0x10 MSIP         RW  bit0 -> irq_software, reset 0
// irq_timer = (mtime >= mtimecmp), muc, da dang ky 1 flop (tre 1 chu ky).
// Ghi mtimecmp 64 bit: ghi HI=0xFFFFFFFF, roi LO, roi HI de tranh ngat gia.
// Doc mtime 64 bit: doc HI, LO, HI roi so sanh HI de tranh carry chen giua.
//
// Toi uu (khong doi chuc nang quan sat duoc tu firmware):
//  - mtime tach 2 nua 32 bit. Nua cao chi cap nhat khi (ghi) hoac (nua thap tran):
//    ~32 flop co enable -> cong cu clock gating tu suy ra; bo cong 64 bit thanh 2 bo 32 bit,
//    duong tinh toan ngan hon.
//  - Moi thanh ghi chi ghi viet theo dang "if (enable) reg <= ..." de clock gating phu duoc.
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
    output wire [63:0] mtime_o        // cho mtime_i cua core (CSR time, RTL-09)
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

    // nua thap dem lien tuc; nua cao chi tang khi nua thap tran (khong bi ghi de)
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
