`timescale 1ns/1ps
`default_nettype none
// tb_rv32_btb - self-checking testbench for rv32_btb (docs/btb_eval.md).
// Checks: no prediction after reset, random lookups and updates against an entry model
// (allocation only on a taken miss, JAL counter 3, branch counter 2, saturating counters,
// full tag so two PCs with the same index never share an entry), a loop branch trained to
// taken then to not taken, FENCE.I flush, asynchronous reset in the middle of a cycle.
// PCs come from a small pool so the same branches and index conflicts repeat often.
// Plusargs: +seed=<n> +n=<random cycles> +timeout=<ns>

module tb_rv32_btb;

    parameter ENTRIES = 8;
    localparam IDX_W = $clog2(ENTRIES);

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [31:0] if_pc = 32'h0;
    wire        pred_taken;
    wire [31:0] pred_target;
    reg         upd = 1'b0;
    reg  [31:0] upd_pc = 32'h0;
    reg         upd_jal = 1'b0;
    reg         upd_taken = 1'b0;
    reg  [31:0] upd_target = 32'h0;
    reg         flush = 1'b0;

    rv32_btb #(.ENTRIES(ENTRIES)) dut (
        .clk(clk), .rst_n(rst_n),
        .if_pc_i(if_pc), .pred_taken_o(pred_taken), .pred_target_o(pred_target),
        .upd_i(upd), .upd_pc_i(upd_pc), .upd_jal_i(upd_jal), .upd_taken_i(upd_taken),
        .upd_target_i(upd_target), .flush_i(flush)
    );

    always #5 clk = ~clk;

    // Entry model
    reg        m_valid  [0:ENTRIES-1];
    reg [31:0] m_pc     [0:ENTRIES-1];
    reg [31:0] m_target [0:ENTRIES-1];
    reg [1:0]  m_cnt    [0:ENTRIES-1];

    // PC pool: 4 PCs per index (same index, different tags), and a fixed target per PC
    localparam POOL = 4 * ENTRIES;
    reg [31:0] pool_pc  [0:POOL-1];
    reg [31:0] pool_tgt [0:POOL-1];

    integer errors = 0;
    integer checks = 0;
    integer n_hit  = 0;
    integer seed   = 1;
    integer seed0;
    integer n_rand = 20000;
    integer timeout_ns = 10000000;
    integer i, k;

    task clear_model;
        integer e;
        begin
            for (e = 0; e < ENTRIES; e = e + 1) begin
                m_valid[e] = 1'b0;
                m_cnt[e]   = 2'b00;
            end
        end
    endtask

    function [IDX_W-1:0] idx(input [31:0] pc);
        idx = pc[IDX_W+1:2];
    endfunction

    task check_lookup;
        reg hit, exp_taken;
        begin
            hit       = m_valid[idx(if_pc)] && m_pc[idx(if_pc)] == if_pc;
            exp_taken = hit && m_cnt[idx(if_pc)][1];
            checks = checks + 1;
            if (pred_taken !== exp_taken ||
                (exp_taken && pred_target !== m_target[idx(if_pc)])) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL: t=%0t pc %h: taken %b target %h, expected %b %h", $time,
                             if_pc, pred_taken, pred_target, exp_taken, m_target[idx(if_pc)]);
            end
            if (exp_taken) n_hit = n_hit + 1;
        end
    endtask

    task model_update;
        reg [IDX_W-1:0] e;
        begin
            e = idx(upd_pc);
            // The update also writes in the flush cycle (counter, tag, target), then the
            // flush clears every valid bit
            if (upd && m_valid[e] && m_pc[e] == upd_pc) begin
                if (upd_taken && m_cnt[e] != 2'b11) m_cnt[e] = m_cnt[e] + 2'b01;
                if (!upd_taken && m_cnt[e] != 2'b00) m_cnt[e] = m_cnt[e] - 2'b01;
            end else if (upd && upd_taken) begin
                m_valid[e]  = 1'b1;
                m_pc[e]     = upd_pc;
                m_target[e] = upd_target;
                m_cnt[e]    = {1'b1, upd_jal};
            end
            if (flush)
                for (k = 0; k < ENTRIES; k = k + 1)
                    m_valid[k] = 1'b0;
        end
    endtask

    // One cycle: inputs after the falling edge, lookup check before the rising edge,
    // model update on the rising edge
    task cycle(input [31:0] t_if, input t_upd, input [31:0] t_pc, input t_jal,
               input t_taken, input [31:0] t_tgt, input t_flush);
        begin
            @(negedge clk);
            if_pc = t_if; upd = t_upd; upd_pc = t_pc; upd_jal = t_jal;
            upd_taken = t_taken; upd_target = t_tgt; flush = t_flush;
            #4;
            check_lookup;
            @(posedge clk);
            model_update;
        end
    endtask

    // Random cycle from the pool: a JAL is always taken
    task rand_cycle;
        integer a, b;
        reg jal;
        begin
            a   = $unsigned($random(seed)) % POOL;
            b   = $unsigned($random(seed)) % POOL;
            jal = ($unsigned($random(seed)) % 4) == 0;
            cycle(pool_pc[a], ($unsigned($random(seed)) % 3) != 0, pool_pc[b], jal,
                  jal | $random(seed), pool_tgt[b], ($unsigned($random(seed)) % 500) == 0);
        end
    endtask

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        seed0 = seed;
        if ($value$plusargs("n=%d", n_rand)) ;
        if ($value$plusargs("timeout=%d", timeout_ns)) ;

        for (i = 0; i < POOL; i = i + 1) begin
            pool_pc[i]  = {$random(seed)} & ~(32'h3 | ((ENTRIES - 1) << 2)) |
                          ((i % ENTRIES) << 2);
            pool_tgt[i] = {$random(seed)} & ~32'h3;
        end
        clear_model;
        #12 rst_n = 1'b1;

        // Nothing is predicted after reset
        for (i = 0; i < POOL; i = i + 1)
            cycle(pool_pc[i], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);

        // Loop branch: allocated as weakly taken, saturates, then two not taken flip it
        cycle(32'h0, 1'b1, pool_pc[1], 1'b0, 1'b1, pool_tgt[1], 1'b0);
        for (i = 0; i < 4; i = i + 1)
            cycle(pool_pc[1], 1'b1, pool_pc[1], 1'b0, 1'b1, pool_tgt[1], 1'b0);
        for (i = 0; i < 3; i = i + 1)
            cycle(pool_pc[1], 1'b1, pool_pc[1], 1'b0, 1'b0, pool_tgt[1], 1'b0);
        cycle(pool_pc[1], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);
        // A not taken miss allocates nothing, another tag at the same index replaces the entry
        cycle(32'h0, 1'b1, pool_pc[2], 1'b0, 1'b0, pool_tgt[2], 1'b0);
        cycle(pool_pc[2], 1'b1, pool_pc[2 + ENTRIES], 1'b1, 1'b1, pool_tgt[2 + ENTRIES], 1'b0);
        cycle(pool_pc[2 + ENTRIES], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);
        cycle(pool_pc[2], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);
        // Flush
        cycle(pool_pc[2 + ENTRIES], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b1);
        cycle(pool_pc[2 + ENTRIES], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);

        for (i = 0; i < n_rand; i = i + 1)
            rand_cycle;

        // Asynchronous reset in the middle of a cycle
        @(negedge clk);
        #2 rst_n = 1'b0;
        #0.5;
        clear_model;
        @(posedge clk);
        #2 rst_n = 1'b1;
        for (i = 0; i < POOL; i = i + 1)
            cycle(pool_pc[i], 1'b0, 32'h0, 1'b0, 1'b0, 32'h0, 1'b0);
        for (i = 0; i < 2000; i = i + 1)
            rand_cycle;

        if (errors == 0)
            $display("PASS: tb_rv32_btb ENTRIES=%0d (%0d checks, %0d taken predictions, seed %0d)",
                     ENTRIES, checks, n_hit, seed0);
        else
            $display("FAIL: tb_rv32_btb (%0d errors / %0d checks, seed %0d)", errors, checks, seed0);
        $finish;
    end

    initial begin
        #1;
        #(timeout_ns);
        $display("FAIL: tb_rv32_btb timeout after %0d ns", timeout_ns);
        $finish;
    end

endmodule

`default_nettype wire
