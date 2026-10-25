`timescale 1ns/1ps
`default_nettype none
// tb_rv32_alu - self-checking testbench for rv32_alu.
// The reference model is written differently from the RTL (signed compare operators,
// SRA with a mask). Corner vectors have hand-written results, then random operands lean to
// corner values.
// Plusargs: +seed=<n> +n=<random vectors per op> +timeout=<ns>
`include "rv32_defs.vh"

module tb_rv32_alu;

    reg  [3:0]  op;
    reg  [31:0] a, b;
    wire [31:0] y;

    rv32_alu dut (.op_i(op), .a_i(a), .b_i(b), .result_o(y));

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 20000;
    integer timeout_ns = 10000000;

    reg [3:0] ops [0:9];
    reg [31:0] corners [0:11];

    function [31:0] ref_alu(input [3:0] f_op, input [31:0] f_a, input [31:0] f_b);
        reg [4:0] s;
        begin
            s = f_b[4:0];
            case (f_op)
                `RV_ALU_ADD:  ref_alu = f_a + f_b;
                `RV_ALU_SUB:  ref_alu = f_a + ~f_b + 32'd1;
                `RV_ALU_SLL:  ref_alu = f_a << s;
                `RV_ALU_SLT:  ref_alu = ($signed(f_a) < $signed(f_b)) ? 32'd1 : 32'd0;
                `RV_ALU_SLTU: ref_alu = (f_a < f_b) ? 32'd1 : 32'd0;
                `RV_ALU_XOR:  ref_alu = f_a ^ f_b;
                `RV_ALU_SRL:  ref_alu = f_a >> s;
                `RV_ALU_SRA:  ref_alu = (f_a >> s) | (f_a[31] ? ~(32'hFFFF_FFFF >> s) : 32'h0);
                `RV_ALU_OR:   ref_alu = f_a | f_b;
                `RV_ALU_AND:  ref_alu = f_a & f_b;
                default:      ref_alu = 32'hxxxx_xxxx;
            endcase
        end
    endfunction

    task apply(input [3:0] t_op, input [31:0] t_a, input [31:0] t_b, input [31:0] t_exp);
        begin
            op = t_op; a = t_a; b = t_b;
            #1;
            checks = checks + 1;
            if (y !== t_exp) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: op=%b a=%h b=%h got=%h exp=%h", t_op, t_a, t_b, y, t_exp);
            end
        end
    endtask

    function [31:0] pick(input integer dummy);
        integer r;
        begin
            r = $random(seed);
            if (r[1:0] == 2'b00)
                pick = corners[{$random(seed)} % 12];
            else
                pick = $random(seed);
        end
    endfunction

    integer i, k;

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        ops[0] = `RV_ALU_ADD;  ops[1] = `RV_ALU_SUB; ops[2] = `RV_ALU_SLL;
        ops[3] = `RV_ALU_SLT;  ops[4] = `RV_ALU_SLTU; ops[5] = `RV_ALU_XOR;
        ops[6] = `RV_ALU_SRL;  ops[7] = `RV_ALU_SRA; ops[8] = `RV_ALU_OR;
        ops[9] = `RV_ALU_AND;
        corners[0]  = 32'h0000_0000; corners[1]  = 32'h0000_0001;
        corners[2]  = 32'hFFFF_FFFF; corners[3]  = 32'h7FFF_FFFF;
        corners[4]  = 32'h8000_0000; corners[5]  = 32'h8000_0001;
        corners[6]  = 32'h7FFF_FFFE; corners[7]  = 32'h0000_001F;
        corners[8]  = 32'h0000_0020; corners[9]  = 32'hAAAA_AAAA;
        corners[10] = 32'h5555_5555; corners[11] = 32'hFFFF_FFE0;

        // Corner vectors with hand-written expected values
        apply(`RV_ALU_ADD,  32'h7FFF_FFFF, 32'h0000_0001, 32'h8000_0000);
        apply(`RV_ALU_ADD,  32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000);
        apply(`RV_ALU_SUB,  32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF);
        apply(`RV_ALU_SUB,  32'h8000_0000, 32'h0000_0001, 32'h7FFF_FFFF);
        apply(`RV_ALU_SLT,  32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0001);
        apply(`RV_ALU_SLT,  32'h7FFF_FFFF, 32'h8000_0000, 32'h0000_0000);
        apply(`RV_ALU_SLT,  32'hFFFF_FFFF, 32'h0000_0000, 32'h0000_0001);
        apply(`RV_ALU_SLT,  32'h0000_0005, 32'h0000_0005, 32'h0000_0000);
        apply(`RV_ALU_SLT,  32'h8000_0000, 32'h8000_0001, 32'h0000_0001);
        apply(`RV_ALU_SLTU, 32'h0000_0000, 32'hFFFF_FFFF, 32'h0000_0001);
        apply(`RV_ALU_SLTU, 32'hFFFF_FFFF, 32'h0000_0000, 32'h0000_0000);
        apply(`RV_ALU_SLTU, 32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0000);
        apply(`RV_ALU_SLTU, 32'h1234_5678, 32'h1234_5678, 32'h0000_0000);
        apply(`RV_ALU_SLL,  32'h0000_0001, 32'h0000_001F, 32'h8000_0000);
        apply(`RV_ALU_SLL,  32'h0000_0001, 32'h0000_0020, 32'h0000_0001); // Only b[4:0] is used
        apply(`RV_ALU_SRL,  32'h8000_0000, 32'h0000_001F, 32'h0000_0001);
        apply(`RV_ALU_SRL,  32'h8000_0000, 32'hFFFF_FFE0, 32'h8000_0000);
        apply(`RV_ALU_SRA,  32'h8000_0000, 32'h0000_001F, 32'hFFFF_FFFF);
        apply(`RV_ALU_SRA,  32'h8000_0000, 32'h0000_0000, 32'h8000_0000);
        apply(`RV_ALU_SRA,  32'h8000_0000, 32'h0000_0004, 32'hF800_0000);
        apply(`RV_ALU_SRA,  32'h7FFF_FFFF, 32'h0000_001F, 32'h0000_0000);
        apply(`RV_ALU_XOR,  32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF);
        apply(`RV_ALU_OR,   32'hAAAA_0000, 32'h0000_5555, 32'hAAAA_5555);
        apply(`RV_ALU_AND,  32'hAAAA_FFFF, 32'hFFFF_5555, 32'hAAAA_5555);

        // Sweep every shift amount on the corner operands
        for (k = 0; k < 12; k = k + 1)
            for (i = 0; i < 64; i = i + 1) begin
                apply(`RV_ALU_SLL, corners[k], i, ref_alu(`RV_ALU_SLL, corners[k], i));
                apply(`RV_ALU_SRL, corners[k], i, ref_alu(`RV_ALU_SRL, corners[k], i));
                apply(`RV_ALU_SRA, corners[k], i, ref_alu(`RV_ALU_SRA, corners[k], i));
            end

        // Every pair of corner operands for each op
        for (k = 0; k < 10; k = k + 1)
            for (i = 0; i < 144; i = i + 1)
                apply(ops[k], corners[i / 12], corners[i % 12],
                      ref_alu(ops[k], corners[i / 12], corners[i % 12]));

        // Random
        for (k = 0; k < 10; k = k + 1)
            for (i = 0; i < n_rand; i = i + 1) begin : rnd
                reg [31:0] ra, rb;
                ra = pick(0);
                rb = pick(0);
                apply(ops[k], ra, rb, ref_alu(ops[k], ra, rb));
            end

        if (errors == 0)
            $display("PASS: tb_rv32_alu (%0d checks, seed %0d)", checks, seed0);
        else
            $display("FAIL: tb_rv32_alu (%0d errors / %0d checks, seed %0d)", errors, checks, seed0);
        $finish;
    end

    initial begin
        #1;
        #(timeout_ns);
        $display("FAIL: tb_rv32_alu timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
