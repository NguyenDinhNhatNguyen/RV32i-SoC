`timescale 1ns/1ps
`default_nettype none
// tb_dma_apb - checks dma_apb (RTL-15).
//   - APB config: reset values, SRC/DST keep bits 31:2, LEN keeps 16 bits, PSLVERR on
//     unknown or misaligned offsets, writes while BUSY ignored, STATUS write-1-to-clear.
//   - Master port against a memory slave model with random wait states (ready = 0) and
//     random response delay: data copied matches a forward word-by-word reference copy
//     (overlapping ranges included).
//   - Bus rules on the master port: request held while ready = 0 (rule 1), at most one
//     request waiting for its response (rule 3), full words only, no X on valid.
//   - LEN = 0 sets DONE without bus traffic. A bus error on a read or a write stops the
//     transfer with ERR = 1 and DONE = 1, words before the error are copied.
//   - irq = DONE & IRQ_EN delayed by one flop.
//   - No stalls: one word takes 2 cycles.
// Plusarg: +seed=<n> +n=<random transfers>

module tb_dma_apb;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    reg  [11:0] paddr  = 12'h0;
    reg  [31:0] pwdata = 32'h0;
    wire [31:0] prdata;
    wire        pready, pslverr;

    wire        m_req_valid, m_we;
    reg         m_req_ready = 1'b1;
    wire [31:0] m_addr, m_wdata;
    wire [3:0]  m_be;
    wire        m_rsp_valid;
    wire [31:0] m_rsp_rdata;
    wire        m_rsp_err;
    wire        irq;

    dma_apb dut (
        .PCLK        (clk),
        .PRESETn     (rst_n),
        .PSEL        (psel),
        .PENABLE     (penable),
        .PWRITE      (pwrite),
        .PADDR       (paddr),
        .PWDATA      (pwdata),
        .PRDATA      (prdata),
        .PREADY      (pready),
        .PSLVERR     (pslverr),
        .m_req_valid (m_req_valid),
        .m_req_ready (m_req_ready),
        .m_addr      (m_addr),
        .m_we        (m_we),
        .m_be        (m_be),
        .m_wdata     (m_wdata),
        .m_rsp_valid (m_rsp_valid),
        .m_rsp_rdata (m_rsp_rdata),
        .m_rsp_err   (m_rsp_err),
        .irq         (irq)
    );

    localparam [11:0] SRC = 12'h000, DST = 12'h004, LEN = 12'h008, CTRL = 12'h00C,
                      STATUS = 12'h010;
    localparam WORDS = 4096;            // Memory model: word index = addr[13:2]

    integer seed = 1, seed0, n_xfer = 200, stall_pct = 0, delay_max = 0;
    integer errors = 0, cycle = 0;
    integer i, k;

    task fail(input [8*80-1:0] msg);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("FAIL: %0s (cycle %0d)", msg, cycle);
        end
    endtask

    // APB tasks, same style as tb_gpio_apb
    reg [31:0] rd;
    reg        err_seen;

    task apb_write(input [11:0] a, input [31:0] d);
        begin
            @(negedge clk); psel = 1; pwrite = 1; paddr = a; pwdata = d; penable = 0;
            @(negedge clk); penable = 1;
            #3 err_seen = pslverr;
            @(negedge clk); psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read(input [11:0] a);
        begin
            @(negedge clk); psel = 1; pwrite = 0; paddr = a; penable = 0;
            @(negedge clk); penable = 1;
            #3 rd = prdata; err_seen = pslverr;
            @(negedge clk); psel = 0; penable = 0;
        end
    endtask

    // Memory slave model on the master port. Addresses with addr[31:28] = 0xE return err.
    reg  [31:0] mem  [0:WORDS-1];
    reg  [31:0] refm [0:WORDS-1];
    reg         pend    = 1'b0;
    integer     cnt     = 0;
    reg  [31:0] sdata   = 32'h0;
    reg         serr    = 1'b0;
    integer     n_acc   = 0;            // Accepted requests, to check LEN = 0 has none
    reg         pend_n;

    assign m_rsp_valid = pend && (cnt == 0);
    assign m_rsp_rdata = m_rsp_valid ? sdata : 32'hBAD0_BAD0;
    assign m_rsp_err   = m_rsp_valid & serr;

    always @(negedge clk)
        m_req_ready <= ($unsigned($random(seed)) % 100) >= stall_pct;

    // Rule checks use the values of the cycle that just ended
    reg         hold_q = 1'b0;
    reg  [31:0] hold_addr_q, hold_wdata_q;
    reg         hold_we_q;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (m_req_valid === 1'bx) fail("m_req_valid is X");
            if (hold_q && (!m_req_valid || m_addr !== hold_addr_q || m_we !== hold_we_q ||
                           (m_we && m_wdata !== hold_wdata_q)))
                fail("request changed while ready = 0");
            if (m_req_valid && m_be !== 4'hF) fail("m_be is not 4'hF");
            if (m_req_valid && m_req_ready && pend && !m_rsp_valid)
                fail("new request while a response is still pending");
            pend_n = pend;
            if (m_rsp_valid) pend_n = 1'b0;
            else if (pend)   cnt <= cnt - 1;
            if (m_req_valid && m_req_ready) begin
                n_acc  = n_acc + 1;
                pend_n = 1'b1;
                cnt   <= $unsigned($random(seed)) % (delay_max + 1);
                serr  <= (m_addr[31:28] == 4'hE);
                if (m_addr[31:28] == 4'hE)
                    sdata <= 32'h0;
                else if (m_we) begin
                    mem[m_addr[13:2]] = m_wdata;
                    sdata <= 32'h0;
                end else
                    sdata <= mem[m_addr[13:2]];
            end
            pend         <= pend_n;
            hold_q       <= m_req_valid & ~m_req_ready;
            hold_addr_q  <= m_addr;
            hold_wdata_q <= m_wdata;
            hold_we_q    <= m_we;
        end
    end

    // irq is registered: it equals DONE & IRQ_EN of the previous cycle
    reg exp_irq = 1'b0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (irq !== exp_irq) fail("irq does not follow DONE & IRQ_EN");
            exp_irq <= dut.done & dut.irq_en;
        end
    end

    // Program and run one transfer, wait for DONE, return the busy time in cycles
    integer t_start, t_busy;

    task run(input [31:0] s, input [31:0] d, input [15:0] n);
        integer guard;
        begin
            apb_write(SRC, s);
            apb_write(DST, d);
            apb_write(LEN, {16'h0, n});
            apb_write(CTRL, 32'h1);
            t_start = cycle;
            rd = 32'h1;
            guard = 0;
            while (rd[0] && guard < 20000) begin
                apb_read(STATUS);
                guard = guard + 1;
            end
            if (rd[0]) fail("DMA never finished");
            t_busy = cycle - t_start;
        end
    endtask

    // Forward word-by-word reference copy, stops at the first word that hits the error region
    integer copied;
    task ref_copy(input [31:0] s, input [31:0] d, input [15:0] n);
        integer w;
        reg stop;
        begin
            stop = 1'b0;
            copied = 0;
            for (w = 0; w < n; w = w + 1) begin
                if (!stop) begin
                    if ((s + 4*w) >> 28 == 4'hE || (d + 4*w) >> 28 == 4'hE)
                        stop = 1'b1;
                    else begin
                        refm[((d >> 2) + w) % WORDS] = refm[((s >> 2) + w) % WORDS];
                        copied = copied + 1;
                    end
                end
            end
        end
    endtask

    task check_mem(input [8*40-1:0] tag);
        integer w, bad;
        begin
            bad = 0;
            for (w = 0; w < WORDS; w = w + 1)
                if (mem[w] !== refm[w]) begin
                    if (bad < 3)
                        $display("      word %0d: mem %h, expected %h", w, mem[w], refm[w]);
                    bad = bad + 1;
                end
            if (bad != 0) fail(tag);
        end
    endtask

    integer s_w, d_w, n_w, n_before, n_err = 0, n_ovl = 0;
    reg [31:0] s_a, d_a;

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("n=%d", n_xfer)) ;
        seed0 = seed;
        for (i = 0; i < WORDS; i = i + 1) begin
            mem[i]  = $random(seed);
            refm[i] = mem[i];
        end
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // ---- 1. Reset values and registers ----
        apb_read(SRC);    if (rd !== 32'h0 || err_seen) fail("reset: SRC");
        apb_read(STATUS); if (rd !== 32'h0) fail("reset: STATUS");
        apb_read(CTRL);   if (rd !== 32'h0) fail("reset: CTRL");
        apb_write(SRC, 32'h1234_5677);
        apb_read(SRC);    if (rd !== 32'h1234_5674) fail("SRC keeps bits 31:2");
        apb_write(LEN, 32'hABCD_0123);
        apb_read(LEN);    if (rd !== 32'h0000_0123) fail("LEN keeps 16 bits");
        apb_write(CTRL, 32'h2);
        apb_read(CTRL);   if (rd !== 32'h2) fail("CTRL reads IRQ_EN");
        apb_write(CTRL, 32'h0);
        apb_read(12'h014); if (!err_seen || rd !== 32'h0) fail("offset 0x14 -> PSLVERR");
        apb_write(12'h006, 32'h1); if (!err_seen) fail("misaligned write -> PSLVERR");

        // ---- 2. LEN = 0: DONE at once, no bus traffic ----
        n_before = n_acc;
        run(32'h0000_0100, 32'h0000_0200, 16'd0);
        apb_read(STATUS);
        if (rd !== 32'h2) fail("LEN = 0 sets DONE only");
        if (n_acc != n_before) fail("LEN = 0 made bus requests");
        apb_write(STATUS, 32'h2);
        apb_read(STATUS); if (rd !== 32'h0) fail("STATUS write 1 clears DONE");

        // ---- 3. No stalls: 2 cycles per word ----
        stall_pct = 0; delay_max = 0;
        run(32'h0000_0400, 32'h0000_1000, 16'd64);
        ref_copy(32'h0000_0400, 32'h0000_1000, 16'd64);
        check_mem("copy without stalls");
        if (t_busy > 2 * 64 + 10) begin
            $display("      64 words took %0d cycles", t_busy);
            fail("one word must take 2 cycles without stalls");
        end

        // ---- 4. Writes while BUSY are ignored, IRQ_EN raises irq ----
        apb_write(CTRL, 32'h2);
        apb_write(SRC, 32'h0000_0800);
        apb_write(DST, 32'h0000_2000);
        apb_write(LEN, 32'd200);
        apb_write(CTRL, 32'h3);             // START | IRQ_EN
        apb_write(SRC, 32'h0000_0F00);      // Ignored while busy
        apb_write(LEN, 32'd5);              // Ignored
        apb_write(CTRL, 32'h1);             // Ignored (would also drop IRQ_EN)
        apb_read(SRC);   if (rd !== 32'h0000_0800) fail("SRC write while busy not ignored");
        apb_read(LEN);   if (rd !== 32'd200) fail("LEN write while busy not ignored");
        apb_read(CTRL);  if (rd !== 32'h2) fail("CTRL write while busy not ignored");
        rd = 32'h1;
        while (rd[0]) apb_read(STATUS);
        ref_copy(32'h0000_0800, 32'h0000_2000, 16'd200);
        check_mem("copy with writes while busy");
        repeat (2) @(posedge clk);
        if (irq !== 1'b1) fail("irq not set when DONE and IRQ_EN");
        apb_write(STATUS, 32'h2);
        repeat (2) @(posedge clk);
        if (irq !== 1'b0) fail("irq not cleared with DONE");
        apb_write(CTRL, 32'h0);

        // ---- 5. Bus errors stop the transfer ----
        stall_pct = 30; delay_max = 3;
        // Reads hit the 0xE... error region at word 4
        run(32'hDFFF_FFF0, 32'h0000_3000, 16'd10);
        ref_copy(32'hDFFF_FFF0, 32'h0000_3000, 16'd10);
        apb_read(STATUS);
        if (rd !== 32'h6) fail("read error: STATUS = ERR | DONE");
        check_mem("words before a read error are copied");
        apb_write(STATUS, 32'h4);
        apb_read(STATUS); if (rd !== 32'h2) fail("STATUS write 1 clears ERR only");
        // Writes hit the 0xE... error region at word 2
        run(32'h0000_0500, 32'hDFFF_FFF8, 16'd10);
        ref_copy(32'h0000_0500, 32'hDFFF_FFF8, 16'd10);
        apb_read(STATUS);
        if (rd !== 32'h6) fail("write error: STATUS = ERR | DONE");
        check_mem("words before a write error are copied");
        run(32'h0000_0600, 32'h0000_3100, 16'd4);   // START clears ERR
        ref_copy(32'h0000_0600, 32'h0000_3100, 16'd4);
        apb_read(STATUS);
        if (rd !== 32'h2) fail("START clears ERR");
        check_mem("copy after an error");

        // ---- 6. Random transfers with wait states, delays and overlapping ranges ----
        for (k = 0; k < n_xfer; k = k + 1) begin
            stall_pct = $unsigned($random(seed)) % 60;
            delay_max = $unsigned($random(seed)) % 4;
            n_w = 1 + $unsigned($random(seed)) % 40;
            s_w = $unsigned($random(seed)) % (WORDS - 64);
            if (($unsigned($random(seed)) % 4) == 0) begin
                d_w = s_w + ($unsigned($random(seed)) % 8) - 4;     // Overlap
                if (d_w < 0) d_w = 0;
                n_ovl = n_ovl + 1;
            end else
                d_w = $unsigned($random(seed)) % (WORDS - 64);
            s_a = s_w * 4;
            d_a = d_w * 4;
            run(s_a, d_a, n_w[15:0]);
            ref_copy(s_a, d_a, n_w[15:0]);
            apb_read(STATUS);
            if (rd !== 32'h2) fail("random: STATUS after transfer");
            apb_write(STATUS, 32'h2);
        end
        check_mem("random transfers");

        repeat (5) @(posedge clk);
        if (errors == 0)
            $display({"PASS: tb_dma_apb: %0d random transfers (%0d overlapping), errors, ",
                      "LEN = 0, busy writes, irq, 2 cycles per word (seed %0d)"},
                     n_xfer, n_ovl, seed0);
        else
            $display("FAIL: tb_dma_apb: %0d errors (seed %0d)", errors, seed0);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL: tb_dma_apb timeout");
        $finish;
    end

endmodule

`default_nettype wire
