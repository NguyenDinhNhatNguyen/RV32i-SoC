// ==============================================================================
// Processing Element (PE) for Systolic Array Matrix Multiplier
// Precision: 8-bit signed inputs (a_in, b_in), 20-bit accumulator (c_out)
// ==============================================================================

module pe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clr_acc,    // Xóa kết quả tích lũy
    input  wire        valid_in,   // Tín hiệu dữ liệu hợp lệ
    input  wire signed [7:0]  a_in,  // Dữ liệu dòng A (truyền theo chiều ngang)
    input  wire signed [7:0]  b_in,  // Dữ liệu dòng B (truyền theo chiều dọc)
    output reg  signed [7:0]  a_out, // Chuyển tiếp A sang PE bên phải
    output reg  signed [7:0]  b_out, // Chuyển tiếp B sang PE bên dưới
    output reg         valid_out,
    output reg  signed [19:0] c_out  // Giá trị tích lũy cục bộ
);

    wire signed [15:0] mult_res;
    assign mult_res = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out     <= 8'sd0;
            b_out     <= 8'sd0;
            valid_out <= 1'b0;
            c_out     <= 20'sd0;
        end else begin
            // Pipeline chuyền dữ liệu sang các PE lân cận
            a_out     <= a_in;
            b_out     <= b_in;
            valid_out <= valid_in;

            // Nhân và tích lũy (MAC)
            if (clr_acc) begin
                c_out <= valid_in ? {{4{mult_res[15]}}, mult_res} : 20'sd0;
            end else if (valid_in) begin
                c_out <= c_out + {{4{mult_res[15]}}, mult_res};
            end
        end
    end

endmodule
