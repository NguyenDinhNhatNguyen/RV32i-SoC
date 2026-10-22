`timescale 1ns/1ps
`default_nettype none
// rv32_muldiv - khối RV32M ở tầng EX (docs/spec/core.md mục 4.9).
//
//   MUL, MULH, MULHSU, MULHU: 2 chu kỳ (EX dừng 1 chu kỳ). Chu kỳ đầu nhân toán hạng 33 bit
//     (đã mở rộng dấu theo phép) với hai nửa 17 bit của toán hạng kia, chốt
//     hai tích riêng vào thanh ghi. Chu kỳ sau cộng hai tích riêng ra tích
//     64 bit. Mỗi chu kỳ chỉ có một nửa bộ nhân nên không cần multicycle
//     path trong SDC.
//   DIV, DIVU, REM, REMU: chia kiểu restoring (thử trừ, âm thì giữ số dư cũ),
//     1 bit mỗi chu kỳ trên giá trị tuyệt đối, sửa dấu ở chu kỳ cuối. Lệnh
//     nằm ở EX 34 chu kỳ (nạp, 32 bước, ra kết quả), tức EX dừng 33 chu kỳ.
//   Chia cho 0 và tràn -2^31 / -1 cho đúng kết quả của đặc tả mà không cần
//   nhánh riêng: thương không dấu toàn bit 1 và không đổi dấu khi số chia
//   bằng 0, |-2^31| / 1 = 2^31 đổi dấu vẫn là -2^31.
//
// Giao tiếp với EX: req_i = 1 suốt thời gian lệnh M nằm ở EX (bằng 0 khi lệnh
// bị huỷ hoặc nhận trap, khối quay về rảnh). Phép bắt đầu ở chu kỳ có
// req_i = 1 và hold_i = 0 (toán hạng đã đúng). done_o = 1 khi result_o
// đúng, khối rảnh lại sau chu kỳ done_o && go_i.
`include "rv32_defs.vh"

module rv32_muldiv (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_i,
    input  wire        hold_i,     // chưa được bắt đầu (toán hạng forward chưa có)
    input  wire        go_i,       // EX chuyển lệnh sang WB trong chu kỳ này
    input  wire [2:0]  op_i,       // funct3, RV_F3_MUL ... RV_F3_REMU
    input  wire [31:0] a_i,        // rs1
    input  wire [31:0] b_i,        // rs2
    output wire        done_o,
    output wire [31:0] result_o
);

    wire is_div   = op_i[2];
    // MULH, MULHSU: rs1 có dấu. MULH: rs2 có dấu. DIV, REM: cả hai có dấu.
    wire a_signed = is_div ? ~op_i[0] : (op_i[1:0] == 2'b01) | (op_i[1:0] == 2'b10);
    wire b_signed = is_div ? ~op_i[0] : (op_i[1:0] == 2'b01);

    // ---- Trạng thái ---------------------------------------------------------------
    reg        busy_q;
    reg        div_q;          // phép đang chạy là chia
    reg        hi_q;           // MUL: lấy nửa cao. DIV: lấy số dư
    reg [5:0]  cnt_q;          // số bước chia còn lại

    wire start = req_i & ~busy_q & ~hold_i;
    assign done_o = busy_q & (~div_q | (cnt_q == 6'd0));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            div_q  <= 1'b0;
            hi_q   <= 1'b0;
            cnt_q  <= 6'd0;
        end else if (!req_i) begin
            busy_q <= 1'b0;                   // lệnh bị huỷ hoặc nhận trap
        end else if (start) begin
            busy_q <= 1'b1;
            div_q  <= is_div;
            // MULH/MULHSU/MULHU lấy nửa cao, REM/REMU lấy số dư (op_i[1] = 1)
            hi_q   <= is_div ? op_i[1] : (op_i[1:0] != 2'b00);
            cnt_q  <= 6'd32;
        end else if (done_o & go_i) begin
            busy_q <= 1'b0;
        end else if (busy_q & div_q & (cnt_q != 6'd0)) begin
            cnt_q  <= cnt_q - 6'd1;
        end
    end

    // ---- Nhân: hai tích riêng 33 x 17 bit ---------------------------------------------
    // A, B là toán hạng 33 bit có dấu. Tích = A * B[15:0] + (A * B[32:16]) << 16.
    // Chỉ cần 64 bit thấp của tích nên tích riêng cao giữ 48 bit.
    wire [32:0] ma = {a_signed & a_i[31], a_i};
    wire [32:0] mb = {b_signed & b_i[31], b_i};

    wire [48:0] p_lo = $signed({{16{ma[32]}}, ma}) * $signed({33'h0, mb[15:0]});
    wire [47:0] p_hi = $signed({{15{ma[32]}}, ma}) * $signed({{31{mb[32]}}, mb[32:16]});

    reg  [48:0] p_lo_q;
    reg  [47:0] p_hi_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_lo_q <= 49'h0;
            p_hi_q <= 48'h0;
        end else if (start & ~is_div) begin
            p_lo_q <= p_lo;
            p_hi_q <= p_hi;
        end
    end

    wire [63:0] prod = {{15{p_lo_q[48]}}, p_lo_q} + {p_hi_q, 16'h0};

    // ---- Chia ---------------------------------------------------------------------------
    reg  [31:0] rem_q;         // số dư từng phần
    reg  [31:0] quo_q;         // số bị chia dịch dần ra, thương dịch dần vào
    reg  [31:0] dvs_q;         // |số chia|
    reg         neg_q_q;       // đổi dấu thương
    reg         neg_r_q;       // đổi dấu số dư

    wire [31:0] a_abs = (a_signed & a_i[31]) ? (32'h0 - a_i) : a_i;
    wire [31:0] b_abs = (b_signed & b_i[31]) ? (32'h0 - b_i) : b_i;

    // Một bước: dịch {rem, quo} sang trái 1 bit rồi thử trừ số chia
    wire [32:0] rem_sh = {rem_q, quo_q[31]};
    wire [32:0] trial  = rem_sh - {1'b0, dvs_q};
    wire        fits   = ~trial[32];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rem_q   <= 32'h0;
            quo_q   <= 32'h0;
            dvs_q   <= 32'h0;
            neg_q_q <= 1'b0;
            neg_r_q <= 1'b0;
        end else if (start & is_div) begin
            rem_q   <= 32'h0;
            quo_q   <= a_abs;
            dvs_q   <= b_abs;
            // Chia cho 0: thương giữ toàn bit 1, không đổi dấu
            neg_q_q <= a_signed & (a_i[31] ^ b_i[31]) & (b_i != 32'h0);
            neg_r_q <= a_signed & a_i[31];
        end else if (busy_q & div_q & (cnt_q != 6'd0)) begin
            rem_q   <= fits ? trial[31:0] : rem_sh[31:0];
            quo_q   <= {quo_q[30:0], fits};
        end
    end

    wire [31:0] quo_res = neg_q_q ? (32'h0 - quo_q) : quo_q;
    wire [31:0] rem_res = neg_r_q ? (32'h0 - rem_q) : rem_q;

    assign result_o = div_q ? (hi_q ? rem_res : quo_res) :
                              (hi_q ? prod[63:32] : prod[31:0]);

endmodule

`default_nettype wire
