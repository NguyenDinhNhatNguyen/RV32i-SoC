// ==============================================================================
// 4x4 Systolic Array Hardware Accelerator Top Module
// Course: IC Physical Design (RTL to GDSII)
// Target Frequency: 150MHz - 250MHz on GPDK 45nm
// Equivalent Gates: ~15,000 - 25,000 gates
// ==============================================================================

module accelerator_top (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire               clear,
    input  wire [3:0]         row_sel,      // Đọc kết quả hàng nào ra bus
    // Đầu vào ma trận A (4 dòng, mỗi chu kỳ nạp 1 giá trị 8-bit)
    input  wire signed [7:0]  a_row0,
    input  wire signed [7:0]  a_row1,
    input  wire signed [7:0]  a_row2,
    input  wire signed [7:0]  a_row3,
    // Đầu vào ma trận B (4 cột, mỗi chu kỳ nạp 1 giá trị 8-bit)
    input  wire signed [7:0]  b_col0,
    input  wire signed [7:0]  b_col1,
    input  wire signed [7:0]  b_col2,
    input  wire signed [7:0]  b_col3,
    // Kết quả đầu ra (4 giá trị 20-bit của hàng được chọn)
    output reg  signed [19:0] res_out0,
    output reg  signed [19:0] res_out1,
    output reg  signed [19:0] res_out2,
    output reg  signed [19:0] res_out3,
    output reg                busy,
    output reg                done
);

    // Dây nối ma trận A ngang (4 hàng, 5 điểm nối)
    wire signed [7:0] a_wire [0:3][0:4];
    // Dây nối ma trận B dọc (5 điểm nối, 4 cột)
    wire signed [7:0] b_wire [0:4][0:3];
    // Tín hiệu valid theo từng PE
    wire v_wire [0:3][0:4];
    // Ma trận tích lũy C (4x4 PE)
    wire signed [19:0] c_matrix [0:3][0:3];

    // Nạp dữ liệu vào biên trái (A) và biên trên (B)
    assign a_wire[0][0] = a_row0;
    assign a_wire[1][0] = a_row1;
    assign a_wire[2][0] = a_row2;
    assign a_wire[3][0] = a_row3;

    assign b_wire[0][0] = b_col0;
    assign b_wire[0][1] = b_col1;
    assign b_wire[0][2] = b_col2;
    assign b_wire[0][3] = b_col3;

    assign v_wire[0][0] = busy;
    assign v_wire[1][0] = busy;
    assign v_wire[2][0] = busy;
    assign v_wire[3][0] = busy;

    // Khởi tạo mảng 4x4 Processing Elements (16 PEs)
    genvar i, j;
    generate
        for (i = 0; i < 4; i = i + 1) begin: ROW
            for (j = 0; j < 4; j = j + 1) begin: COL
                pe u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clr_acc   (clear),
                    .valid_in  (v_wire[i][j]),
                    .a_in      (a_wire[i][j]),
                    .b_in      (b_wire[i][j]),
                    .a_out     (a_wire[i][j+1]),
                    .b_out     (b_wire[i+1][j]),
                    .valid_out (v_wire[i][j+1]),
                    .c_out     (c_matrix[i][j])
                );
            end
        end
    endgenerate

    // FSM Điều khiển tính toán và đếm chu kỳ hoàn tất
    reg [3:0] step_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            step_cnt <= 4'd0;
        end else begin
            if (start) begin
                busy     <= 1'b1;
                done     <= 1'b0;
                step_cnt <= 4'd1;
            end else if (busy) begin
                if (step_cnt == 4'd10) begin // Đủ độ trễ pipeline 4x4
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    step_cnt <= 4'd0;
                end else begin
                    step_cnt <= step_cnt + 4'd1;
                end
            end
        end
    end

    // Đọc kết quả tích lũy theo hàng (Row Selection) ra cổng ngoài
    always @(*) begin
        case (row_sel)
            4'b0001: begin
                res_out0 = c_matrix[0][0];
                res_out1 = c_matrix[0][1];
                res_out2 = c_matrix[0][2];
                res_out3 = c_matrix[0][3];
            end
            4'b0010: begin
                res_out0 = c_matrix[1][0];
                res_out1 = c_matrix[1][1];
                res_out2 = c_matrix[1][2];
                res_out3 = c_matrix[1][3];
            end
            4'b0100: begin
                res_out0 = c_matrix[2][0];
                res_out1 = c_matrix[2][1];
                res_out2 = c_matrix[2][2];
                res_out3 = c_matrix[2][3];
            end
            4'b1000: begin
                res_out0 = c_matrix[3][0];
                res_out1 = c_matrix[3][1];
                res_out2 = c_matrix[3][2];
                res_out3 = c_matrix[3][3];
            end
            default: begin
                res_out0 = c_matrix[0][0];
                res_out1 = c_matrix[0][1];
                res_out2 = c_matrix[0][2];
                res_out3 = c_matrix[0][3];
            end
        endcase
    end

endmodule
