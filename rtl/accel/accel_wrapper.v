`timescale 1ns/1ps
// accel_wrapper.v
// MMIO wrapper for the matrix multiply accelerator (Lab 2 systolic array).
// Owner: Nguyen. SoC address region: 0x3000_0000, 4 KB.
//
// Why a wrapper: the CPU writes only 4 bytes per store, while an N x N array needs
// N bytes of A and N bytes of B every cycle in skewed order. The wrapper first loads
// both matrices into buffers, then drives the skewed sequence into the core for
// 3N-2 consecutive cycles.
//
// Bus: valid/ready as in the common SoC spec. The wrapper is always ready
// (ready = valid) and read data is valid in the same ready cycle.
//
// Register map (offset inside the 4 KB region):
//   0x000 CTRL    W: bit0 START (taken only when idle), bit1 IRQ_EN.  R: bit1 IRQ_EN
//   0x004 STATUS  R: bit0 BUSY, bit1 DONE.  W: write 1 to bit1 to clear DONE
//   0x008 INFO    R: {N, DW, AW, LAT}, 8 bits each, from the MSB down
//   0x100 A_BUF   A[i][k] at byte i*N+k (little-endian within a word), N*N bytes
//   0x200 B_BUF   B[k][j] at byte k*N+j
//   0x300 C_BUF   C[i][j] at word i*N+j (read only)
// Writes to A, B or CTRL while BUSY are ignored.
// The irq output is DONE & IRQ_EN and goes to the SoC interrupt controller.
//
// Parameter limits: the Lab 2 core (accelerator_top) is fixed at N = 4, DW = 8, AW = 20,
// signed. Keep the default parameters.
// C_BUF returns the accumulated value sign-extended to 32 bits.

module accel_wrapper #(
    parameter N      = 4,
    parameter DW     = 8,
    parameter AW     = 20,
    parameter SIGNED = 1,
    parameter LAT    = 3*N - 2      // 10 cycles, matches step_cnt == 10 in accelerator_top
) (
    input  wire        clk,
    input  wire        rst_n,
    // bus slave
    input  wire        s_valid,
    input  wire        s_we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [11:0] s_addr,           // Bits [1:0] are ignored, word access only
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output wire        s_ready,
    output reg  [31:0] s_rdata,
    // Interrupt
    output wire        irq
);

    localparam NB = N*N;                 // Bytes per matrix
    localparam CW = 6;                   // Enough to count to LAT-1 for N <= 8

    localparam [1:0] S_IDLE = 2'd0,
                     S_CLR  = 2'd1,
                     S_RUN  = 2'd2;

    // State
    reg  [1:0]    state;
    reg  [CW-1:0] cnt;
    reg           done;
    reg           irq_en;
    wire          busy = (state != S_IDLE);

    reg  [NB*DW-1:0] abuf;
    reg  [NB*DW-1:0] bbuf;

    // Bus decode
    wire        acc_w   = s_valid & s_we;
    wire [3:0]  region  = s_addr[11:8];
    wire [5:0]  widx    = s_addr[7:2];
    wire        sel_reg = (region == 4'h0);
    wire        sel_a   = (region == 4'h1);
    wire        sel_b   = (region == 4'h2);
    wire        sel_c   = (region == 4'h3);

    wire wr_ctrl   = acc_w & sel_reg & (widx == 6'd0) & s_wstrb[0];
    wire wr_status = acc_w & sel_reg & (widx == 6'd1) & s_wstrb[0];
    wire start     = wr_ctrl & s_wdata[0] & ~busy;

    assign s_ready = s_valid;

    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cnt   <= {CW{1'b0}};
        end else begin
            case (state)
                S_IDLE: if (start) state <= S_CLR;
                S_CLR:  begin
                            state <= S_RUN;
                            cnt   <= {CW{1'b0}};
                        end
                S_RUN:  if (cnt == LAT-1) state <= S_IDLE;
                        else              cnt   <= cnt + 1'b1;
                default: state <= S_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done   <= 1'b0;
            irq_en <= 1'b0;
        end else begin
            if (wr_ctrl & ~busy)
                irq_en <= s_wdata[1];
            if (state == S_RUN && cnt == LAT-1)
                done <= 1'b1;
            else if (start || (wr_status && s_wdata[1]))
                done <= 1'b0;
        end
    end

    assign irq = done & irq_en;

    // A/B buffers
    integer b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            abuf <= {NB*DW{1'b0}};
            bbuf <= {NB*DW{1'b0}};
        end else if (acc_w && !busy) begin
            for (b = 0; b < 4; b = b + 1) begin
                if (s_wstrb[b] && (widx*4 + b) < NB) begin
                    if (sel_a) abuf[(widx*4 + b)*DW +: DW] <= s_wdata[b*8 +: 8];
                    if (sel_b) bbuf[(widx*4 + b)*DW +: DW] <= s_wdata[b*8 +: 8];
                end
            end
        end
    end

    // Sinh skew
    // Cycle t = cnt: row i gets A[i][t-i], column j gets B[t-j][j] (0 when out of range)
    reg [N*DW-1:0] a_feed;
    reg [N*DW-1:0] b_feed;
    integer i;
    integer t;                           // Holds cnt widened to 32 bits to compare and add with i
    always @* begin
        t = {{(32-CW){1'b0}}, cnt};
        i = 0;                           // Default avoids a Yosys latch on the loop variable
        a_feed = {N*DW{1'b0}};
        b_feed = {N*DW{1'b0}};
        if (state == S_RUN) begin
            for (i = 0; i < N; i = i + 1) begin
                if ((t >= i) && (t < i + N)) begin
                    a_feed[i*DW +: DW] = abuf[(i*N + t - i)*DW +: DW];
                    b_feed[i*DW +: DW] = bbuf[((t - i)*N + i)*DW +: DW];
                end
            end
        end
    end

    // Lab 2 core (accelerator_top + pe)
    // Both start and clear pulse in the CLR cycle. The clear pulse empties the array, and the
    // core's busy rises exactly on the first RUN cycle and lasts LAT cycles, while the wrapper
    // drives the skewed sequence.
    // The core outputs one result row at a time, selected by the one-hot row_sel taken from
    // the C_BUF address (row = widx[3:2]).
    wire [3:0]    row_sel = 4'b0001 << widx[3:2];
    wire [AW-1:0] res0, res1, res2, res3;
    /* verilator lint_off UNUSEDSIGNAL */
    wire          core_busy, core_done;   // Not needed, the wrapper counts LAT cycles itself
    /* verilator lint_on UNUSEDSIGNAL */

    accelerator_top u_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (state == S_CLR),
        .clear    (state == S_CLR),
        .row_sel  (row_sel),
        .a_row0   (a_feed[0*DW +: DW]),
        .a_row1   (a_feed[1*DW +: DW]),
        .a_row2   (a_feed[2*DW +: DW]),
        .a_row3   (a_feed[3*DW +: DW]),
        .b_col0   (b_feed[0*DW +: DW]),
        .b_col1   (b_feed[1*DW +: DW]),
        .b_col2   (b_feed[2*DW +: DW]),
        .b_col3   (b_feed[3*DW +: DW]),
        .res_out0 (res0),
        .res_out1 (res1),
        .res_out2 (res2),
        .res_out3 (res3),
        .busy     (core_busy),
        .done     (core_done)
    );

    wire [4*AW-1:0] c_row = {res3, res2, res1, res0};
    wire [AW-1:0]   c_sel = c_row[widx[1:0]*AW +: AW];

    // Bus read
    integer r;
    always @* begin
        s_rdata = 32'd0;
        r       = 0;        // Default avoids a Yosys latch on the loop variable
        if (sel_reg) begin
            case (widx)
                6'd0: s_rdata = {30'd0, irq_en, 1'b0};
                6'd1: s_rdata = {30'd0, done, busy};
                6'd2: s_rdata = {N[7:0], DW[7:0], AW[7:0], LAT[7:0]};
                default: s_rdata = 32'd0;
            endcase
        end else if (sel_a || sel_b) begin
            for (r = 0; r < 4; r = r + 1)
                if ((widx*4 + r) < NB)
                    s_rdata[r*8 +: 8] = sel_a ? abuf[(widx*4 + r)*DW +: DW]
                                              : bbuf[(widx*4 + r)*DW +: DW];
        end else if (sel_c) begin
            if (widx < NB)
                s_rdata = SIGNED ? {{(32-AW){c_sel[AW-1]}}, c_sel}
                                 : {{(32-AW){1'b0}}, c_sel};
        end
    end

endmodule
