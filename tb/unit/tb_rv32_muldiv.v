`timescale 1ns/1ps
`default_nettype none
// tb_rv32_muldiv - testbench tự kiểm tra cho rv32_muldiv.
// Mô hình tham chiếu dùng phép nhân/chia 64 bit có dấu của Verilog (khác
// cách RTL tách tích riêng và chia từng bit), trường hợp đặc biệt viết theo
// bảng của đặc tả (chia cho 0, tràn -2^31 / -1).
// Kiểm tra:
//   - mọi cặp toán hạng biên x 8 phép, rồi toán hạng ngẫu nhiên có thiên vị,
//   - số chu kỳ: MUL* có kết quả ở chu kỳ thứ 2, DIV/REM ở chu kỳ thứ 34
//     tính từ chu kỳ bắt đầu,
//   - hold_i = 1 thì chưa bắt đầu, go_i = 0 thì kết quả giữ nguyên,
//   - req_i hạ giữa chừng thì phép bị bỏ, phép sau vẫn đúng.
// Plusarg: +seed=<n> +n=<số phép ngẫu nhiên>

module tb_rv32_muldiv;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         req = 1'b0;
    reg         hold = 1'b0;
    reg         go = 1'b0;
    reg  [2:0]  op = 3'd0;
    reg  [31:0] a = 32'h0, b = 32'h0;
    wire        done;
    wire [31:0] result;

    rv32_muldiv dut (
        .clk(clk), .rst_n(rst_n),
        .req_i(req), .hold_i(hold), .go_i(go), .op_i(op),
        .a_i(a), .b_i(b), .done_o(done), .result_o(result)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 20000;
    integer i, j, k;

    // ---- Mô hình tham chiếu ----------------------------------------------------------
    function [31:0] ref_md(input [2:0] f, input [31:0] x, input [31:0] y);
        reg signed [63:0] sx, sy;
        reg        [63:0] ux, uy, p;
        reg signed [31:0] sq, sr;   // tính riêng: trong biểu thức ?: có hằng không dấu thì / và % thành không dấu
        begin
            sq = $signed(x) / $signed(y);
            sr = $signed(x) % $signed(y);
            sx = {{32{x[31]}}, x};
            sy = {{32{y[31]}}, y};
            ux = {32'h0, x};
            uy = {32'h0, y};
            case (f)
                3'd0: begin p = sx * sy; ref_md = p[31:0];  end   // MUL
                3'd1: begin p = sx * sy; ref_md = p[63:32]; end   // MULH
                3'd2: begin p = sx * uy; ref_md = p[63:32]; end   // MULHSU
                3'd3: begin p = ux * uy; ref_md = p[63:32]; end   // MULHU
                3'd4: ref_md = (y == 0) ? 32'hffff_ffff :
                               (x == 32'h8000_0000 && y == 32'hffff_ffff) ? 32'h8000_0000 :
                               sq;                                // DIV
                3'd5: ref_md = (y == 0) ? 32'hffff_ffff : x / y;  // DIVU
                3'd6: ref_md = (y == 0) ? x :
                               (x == 32'h8000_0000 && y == 32'hffff_ffff) ? 32'h0 :
                               sr;                                // REM
                default: ref_md = (y == 0) ? x : x % y;           // REMU
            endcase
        end
    endfunction

    // Chạy một phép: bắt đầu ở chu kỳ đầu, đếm chu kỳ tới done, giữ go = 0
    // thêm vài chu kỳ (kết quả phải giữ), rồi go = 1.
    task run_op(input [2:0] f, input [31:0] x, input [31:0] y, input integer extra_hold);
        integer cyc, lat;
        reg [31:0] exp, first;
        begin
            @(negedge clk);
            // hold = 1 ít nhất một cạnh clock để biết chắc chu kỳ bắt đầu
            op = f; a = x; b = y; req = 1'b1; go = 1'b0; hold = 1'b1;
            repeat (extra_hold) begin
                @(posedge clk); #1;
                checks = checks + 1;
                if (done) begin
                    errors = errors + 1;
                    $display("FAIL: done while hold_i = 1");
                end
            end
            @(negedge clk);
            hold = 1'b0;
            cyc = 1;
            #1;
            while (!done && cyc < 100) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end
            exp = ref_md(f, x, y);
            lat = f[2] ? 34 : 2;
            checks = checks + 2;
            if (cyc != lat) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: op %0d latency %0d, expected %0d", f, cyc, lat);
            end
            if (result !== exp) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: op %0d a=%h b=%h got=%h exp=%h", f, x, y, result, exp);
            end
            // go = 0 thêm 2 chu kỳ: kết quả giữ nguyên
            first = result;
            @(posedge clk); #1;
            @(posedge clk); #1;
            checks = checks + 1;
            if (!done || result !== first) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: op %0d result not held while go_i = 0", f);
            end
            @(negedge clk);
            go = 1'b1;
            @(negedge clk);
            req = 1'b0;
            go  = 1'b0;
        end
    endtask

    // Phép bị huỷ sau k chu kỳ
    task abort_op(input [2:0] f, input [31:0] x, input [31:0] y, input integer cyc);
        begin
            @(negedge clk);
            op = f; a = x; b = y; req = 1'b1; go = 1'b0; hold = 1'b0;
            repeat (cyc) @(negedge clk);
            req = 1'b0;
        end
    endtask

    reg [31:0] corner [0:11];

    function [31:0] rand_operand(input integer dummy);
        integer r;
        begin
            r = $unsigned($random(seed)) % 8;
            case (r)
                0:       rand_operand = corner[$unsigned($random(seed)) % 12];
                1:       rand_operand = $unsigned($random(seed)) % 16;
                2:       rand_operand = -($unsigned($random(seed)) % 16);
                3:       rand_operand = $random(seed) >>> ($unsigned($random(seed)) % 32);
                default: rand_operand = $random(seed);
            endcase
        end
    endfunction

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;

        corner[0]  = 32'h0000_0000;  corner[1]  = 32'h0000_0001;
        corner[2]  = 32'hffff_ffff;  corner[3]  = 32'h0000_0002;
        corner[4]  = 32'hffff_fffe;  corner[5]  = 32'h7fff_ffff;
        corner[6]  = 32'h8000_0000;  corner[7]  = 32'h8000_0001;
        corner[8]  = 32'h0000_ffff;  corner[9]  = 32'h0001_0000;
        corner[10] = 32'h1234_5678;  corner[11] = 32'hedcb_a987;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        for (k = 0; k < 8; k = k + 1)
            for (i = 0; i < 12; i = i + 1)
                for (j = 0; j < 12; j = j + 1)
                    run_op(k, corner[i], corner[j], 0);

        for (i = 0; i < n_rand; i = i + 1) begin
            k = $unsigned($random(seed)) % 8;
            // Thỉnh thoảng có hold trước khi bắt đầu, hoặc một phép bị huỷ chen trước
            if (($unsigned($random(seed)) % 8) == 0)
                abort_op($unsigned($random(seed)) % 8, $random(seed), $random(seed),
                         1 + $unsigned($random(seed)) % 36);
            run_op(k, rand_operand(0), rand_operand(0),
                   (($unsigned($random(seed)) % 4) == 0) ? 1 + $unsigned($random(seed)) % 3 : 0);
        end

        if (errors == 0)
            $display("PASS: tb_rv32_muldiv (%0d checks, seed %0d)", checks, seed0);
        else
            $display("FAIL: tb_rv32_muldiv %0d errors in %0d checks", errors, checks);
        $finish;
    end

endmodule

`default_nettype wire
