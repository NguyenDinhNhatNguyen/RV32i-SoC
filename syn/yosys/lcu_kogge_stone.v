// lcu_kogge_stone.v - techmap for $lcu (the carry unit of $alu) as Kogge-Stone,
// used only in the home flow (synth_nangate.tcl). By default Yosys 0.33 maps $lcu to a
// ripple chain whose delay grows linearly with width, while Genus uses fast adders.
// The module name starts with _80_ so techmap picks it before _90_lcu of +/techmap.v.
// CO[i] = G[i] | P[i] & CO[i-1], with CO[-1] = CI.
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
        // Each level merges groups 2^i bits apart. j counts down, so g[j - 2^i] still holds
        // the previous level's value.
        for (i = 0; (1 << i) < WIDTH; i = i + 1) begin
            for (j = WIDTH - 1; j >= (1 << i); j = j - 1) begin
                g[j] = g[j] | (p[j] & g[j - (1 << i)]);
                p[j] = p[j] & p[j - (1 << i)];
            end
        end
        CO = g;
    end
endmodule
