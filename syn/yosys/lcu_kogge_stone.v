// lcu_kogge_stone.v - techmap cho $lcu (bộ tính carry của $alu) theo kiểu Kogge-Stone,
// chỉ dùng trong flow nhà (synth_nangate.tcl). Yosys 0.33 mặc định map $lcu thành
// chuỗi ripple, trễ tăng tuyến tính theo số bit, trong khi Genus dùng bộ cộng nhanh.
// Tên module bắt đầu bằng _80_ để techmap chọn trước _90_lcu của +/techmap.v.
// CO[i] = G[i] | P[i] & CO[i-1], với CO[-1] = CI.
(* techmap_celltype = "$lcu" *)
module _80_lcu_kogge_stone (P, G, CI, CO);
    parameter WIDTH = 2;

    (* force_downto *)
    input  wire [WIDTH-1:0] P, G;
    input  wire             CI;
    (* force_downto *)
    output reg  [WIDTH-1:0] CO;

    integer i, j;
    reg [WIDTH-1:0] p, g;

    always @(*) begin
        p = P;
        g = G;
        g[0] = g[0] | (p[0] & CI);
        // Mỗi tầng gộp nhóm cách 2^i bit. j giảm dần nên g[j - 2^i] còn là
        // giá trị của tầng trước.
        for (i = 0; (1 << i) < WIDTH; i = i + 1) begin
            for (j = WIDTH - 1; j >= (1 << i); j = j - 1) begin
                g[j] = g[j] | (p[j] & g[j - (1 << i)]);
                p[j] = p[j] & p[j - (1 << i)];
            end
        end
        CO = g;
    end
endmodule
