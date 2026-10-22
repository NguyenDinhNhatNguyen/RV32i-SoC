`timescale 1ns/1ps
`default_nettype none
// tb_rv32_lsu_align - testbench tự kiểm tra cho rv32_lsu_align.
// Mô hình tham chiếu làm việc trên mảng byte (không dịch hay lặp làn như RTL):
//   yêu cầu : lệch khi và chỉ khi addr % size != 0. Nếu không lệch thì byte
//             enable phủ đúng các byte [addr, addr+size) và mỗi làn được bật
//             mang byte thứ (làn - addr) của rs2. Làn không bật thì bỏ qua.
//   phản hồi: các byte [addr, addr+size) của word trên bus, mở rộng dấu hoặc 0.
// Mọi kích thước x offset với dữ liệu biên (bit dấu 0 và 1 ở từng byte),
// sau đó dữ liệu ngẫu nhiên.
// Plusarg: +seed=<n> +n=<số vector ngẫu nhiên> +timeout=<ns>
`include "rv32_defs.vh"

module tb_rv32_lsu_align;

    reg  [1:0]  req_size;
    reg  [1:0]  req_addr_lo;
    reg  [31:0] req_wdata;
    wire [3:0]  req_be;
    wire [31:0] req_wdata_o;
    wire        req_misaligned;
    reg  [2:0]  rsp_funct3;
    reg  [1:0]  rsp_addr_lo;
    reg  [31:0] rsp_rdata;
    wire [31:0] rsp_data;

    rv32_lsu_align dut (
        .req_size_i       (req_size),
        .req_addr_lo_i    (req_addr_lo),
        .req_wdata_i      (req_wdata),
        .req_be_o         (req_be),
        .req_wdata_o      (req_wdata_o),
        .req_misaligned_o (req_misaligned),
        .rsp_funct3_i     (rsp_funct3),
        .rsp_addr_lo_i    (rsp_addr_lo),
        .rsp_rdata_i      (rsp_rdata),
        .rsp_data_o       (rsp_data)
    );

    integer errors = 0;
    integer checks = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 20000;
    integer timeout_ns = 10000000;
    integer i, sz, off, f;

    function integer size_bytes(input [1:0] size);
        size_bytes = (size == `RV_MEM_B) ? 1 : (size == `RV_MEM_H) ? 2 : 4;
    endfunction

    task fail_msg(input [8*16-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("FAIL: %0s size=%0d f3=%0d off=%0d wdata=%h rdata=%h got=%h exp=%h",
                         what, req_size, rsp_funct3, req_addr_lo, req_wdata, rsp_rdata, got, exp);
        end
    endtask

    // Phía yêu cầu cho (kích thước, offset, dữ liệu)
    task check_req(input [1:0] t_size, input [1:0] t_off, input [31:0] t_data);
        integer n, b;
        reg     exp_mis;
        reg [3:0] exp_be;
        begin
            req_size = t_size; req_addr_lo = t_off; req_wdata = t_data;
            #1;
            checks = checks + 1;
            if (t_size == 2'b11) begin
                // Không bao giờ được phát (decoder báo illegal), không được bật làn nào
                if (req_be !== 4'b0000 || req_misaligned !== 1'b0)
                    fail_msg("req size 11", {27'b0, req_misaligned, req_be}, 32'h0);
            end else begin
                n       = size_bytes(t_size);
                exp_mis = (t_off % n) != 0;
                exp_be  = 4'b0000;
                for (b = 0; b < 4; b = b + 1)
                    if (b >= t_off && b < t_off + n) exp_be[b] = 1'b1;
                if (req_misaligned !== exp_mis)
                    fail_msg("misaligned", req_misaligned, exp_mis);
                if (!exp_mis) begin
                    if (req_be !== exp_be)
                        fail_msg("be", req_be, exp_be);
                    for (b = 0; b < 4; b = b + 1)
                        if (exp_be[b] && req_wdata_o[8*b +: 8] !== t_data[8*(b - t_off) +: 8])
                            fail_msg("wdata lane", req_wdata_o, t_data);
                end
            end
        end
    endtask

    // Phía phản hồi cho (funct3, offset, word trên bus), chỉ truy cập thẳng hàng
    task check_rsp(input [2:0] t_f3, input [1:0] t_off, input [31:0] t_word);
        integer n, b;
        reg [31:0] exp;
        reg        sign;
        begin
            rsp_funct3 = t_f3; rsp_addr_lo = t_off; rsp_rdata = t_word;
            #1;
            checks = checks + 1;
            n   = size_bytes(t_f3[1:0]);
            exp = 32'h0;
            for (b = 0; b < n; b = b + 1)
                exp[8*b +: 8] = t_word[8*(t_off + b) +: 8];
            sign = ~t_f3[2] & exp[8*n - 1];
            for (b = n; b < 4; b = b + 1)
                exp[8*b +: 8] = {8{sign}};
            if (rsp_data !== exp)
                fail_msg("load data", rsp_data, exp);
        end
    endtask

    // Các funct3 của load mà decoder chấp nhận
    function [2:0] ld_f3(input integer k);
        case (k)
            0: ld_f3 = `RV_F3_LB;
            1: ld_f3 = `RV_F3_LH;
            2: ld_f3 = `RV_F3_LW;
            3: ld_f3 = `RV_F3_LBU;
            default: ld_f3 = `RV_F3_LHU;
        endcase
    endfunction

    reg [31:0] edge_data [0:5];

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        rsp_funct3 = 3'b000; rsp_addr_lo = 2'b00; rsp_rdata = 32'h0;
        edge_data[0] = 32'h00000000;
        edge_data[1] = 32'hFFFFFFFF;
        edge_data[2] = 32'h80808080;
        edge_data[3] = 32'h7F7F7F7F;
        edge_data[4] = 32'h8000807F;
        edge_data[5] = 32'h01FF80FE;

        // Quét đủ kích thước x offset với dữ liệu biên
        for (i = 0; i < 6; i = i + 1)
            for (sz = 0; sz < 4; sz = sz + 1)
                for (off = 0; off < 4; off = off + 1)
                    check_req(sz, off, edge_data[i]);

        for (i = 0; i < 6; i = i + 1)
            for (f = 0; f < 5; f = f + 1)
                for (off = 0; off < 4; off = off + 1)
                    if (off % size_bytes(ld_f3(f)) == 0)
                        check_rsp(ld_f3(f), off, edge_data[i]);

        // Ngẫu nhiên
        for (i = 0; i < n_rand; i = i + 1) begin
            check_req($random(seed), $random(seed), $random(seed));
            f   = $unsigned($random(seed)) % 5;
            off = ($unsigned($random(seed)) % 4) & ~(size_bytes(ld_f3(f)) - 1);
            check_rsp(ld_f3(f), off, $random(seed));
        end

        if (errors == 0)
            $display("PASS: tb_rv32_lsu_align (%0d checks, seed %0d)", checks, seed0);
        else
            $display("FAIL: tb_rv32_lsu_align (%0d errors / %0d checks, seed %0d)", errors, checks, seed0);
        $finish;
    end

    initial begin
        #(timeout_ns);
        $display("FAIL: tb_rv32_lsu_align timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
