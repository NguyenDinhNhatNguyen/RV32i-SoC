`timescale 1ns/1ps
`default_nettype none
// reset_sync - bộ đồng bộ reset 2 flop (RTL-09), docs/spec/soc_spec.md mục 1.
// Assert bất đồng bộ: rst_n_i = 0 thì rst_n_o = 0 ngay, không chờ clock.
// Deassert đồng bộ: rst_n_o lên 1 ở cạnh lên thứ hai sau khi rst_n_i lên 1.
// SDC: chỉ false path từ chân rst_n vào hai flop này. Đường từ rst_n_o tới chân
// reset của các flop khác phải kiểm recovery/removal (STA-01).

module reset_sync (
    input  wire clk,
    input  wire rst_n_i,        // chân reset ngoài, tích cực thấp
    output wire rst_n_o         // reset dùng chung cho mọi khối
);

    // Hai flop tách riêng: flop 2 làm reset cho cả SoC, flop 1 chỉ làm dữ liệu
    // (Verilator báo SYNCASYNCNET nếu gộp chung một vector)
    reg meta_q;
    reg sync_q;

    always @(posedge clk or negedge rst_n_i) begin
        if (!rst_n_i) begin
            meta_q <= 1'b0;
            sync_q <= 1'b0;
        end else begin
            meta_q <= 1'b1;
            sync_q <= meta_q;
        end
    end

    assign rst_n_o = sync_q;

endmodule

`default_nettype wire
