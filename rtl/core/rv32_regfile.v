`timescale 1ns/1ps
`default_nettype none
// rv32_regfile - register file 32 x 32 bit, x0 luôn bằng 0.
// 2 cổng đọc tổ hợp, 1 cổng ghi (tầng WB).
// Không có bypass ghi -> đọc bên trong vì core tự forward WB -> EX.
// Mọi thanh ghi có reset bất đồng bộ về 0 để mô phỏng mức cổng không bị X.

module rv32_regfile (
    input  wire        clk,
    input  wire        rst_n,
    // Cổng ghi
    input  wire        we_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [31:0] rd_data_i,
    // Cổng đọc
    input  wire [4:0]  rs1_addr_i,
    output wire [31:0] rs1_data_o,
    input  wire [4:0]  rs2_addr_i,
    output wire [31:0] rs2_data_o
);

    // Enable ghi one-hot cho từng thanh ghi: mỗi thanh ghi là một nhóm
    // enable riêng để Genus gate clock được.
    wire [31:0] wr_sel = we_i ? (32'h1 << rd_addr_i) : 32'h0;

    wire [31:0] regs [0:31];
    assign regs[0] = 32'h0;

    genvar g;
    generate
        for (g = 1; g < 32; g = g + 1) begin : g_reg
            reg [31:0] q;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    q <= 32'h0;
                else if (wr_sel[g])
                    q <= rd_data_i;
            end
            assign regs[g] = q;
        end
    endgenerate

    assign rs1_data_o = regs[rs1_addr_i];
    assign rs2_data_o = regs[rs2_addr_i];

    // wr_sel[0] (ghi vào x0) cố ý bỏ qua.
    wire unused_ok = wr_sel[0];

endmodule

`default_nettype wire
