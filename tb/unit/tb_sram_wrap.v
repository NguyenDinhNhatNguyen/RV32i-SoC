`timescale 1ns/1ps
`default_nettype none
// tb_sram_wrap - tests sram_wrap (RTL-08) with the sram_2k_macro model.
//   - Random word, half and byte reads and writes, compared with a reference memory.
//   - Full-word writes and reads: req_ready = 1, rsp_valid exactly one cycle later.
//     Byte/half writes: exactly 1 wait state cycle before acceptance.
//   - A new request in the response cycle (rule 3), with random idle cycles in between.
//   - Low-priority read port: f_gnt = ~req_valid, correct data one cycle later.
//   - Addresses cover every macro and cluster on a few words so reads follow writes.
// Plusargs: +seed=<n> +n=<bus requests> +timeout=<cycles>

module tb_sram_wrap;

    parameter BANK_W = 2;
    localparam AW    = 10 + BANK_W;
    localparam WORDS = 1 << AW;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg          req_valid = 1'b0;
    wire         req_ready;
    reg  [31:0]  req_addr  = 32'h0;
    reg          req_we    = 1'b0;
    reg  [3:0]   req_be    = 4'h0;
    reg  [31:0]  req_wdata = 32'h0;
    wire         rsp_valid;
    wire [31:0]  rsp_rdata;
    reg          f_req     = 1'b0;
    wire         f_gnt;
    reg  [AW-1:0] f_addr   = {AW{1'b0}};
    wire [31:0]  f_rdata;

    sram_wrap #(.BANK_W(BANK_W)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_we    (req_we),
        .req_be    (req_be),
        .req_wdata (req_wdata),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata),
        .f_req     (f_req),
        .f_gnt     (f_gnt),
        .f_addr    (f_addr),
        .f_rdata   (f_rdata)
    );

    // ---------------------------------------------------------- reference
    reg [31:0] ref_mem [0:WORDS-1];
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) ref_mem[i] = 32'h0;

    integer seed = 1, seed0, n_req = 4000, timeout = 200000;
    integer errors = 0, cycle = 0;
    integer n_acc = 0, n_rd = 0, n_wr_full = 0, n_wr_part = 0, n_fetch = 0, n_back2back = 0;

    task fail(input [8*80-1:0] msg);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("FAIL: %0s (cycle %0d)", msg, cycle);
        end
    endtask

    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] be);
        begin
            merge[ 7: 0] = be[0] ? nw[ 7: 0] : old[ 7: 0];
            merge[15: 8] = be[1] ? nw[15: 8] : old[15: 8];
            merge[23:16] = be[2] ? nw[23:16] : old[23:16];
            merge[31:24] = be[3] ? nw[31:24] : old[31:24];
        end
    endfunction

    // Word address: 70% land on 8 "hot" words spread over every macro
    function [AW-1:0] pick_addr(input integer r);
        reg [AW-1:0] hot;
        begin
            hot = (($unsigned(r) % 8) * (WORDS / 8)) + ($unsigned(r) % 3);
            if (($unsigned($random(seed)) % 10) < 7)
                pick_addr = hot;
            else
                pick_addr = $random(seed);
        end
    endfunction

    // ---------------------------------------------------------- checks on the rising edge
    reg         exp_q      = 1'b0;      // rsp_valid is required this cycle
    reg         exp_rd_q   = 1'b0;
    reg  [31:0] exp_data_q = 32'h0;
    reg         f_exp_q    = 1'b0;
    reg  [31:0] f_exp_data_q = 32'h0;
    reg         part_wait_q = 1'b0;     // Last cycle was the wait state of a partial write

    wire part = req_we & (req_be != 4'hF);

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            // Response
            if (rsp_valid !== exp_q)
                fail("rsp_valid in the wrong cycle");
            if (exp_q && exp_rd_q && rsp_rdata !== exp_data_q) begin
                $display("      read %h, expected %h", rsp_rdata, exp_data_q);
                fail("wrong read data");
            end
            if (exp_q && !exp_rd_q && rsp_rdata !== 32'h0)
                fail("rsp_rdata of a write is not 0");
            if (f_exp_q && f_rdata !== f_exp_data_q) begin
                $display("      f_rdata %h, mong doi %h", f_rdata, f_exp_data_q);
                fail("wrong fetch read");
            end
            // Ready
            if (f_gnt !== ~req_valid)
                fail("f_gnt khac ~req_valid");
            if (req_valid) begin
                if (!part && req_ready !== 1'b1)
                    fail("full-word read/write must have ready = 1");
                if (part && req_ready !== part_wait_q)
                    fail("a partial write must have exactly 1 wait state cycle");
            end
            if (req_valid && req_ready && exp_q)
                n_back2back = n_back2back + 1;

            // The reference model updates on acceptance
            exp_q    <= req_valid & req_ready;
            exp_rd_q <= ~req_we;
            if (req_valid && req_ready) begin
                n_acc = n_acc + 1;
                if (req_we) begin
                    ref_mem[req_addr[AW+1:2]] = merge(ref_mem[req_addr[AW+1:2]], req_wdata, req_be);
                    if (part) n_wr_part = n_wr_part + 1; else n_wr_full = n_wr_full + 1;
                end else begin
                    exp_data_q <= ref_mem[req_addr[AW+1:2]];
                    n_rd = n_rd + 1;
                end
            end
            part_wait_q <= req_valid & part & ~req_ready;
            f_exp_q <= f_req & f_gnt;
            if (f_req && f_gnt) begin
                f_exp_data_q <= ref_mem[f_addr];
                n_fetch = n_fetch + 1;
            end
        end
    end

    // ---------------------------------------------------------- master on the falling edge
    // req_ready is latched on the rising edge, so the master on the falling edge knows whether
    // the request was taken
    reg req_ready_q = 1'b0;
    always @(posedge clk) req_ready_q <= req_ready;

    integer issued = 0;
    integer r;
    always @(negedge clk) begin
        if (rst_n) begin
            // Hold the request until it is accepted (rule 1). req_ready on the
            // falling edge is the value of the cycle that just ended.
            if (!(req_valid && !req_ready_q)) begin
                if (issued < n_req && ($unsigned($random(seed)) % 4) != 0) begin
                    r         = $random(seed);
                    req_valid = 1'b1;
                    req_we    = ($unsigned($random(seed)) % 2);
                    req_addr  = {{(30-AW){1'b0}}, pick_addr(r), 2'b00};
                    req_wdata = $random(seed);
                    case ($unsigned($random(seed)) % 7)
                        0: req_be = 4'b0001;
                        1: req_be = 4'b0010;
                        2: req_be = 4'b0100;
                        3: req_be = 4'b1000;
                        4: req_be = 4'b0011;
                        5: req_be = 4'b1100;
                        default: req_be = 4'b1111;
                    endcase
                    issued = issued + 1;
                end else begin
                    req_valid = 1'b0;
                    req_we    = 1'bx;
                    req_addr  = 32'hxxxx_xxxx;
                    req_wdata = 32'hxxxx_xxxx;
                    req_be    = 4'hx;
                end
            end
            f_req  = ($unsigned($random(seed)) % 2);
            f_addr = pick_addr($random(seed));
        end
    end

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("n=%d", n_req)) ;
        if ($value$plusargs("timeout=%d", timeout)) ;
        seed0 = seed;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        while ((issued < n_req || req_valid) && cycle < timeout)
            @(posedge clk);
        repeat (3) @(posedge clk);
        if (cycle >= timeout) fail("qua thoi gian");
        if (n_wr_part == 0 || n_wr_full == 0 || n_rd == 0 || n_fetch == 0 || n_back2back == 0)
            fail("missing transaction type");
        if (errors == 0)
            $display("PASS: tb_sram_wrap BANK_W=%0d: %0d requests (%0d reads, %0d word writes, %0d byte/half writes), %0d fetches, %0d back-to-back requests (seed %0d)",
                     BANK_W, n_acc, n_rd, n_wr_full, n_wr_part, n_fetch, n_back2back, seed0);
        else
            $display("FAIL: tb_sram_wrap BANK_W=%0d: %0d loi (seed %0d)", BANK_W, errors, seed0);
        $finish;
    end

endmodule

`default_nettype wire
