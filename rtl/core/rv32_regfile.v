`timescale 1ns/1ps
`default_nettype none
// rv32_regfile - 32 x 32-bit register file, x0 is always 0.
// 2 combinational read ports, 1 write port (WB stage).
// No internal write-to-read bypass, because the core forwards WB -> EX itself.
// Every register has an asynchronous reset to 0 so gate-level simulation has no X.

module rv32_regfile (
    input  wire        clk,
    input  wire        rst_n,
    // Write port
    input  wire        we_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [31:0] rd_data_i,
    // Read ports
    input  wire [4:0]  rs1_addr_i,
    output wire [31:0] rs1_data_o,
    input  wire [4:0]  rs2_addr_i,
    output wire [31:0] rs2_data_o
);

    // One-hot write enable per register: each register is its own enable group
    // so Genus can gate its clock.
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

    // wr_sel[0] (write to x0) is ignored on purpose.
    wire unused_ok = wr_sel[0];

endmodule

`default_nettype wire
