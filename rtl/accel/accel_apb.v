`timescale 1ns/1ps
// accel_apb.v
// Bridge from an APB3 slave to the valid/ready interface of accel_wrapper.
// Used when SoC peripherals sit behind an APB3 bridge (as proposed in the plan doc).
// APB3 is word access only, so every write uses all 4 bytes.
// PSLVERR = 1 for an undefined address inside the accelerator's 4 KB (offset >= 0x400,
// registers 0x00C-0x0FC) or a write to C_BUF, so the core traps with an access fault
// instead of reading 0.

module accel_apb #(
    parameter N      = 4,
    parameter DW     = 8,
    parameter AW     = 20,
    parameter SIGNED = 1
) (
    input  wire        pclk,
    input  wire        presetn,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [11:0] paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    output wire        irq
);

    wire [3:0] region = paddr[11:8];
    wire [5:0] widx   = paddr[7:2];
    wire       bad    = (region > 4'h3) ||
                        (region == 4'h0 && widx > 6'd2) ||
                        (region == 4'h3 && pwrite);

    // Pass only valid transfers in the access phase down to the wrapper
    wire access = psel & penable;
    wire unused_s_ready;                 // APB returns PREADY = 1, so s_ready is not needed

    accel_wrapper #(.N(N), .DW(DW), .AW(AW), .SIGNED(SIGNED)) u_wrap (
        .clk     (pclk),
        .rst_n   (presetn),
        .s_valid (access & ~bad),
        .s_we    (pwrite),
        .s_addr  (paddr),
        .s_wdata (pwdata),
        .s_wstrb (4'hF),
        .s_ready (unused_s_ready),
        .s_rdata (prdata),
        .irq     (irq)
    );

    assign pready  = 1'b1;              // The wrapper always answers in one cycle
    assign pslverr = access & bad;

endmodule
