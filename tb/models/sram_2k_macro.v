`timescale 1ns/1ps
`default_nettype none
// sram_2k_macro - mô hình ở nhà của SRAM hard macro trên server, CHỈ DÙNG KHI MÔ PHỎNG.
// Đúng tên và chân của macro thật (docs/macro_notes.md mục 1): 1024 word x 32 bit,
// CEN, WEN tích cực thấp, không ghi theo byte. Trên server thay file này bằng
// ~/PDK_GPDK45/lib/sram_2k_macro.v (không đưa file đó lên repo).
//
// Hành vi:
//   - CEN=0, WEN=1: đọc, Q có ở chu kỳ sau (đọc đồng bộ).
//   - CEN=0, WEN=0: ghi D vào A. Q thành X vì chưa biết macro thật làm gì khi
//     ghi (macro_notes mục 2). Wrapper không được dùng Q sau chu kỳ ghi.
//   - CEN=1: Q giữ nguyên.
// Nội dung khởi tạo 0. Testbench nạp chương trình bằng tham chiếu phân cấp vào mem.

module sram_2k_macro (
    input  wire        CLK,
    input  wire        CEN,
    input  wire        WEN,
    input  wire [9:0]  A,
    input  wire [31:0] D,
    output reg  [31:0] Q
);

    reg [31:0] mem [0:1023];
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0;
    end

    always @(posedge CLK) begin
        if (CEN === 1'b0) begin
            if (WEN === 1'b0) begin
                mem[A] <= D;
                Q      <= 32'hxxxx_xxxx;
            end else if (WEN === 1'b1) begin
                Q      <= mem[A];
            end else begin
                Q      <= 32'hxxxx_xxxx;
                $display("LOI: %m WEN = X khi CEN = 0 (t=%0t)", $time);
            end
        end else if (CEN !== 1'b1) begin
            Q <= 32'hxxxx_xxxx;
            $display("LOI: %m CEN = X (t=%0t)", $time);
        end
    end

endmodule

`default_nettype wire
