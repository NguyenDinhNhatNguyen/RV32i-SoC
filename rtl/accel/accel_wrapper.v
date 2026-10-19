`timescale 1ns/1ps
// accel_wrapper.v
// Wrapper MMIO cho accelerator nhân ma trận (systolic array Lab 2).
// Chủ: Nguyên. Vùng địa chỉ trong SoC: 0x3000_0000, 4 KB.
//
// Lý do có wrapper: CPU chỉ ghi được 4 byte mỗi lệnh store, trong khi mảng N x N cần N byte A + N byte B mỗi chu kỳ theo đúng thứ tự skew. Wrapper nhận ma trận vào bộ đệm trước, rồi tự phát chuỗi skew cho lõi trong 3N-2 chu kỳ liên tiếp.
//
// Bus: valid/ready theo spec chung của SoC. Wrapper luôn sẵn sàng (ready = valid), dữ liệu đọc hợp lệ trong chính chu kỳ ready.
//
// Bản đồ thanh ghi (offset trong vùng 4 KB):
//   0x000 CTRL    W: bit0 START (chỉ nhận khi rảnh), bit1 IRQ_EN.  R: bit1 IRQ_EN
//   0x004 STATUS  R: bit0 BUSY, bit1 DONE.  W: ghi 1 vào bit1 để xoá DONE
//   0x008 INFO    R: {N, DW, AW, LAT} mỗi trường 8 bit, từ bit cao xuống
//   0x100 A_BUF   A[i][k] ở byte i*N+k (little-endian trong word), N*N byte
//   0x200 B_BUF   B[k][j] ở byte k*N+j
//   0x300 C_BUF   C[i][j] ở word i*N+j (chỉ đọc)
// Ghi vào A/B/CTRL khi đang BUSY bị bỏ qua.
// irq = DONE & IRQ_EN, nối vào bộ gom ngắt của SoC.
//
// Giới hạn tham số: DW = 8, AW <= 32 (Lab 2: tích luỹ 20 bit), N <= 8.
// C_BUF trả về giá trị tích luỹ mở rộng dấu lên 32 bit.

module accel_wrapper #(
    parameter N      = 4,
    parameter DW     = 8,
    parameter AW     = 20,
    parameter SIGNED = 1,
    parameter LAT    = 3*N - 2      // số chu kỳ en=1 cần cho lõi và chỉnh theo lõi Lab 2
) (
    input  wire        clk,
    input  wire        rst_n,
    // bus slave
    input  wire        s_valid,
    input  wire        s_we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [11:0] s_addr,           // bit [1:0] bỏ qua: chỉ truy cập theo word
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output wire        s_ready,
    output reg  [31:0] s_rdata,
    // ngắt
    output wire        irq
);

    localparam NB = N*N;                 // số byte mỗi ma trận
    localparam CW = 6;                   // đủ đếm tới LAT-1 với N <= 8

    localparam [1:0] S_IDLE = 2'd0,
                     S_CLR  = 2'd1,
                     S_RUN  = 2'd2;

    // Trạng thái
    reg  [1:0]    state;
    reg  [CW-1:0] cnt;
    reg           done;
    reg           irq_en;
    wire          busy = (state != S_IDLE);

    reg  [NB*DW-1:0] abuf;
    reg  [NB*DW-1:0] bbuf;

    // Giải mã bus
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

    // Bộ đệm A/B
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
    // Chu kỳ t = cnt: hàng i nhận A[i][t-i], cột j nhận B[t-j][j] (0 nếu ngoài khoảng)
    reg [N*DW-1:0] a_feed;
    reg [N*DW-1:0] b_feed;
    integer i;
    integer t;                           // cnt mở rộng lên 32 bit cho phép so sánh/cộng với i
    always @* begin
        t = {{(32-CW){1'b0}}, cnt};
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

    // Lõi
    wire [NB*AW-1:0] c_out;

    sa_core_model #(
        .N(N), .DW(DW), .AW(AW), .SIGNED(SIGNED)
    ) u_core (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (state == S_RUN),     // Ngoài lúc chạy, mảng giữ nguyên: clock gating
        .clr   (state == S_CLR),
        .a_in  (a_feed),
        .b_in  (b_feed),
        .c_out (c_out)
    );

    // Đọc bus
    integer r;
    always @* begin
        s_rdata = 32'd0;
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
                s_rdata = SIGNED ? {{(32-AW){c_out[widx*AW + AW-1]}}, c_out[widx*AW +: AW]}
                                 : {{(32-AW){1'b0}}, c_out[widx*AW +: AW]};
        end
    end

endmodule
