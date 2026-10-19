`timescale 1ns/1ps
// sa_core_model.v
// Mô hình thay thế cho lõi systolic array của Lab 2, chỉ dùng để phát triển và
// kiểm tra wrapper khi chưa ghép code Lab 2. KHI CÓ CODE LAB 2: thay module này
// bằng lõi thật, giữ nguyên tên cổng hoặc sửa phần khởi tạo trong accel_wrapper.v,
// và chỉnh tham số LAT của wrapper cho đúng độ trễ của lõi thật.
//
// Kiến trúc: N x N PE, output-stationary.
//   - PE(i,j) nhận a từ trái (cột 0 lấy a_in[i]), b từ trên (hàng 0 lấy b_in[j]).
//   - Mỗi chu kỳ en=1: acc += a*b, đẩy a sang phải (a_out), b xuống dưới (b_out).
//   - Đầu vào phải được skew: hàng i trễ i chu kỳ, cột j trễ j chu kỳ (wrapper lo).
//   - en=0 giữ nguyên mọi thanh ghi (kể cả a_out/b_out): Genus suy ra enable và
//     chèn clock gating cho gần như toàn bộ flop của mảng.
//   - clr xoá bộ tích luỹ và thanh ghi truyền.
// Với đầu vào skew, kết quả đầy đủ sau 3N-2 chu kỳ en=1.

module sa_core_model #(
    parameter N      = 4,
    parameter DW     = 8,
    parameter AW     = 32,
    parameter SIGNED = 1
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              en,
    input  wire              clr,
    input  wire [N*DW-1:0]   a_in,    // a_in[i*DW +: DW] vào hàng i
    input  wire [N*DW-1:0]   b_in,    // b_in[j*DW +: DW] vào cột j
    output wire [N*N*AW-1:0] c_out    // c_out[(i*N+j)*AW +: AW] = C[i][j]
);

    // Thanh ghi truyền của từng PE, gom thành vector phẳng (index i*N+j)
    wire [N*N*DW-1:0] a_out;
    wire [N*N*DW-1:0] b_out;

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_row
            for (gj = 0; gj < N; gj = gj + 1) begin : g_col
                localparam IDX = gi*N + gj;

                wire [DW-1:0] a_left;
                wire [DW-1:0] b_up;
                if (gj == 0) begin : g_al
                    assign a_left = a_in[gi*DW +: DW];
                end else begin : g_al
                    assign a_left = a_out[(IDX-1)*DW +: DW];
                end
                if (gi == 0) begin : g_bu
                    assign b_up = b_in[gj*DW +: DW];
                end else begin : g_bu
                    assign b_up = b_out[(IDX-N)*DW +: DW];
                end

                wire signed [2*DW+1:0] prod_s = $signed({{2{a_left[DW-1]}}, a_left}) *
                                                $signed({{2{b_up[DW-1]}},   b_up});
                wire        [2*DW-1:0] prod_u = a_left * b_up;
                wire        [AW-1:0]   prod   = SIGNED ? {{(AW-2*DW-2){prod_s[2*DW+1]}}, prod_s}
                                                       : {{(AW-2*DW){1'b0}}, prod_u};

                reg [DW-1:0] a_q, b_q;
                reg [AW-1:0] acc_q;

                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        a_q   <= {DW{1'b0}};
                        b_q   <= {DW{1'b0}};
                        acc_q <= {AW{1'b0}};
                    end else if (clr) begin
                        a_q   <= {DW{1'b0}};
                        b_q   <= {DW{1'b0}};
                        acc_q <= {AW{1'b0}};
                    end else if (en) begin
                        a_q   <= a_left;
                        b_q   <= b_up;
                        acc_q <= acc_q + prod;
                    end
                end

                assign a_out[IDX*DW +: DW] = a_q;
                assign b_out[IDX*DW +: DW] = b_q;
                assign c_out[IDX*AW +: AW] = acc_q;
            end
        end
    endgenerate

endmodule
