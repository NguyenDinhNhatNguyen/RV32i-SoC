`timescale 1ns/1ps
`default_nettype none
// tb_rv32_imm_gen - testbench tự kiểm tra cho rv32_imm_gen.
// Tham chiếu theo chiều ngược: rải giá trị immediate vào word lệnh theo bố cục
// bit của đặc tả Unprivileged (các bit còn lại ngẫu nhiên), imm_gen phải trả
// lại đúng giá trị đó.
// Plusarg: +seed=<n> +n=<số vector ngẫu nhiên mỗi dạng> +timeout=<ns>
`include "rv32_defs.vh"

module tb_rv32_imm_gen;

    reg  [31:0] instr;
    reg  [2:0]  imm_type;
    wire [31:0] imm;

    rv32_imm_gen dut (.instr_i(instr[31:7]), .imm_type_i(imm_type), .imm_o(imm));

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 20000;
    integer timeout_ns = 10000000;

    // Mã hoá immediate v của dạng f vào các bit lệnh ngẫu nhiên r.
    // v phải là giá trị hợp lệ của dạng đó.
    function [31:0] encode(input [2:0] f, input [31:0] v, input [31:0] r);
        reg [31:0] w;
        begin
            w = r;
            case (f)
                `RV_IMM_I: w[31:20] = v[11:0];
                `RV_IMM_S: begin w[31:25] = v[11:5]; w[11:7] = v[4:0]; end
                `RV_IMM_B: begin
                    w[31] = v[12]; w[7] = v[11]; w[30:25] = v[10:5]; w[11:8] = v[4:1];
                end
                `RV_IMM_U: w[31:12] = v[31:12];
                `RV_IMM_J: begin
                    w[31] = v[20]; w[19:12] = v[19:12]; w[20] = v[11]; w[30:21] = v[10:1];
                end
                `RV_IMM_Z: w[19:15] = v[4:0];
                default:   w = r;
            endcase
            encode = w;
        end
    endfunction

    // Biến một word ngẫu nhiên thành immediate hợp lệ của dạng f.
    function [31:0] legalize(input [2:0] f, input [31:0] r);
        begin
            case (f)
                `RV_IMM_I, `RV_IMM_S: legalize = {{20{r[11]}}, r[11:0]};
                `RV_IMM_B: legalize = {{19{r[12]}}, r[12:1], 1'b0};
                `RV_IMM_U: legalize = {r[31:12], 12'h0};
                `RV_IMM_J: legalize = {{11{r[20]}}, r[20:1], 1'b0};
                `RV_IMM_Z: legalize = {27'h0, r[4:0]};
                default:   legalize = 32'h0;
            endcase
        end
    endfunction

    task apply(input [2:0] f, input [31:0] v);
        reg [31:0] r;
        begin
            r = $random(seed);
            instr = encode(f, v, r);
            imm_type = f;
            #1;
            checks = checks + 1;
            if (imm !== v) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: type=%0d instr=%h got=%h exp=%h", f, instr, imm, v);
            end
        end
    endtask

    integer i, f;

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        // Biên của từng dạng
        apply(`RV_IMM_I, 32'h0000_0000); apply(`RV_IMM_I, 32'hFFFF_FFFF);
        apply(`RV_IMM_I, 32'h0000_07FF); apply(`RV_IMM_I, 32'hFFFF_F800);
        apply(`RV_IMM_S, 32'h0000_0000); apply(`RV_IMM_S, 32'hFFFF_FFFF);
        apply(`RV_IMM_S, 32'h0000_07FF); apply(`RV_IMM_S, 32'hFFFF_F800);
        apply(`RV_IMM_B, 32'h0000_0000); apply(`RV_IMM_B, 32'hFFFF_FFFE);
        apply(`RV_IMM_B, 32'h0000_0FFE); apply(`RV_IMM_B, 32'hFFFF_F000);
        apply(`RV_IMM_B, 32'h0000_0800); apply(`RV_IMM_B, 32'h0000_0002);
        apply(`RV_IMM_U, 32'h0000_0000); apply(`RV_IMM_U, 32'hFFFF_F000);
        apply(`RV_IMM_U, 32'h8000_0000); apply(`RV_IMM_U, 32'h0000_1000);
        apply(`RV_IMM_J, 32'h0000_0000); apply(`RV_IMM_J, 32'hFFFF_FFFE);
        apply(`RV_IMM_J, 32'h000F_FFFE); apply(`RV_IMM_J, 32'hFFF0_0000);
        apply(`RV_IMM_J, 32'h0000_0800); apply(`RV_IMM_J, 32'h0000_0002);
        apply(`RV_IMM_Z, 32'h0000_0000); apply(`RV_IMM_Z, 32'h0000_001F);

        // Mọi immediate chỉ có một bit 1 (walking one) ở từng dạng
        for (f = 0; f < 6; f = f + 1)
            for (i = 0; i < 32; i = i + 1)
                if (legalize(f, 32'h1 << i) == (32'h1 << i))
                    apply(f, 32'h1 << i);

        // Giá trị ngẫu nhiên, các bit xung quanh ngẫu nhiên
        for (f = 0; f < 6; f = f + 1)
            for (i = 0; i < n_rand; i = i + 1)
                apply(f, legalize(f, $random(seed)));

        if (errors == 0)
            $display("PASS: tb_rv32_imm_gen (%0d checks, seed %0d)", checks, seed0);
        else
            $display("FAIL: tb_rv32_imm_gen (%0d errors / %0d checks, seed %0d)", errors, checks, seed0);
        $finish;
    end

    initial begin
        #1;
        #(timeout_ns);
        $display("FAIL: tb_rv32_imm_gen timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
