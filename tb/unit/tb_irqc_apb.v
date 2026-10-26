`timescale 1ns/1ps
// Self-checking testbench for irqc_apb. Prints "PASS: ..." at the end if every check passes.
module tb_irqc_apb;
    localparam N = 5;

    reg          PCLK = 1'b0;
    reg          PRESETn = 1'b0;
    reg          PSEL = 1'b0;
    reg          PENABLE = 1'b0;
    reg          PWRITE = 1'b0;
    reg  [11:0]  PADDR = 12'd0;
    reg  [31:0]  PWDATA = 32'd0;
    wire [31:0]  PRDATA;
    wire         PREADY;
    wire         PSLVERR;
    reg  [N-1:0] irq_src = {N{1'b0}};
    wire         irq;

    irqc_apb #(.N(N)) dut (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .irq_src(irq_src), .irq(irq)
    );

    localparam HALF = 10;      // Half period (ns): 50 MHz
    always #HALF PCLK = ~PCLK;

    localparam PENDING = 12'h000, ENABLE = 12'h004;
    localparam [31:0] MASK = (32'd1 << N) - 1;

    integer      errors = 0;
    reg  [31:0]  rd;
    reg          err_seen;
    integer      k, sel, seed;
    reg  [31:0]  wd;
    reg  [11:0]  ra;
    reg  [N-1:0] m_en;

    task check;
        input        cond;
        input [8*40-1:0] tag;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s (t=%0t)", tag, $time);
            end
        end
    endtask

    task apb_write;
        input [11:0] a;
        input [31:0] d;
        begin
            @(negedge PCLK); PSEL = 1; PWRITE = 1; PADDR = a; PWDATA = d; PENABLE = 0;
            @(negedge PCLK); PENABLE = 1;
            #(HALF-2) err_seen = PSLVERR;
            @(negedge PCLK); PSEL = 0; PENABLE = 0; PWRITE = 0;
        end
    endtask

    task apb_read;
        input [11:0] a;
        begin
            @(negedge PCLK); PSEL = 1; PWRITE = 0; PADDR = a; PENABLE = 0;
            @(negedge PCLK); PENABLE = 1;
            #(HALF-2) rd = PRDATA; err_seen = PSLVERR;
            @(negedge PCLK); PSEL = 0; PENABLE = 0;
        end
    endtask

    // Ends on the next falling edge, so source changes and irq checks never race the DUT
    task wait_clks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge PCLK);
            @(negedge PCLK);
        end
    endtask

    // irq is registered: it must equal |(irq_src & enable) from the previous cycle
    reg exp_irq = 1'b0;
    always @(posedge PCLK) begin
        if (PRESETn) begin
            if (irq !== exp_irq) begin
                errors = errors + 1;
                $display("FAIL: irq = %b, expected %b (t=%0t)", irq, exp_irq, $time);
            end
            exp_irq <= |(irq_src & dut.enable);
        end else
            exp_irq <= 1'b0;
    end

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/irqc_apb.vcd");
        $dumpvars(0, tb_irqc_apb);

        // ---- 1. Reset ----
        irq_src = {N{1'b1}};
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        check(irq == 1'b0, "reset: irq = 0 with all sources high");
        apb_read(ENABLE);  check(rd == 32'd0 && !err_seen, "reset: ENABLE = 0");
        apb_read(PENDING); check(rd == MASK && !err_seen, "PENDING = sources even when disabled");

        // ---- 2. ENABLE write/read, only N bits kept ----
        apb_write(ENABLE, 32'hFFFF_FFFF);
        check(!err_seen, "write ENABLE: no PSLVERR");
        apb_read(ENABLE); check(rd == MASK, "ENABLE keeps N bits");
        apb_write(ENABLE, 32'h0000_0005);
        apb_read(ENABLE); check(rd == 32'h5, "ENABLE readback");

        // ---- 3. PENDING follows the source level, irq = |(PENDING & ENABLE) ----
        irq_src = 5'b00010;
        wait_clks(2);
        apb_read(PENDING); check(rd == 32'h2, "PENDING = irq_src");
        check(irq == 1'b0, "disabled source does not raise irq");
        irq_src = 5'b00110;
        wait_clks(2);
        check(irq == 1'b1, "enabled source raises irq");
        irq_src = 5'b00010;
        wait_clks(2);
        check(irq == 1'b0, "irq drops when the source drops (no latch)");
        apb_write(ENABLE, 32'h0000_0002);
        wait_clks(1);
        check(irq == 1'b1, "enabling a high source raises irq");
        apb_write(ENABLE, 32'h0);
        wait_clks(1);
        check(irq == 1'b0, "disabling the source drops irq");

        // ---- 4. Write to PENDING (read only) -> PSLVERR, nothing changes ----
        apb_write(ENABLE, 32'h0000_0013);
        apb_write(PENDING, 32'hFFFF_FFFF);
        check(err_seen == 1'b1, "write PENDING -> PSLVERR");
        apb_read(ENABLE);  check(rd == 32'h13, "ENABLE unchanged after PENDING write");
        apb_read(PENDING); check(rd == 32'h2, "PENDING unchanged after write");

        // ---- 5. Bad address -> PSLVERR ----
        apb_write(12'h008, 32'h1);
        check(err_seen == 1'b1, "write offset 0x8 -> PSLVERR");
        apb_read(12'h008);
        check(err_seen == 1'b1 && rd == 32'd0, "read offset 0x8 -> PSLVERR, rdata 0");
        apb_write(12'h006, 32'h1);
        check(err_seen == 1'b1, "misaligned write -> PSLVERR");
        apb_read(ENABLE);
        check(rd == 32'h13 && !err_seen, "state unchanged after bad access");

        // ---- 6. Reset in the middle ----
        PRESETn = 0; wait_clks(2); PRESETn = 1; wait_clks(2);
        apb_read(ENABLE); check(rd == 32'd0, "async reset clears ENABLE");

        // ---- 7. Random: compare with the model inside the tb, irq checked every cycle ----
        seed = 32'h1C0FFEE1;
        m_en = {N{1'b0}};
        for (k = 0; k < 400; k = k + 1) begin
            sel = $random(seed) & 7;
            wd  = $random(seed);
            case (sel)
                0, 1: begin apb_write(ENABLE, wd); m_en = wd[N-1:0];
                            check(!err_seen, "rnd: write ENABLE"); end
                2:    begin apb_read(ENABLE);
                            check(!err_seen && rd == {{(32-N){1'b0}}, m_en},
                                  "rnd: read ENABLE"); end
                3:    begin apb_read(PENDING);
                            check(!err_seen && rd == {{(32-N){1'b0}}, irq_src},
                                  "rnd: read PENDING"); end
                4, 5: begin irq_src = wd[N-1:0]; wait_clks(wd[9:8]); end
                6:    begin apb_write(PENDING, wd);
                            check(err_seen, "rnd: write PENDING -> PSLVERR"); end
                7:    begin ra = 12'h008 + {wd[7:0], 2'b00};
                            apb_write(ra, wd);
                            check(err_seen, "rnd: write unmapped -> PSLVERR");
                            apb_read(ra);
                            check(err_seen && rd == 32'd0, "rnd: read unmapped -> PSLVERR"); end
            endcase
        end
        apb_read(ENABLE); check(rd == {{(32-N){1'b0}}, m_en}, "rnd end: ENABLE");

        // ---- Result ----
        if (errors == 0)
            $display("PASS: irqc_apb - PENDING, ENABLE, irq, PSLVERR, 400 random commands correct");
        else
            $display("FAIL: irqc_apb - %0d errors", errors);
        $finish;
    end
endmodule
