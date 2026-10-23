
`timescale 1ns/1ps
// Testbench tu kiem tra cho timer_apb. Cuoi cung in "PASS: ..." neu moi kiem tra dung.
module tb_timer_apb;
    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        irq_timer;
    wire        irq_software;

    timer_apb dut (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .irq_timer(irq_timer), .irq_software(irq_software)
    );

    localparam HALF = 10;      // nua chu ky (ns): 50 MHz
    always #HALF PCLK = ~PCLK;

    localparam MTIME_LO = 12'h000, MTIME_HI = 12'h004,
               CMP_LO   = 12'h008, CMP_HI   = 12'h00C,
               MSIP     = 12'h010;

    integer errors = 0;
    integer cyc;
    reg [31:0] rd;
    reg [31:0] r1, r2;
    reg        err_seen;
    integer    k, sel, seed;
    reg [31:0] wd;
    reg [11:0] ra;
    reg [31:0] m_cmp_lo, m_cmp_hi;
    reg        m_msip;

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

    task wait_clks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge PCLK);
        end
    endtask

    initial begin
        #4000000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/timer_apb.vcd");
        $dumpvars(0, tb_timer_apb);

        // ---- 1. Reset ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        check(irq_timer == 1'b0,    "reset: irq_timer = 0");
        check(irq_software == 1'b0, "reset: irq_software = 0");
        apb_read(CMP_LO);  check(rd == 32'hFFFFFFFF && !err_seen, "reset: mtimecmp_lo = FFFFFFFF");
        apb_read(CMP_HI);  check(rd == 32'hFFFFFFFF && !err_seen, "reset: mtimecmp_hi = FFFFFFFF");
        apb_read(MSIP);    check(rd == 32'd0 && !err_seen,        "reset: msip = 0");
        apb_read(MTIME_HI);check(rd == 32'd0,                     "reset: mtime_hi = 0");

        // ---- 2. mtime tang moi chu ky ----
        apb_write(MTIME_HI, 32'd0);
        apb_write(MTIME_LO, 32'd0);
        check(!err_seen, "write mtime: no PSLVERR");
        apb_read(MTIME_LO); r1 = rd;
        wait_clks(10);
        apb_read(MTIME_LO); r2 = rd;
        check(r2 > r1,           "mtime increases");
        check((r2 - r1) >= 10 && (r2 - r1) <= 14, "mtime step ~ elapsed clks");

        // ---- 3. Ngat khi mtime >= mtimecmp ----
        apb_write(CMP_HI, 32'hFFFFFFFF);
        apb_write(MTIME_HI, 32'd0);
        apb_write(MTIME_LO, 32'd0);
        apb_write(CMP_LO, 32'd100);
        apb_write(CMP_HI, 32'd0);                 // cmp = 100
        check(irq_timer == 1'b0, "irq low before mtime reaches cmp");
        cyc = 0;
        while (!irq_timer && cyc < 2000) begin @(posedge PCLK); cyc = cyc + 1; end
        check(irq_timer == 1'b1, "irq rises when mtime >= cmp");
        apb_read(MTIME_LO);
        check(rd >= 100 && rd < 130, "irq rises at mtime ~ cmp");

        // ---- 4. Xoa ngat bang cach tang mtimecmp ----
        apb_write(CMP_LO, 32'hFFFFFFFF);          // cmp = 0x0_FFFFFFFF
        wait_clks(3);
        check(irq_timer == 1'b0, "irq clears after raising cmp");

        // ---- 5. Tran qua 32 bit sang mtime_hi ----
        apb_write(CMP_HI, 32'hFFFFFFFF);
        apb_write(MTIME_HI, 32'd0);
        apb_write(MTIME_LO, 32'hFFFFFFF0);
        wait_clks(60);
        apb_read(MTIME_HI);
        check(rd == 32'd1, "carry: mtime_hi = 1 after wrap");
        apb_read(MTIME_LO);
        check(rd < 32'd100, "carry: mtime_lo small after wrap");

        // ---- 6. So sanh dung 64 bit (word cao) ----
        apb_write(CMP_HI, 32'hFFFFFFFF);
        apb_write(CMP_LO, 32'd0);
        apb_write(CMP_HI, 32'd1);                 // cmp = {1, 0}
        apb_write(MTIME_HI, 32'd0);
        apb_write(MTIME_LO, 32'hFFFFFF00);        // mtime = {0, FFFFFF00}
        wait_clks(20);
        check(irq_timer == 1'b0, "64-bit cmp: lo large but hi smaller -> no irq");
        cyc = 0;
        while (!irq_timer && cyc < 2000) begin @(posedge PCLK); cyc = cyc + 1; end
        check(irq_timer == 1'b1, "64-bit cmp: irq after hi word reaches 1");
        apb_write(CMP_HI, 32'hFFFFFFFF);
        wait_clks(3);
        check(irq_timer == 1'b0, "irq cleared again");

        // ---- 7. MSIP ----
        apb_write(MSIP, 32'd1);
        check(irq_software == 1'b1, "msip=1 -> irq_software");
        apb_read(MSIP); check(rd == 32'd1, "msip readback");
        apb_write(MSIP, 32'hFFFFFFFE);            // bit0 = 0
        check(irq_software == 1'b0, "msip=0 (only bit0 used)");

        // ---- 8. Truy cap sai -> PSLVERR, khong doi trang thai ----
        apb_write(MSIP, 32'd1);
        apb_write(12'h014, 32'hDEADBEEF);
        check(err_seen == 1'b1, "write offset 0x14 -> PSLVERR");
        apb_read(12'h014);
        check(err_seen == 1'b1 && rd == 32'd0, "read offset 0x14 -> PSLVERR, rdata 0");
        apb_write(12'h002, 32'h12345678);
        check(err_seen == 1'b1, "misaligned write -> PSLVERR");
        apb_read(MSIP);
        check(rd == 32'd1 && !err_seen, "state unchanged after bad access");
        apb_read(CMP_HI);
        check(rd == 32'hFFFFFFFF, "mtimecmp_hi unchanged after bad access");

        // ---- 9. Ghi mtime_lo dung luc nua thap = FFFFFFFF: ghi thang, khong carry ----
        apb_write(MTIME_HI, 32'd5);
        apb_write(MTIME_LO, 32'hFFFFFFFD);   // 3 chu ky/lan ghi: den lan ghi sau lo = FFFFFFFF
        apb_write(MTIME_LO, 32'h00000010);        // luc nay mtime_lo dang la FFFFFFFF
        apb_read(MTIME_HI);
        check(rd == 32'd5, "write lo at wrap: no carry into hi");
        apb_read(MTIME_LO);
        check(rd >= 32'h10 && rd < 32'h30, "write lo at wrap: lo takes new value");

        // ---- 10. Ngau nhien: mtimecmp/msip + truy cap sai, doi chieu mo hinh trong tb ----
        seed = 32'h5EED1234;
        apb_write(CMP_HI, 32'hFFFFFFFF); m_cmp_hi = 32'hFFFFFFFF;
        apb_write(CMP_LO, 32'hFFFFFFFF); m_cmp_lo = 32'hFFFFFFFF;
        apb_write(MSIP, 32'd0);          m_msip   = 1'b0;
        for (k = 0; k < 400; k = k + 1) begin
            sel = $random(seed) & 7;
            wd  = $random(seed);
            case (sel)
                0: begin apb_write(CMP_LO, wd); m_cmp_lo = wd;
                         check(!err_seen, "rnd: write cmp_lo ok"); end
                1: begin apb_write(CMP_HI, wd); m_cmp_hi = wd;
                         check(!err_seen, "rnd: write cmp_hi ok"); end
                2: begin apb_write(MSIP, wd);   m_msip = wd[0];
                         check(!err_seen && irq_software == m_msip, "rnd: write msip"); end
                3: begin apb_read(CMP_LO);
                         check(!err_seen && rd == m_cmp_lo, "rnd: read cmp_lo"); end
                4: begin apb_read(CMP_HI);
                         check(!err_seen && rd == m_cmp_hi, "rnd: read cmp_hi"); end
                5: begin apb_read(MSIP);
                         check(!err_seen && rd == {31'd0, m_msip}, "rnd: read msip"); end
                6: begin ra = 12'h014 + {wd[7:0], 2'b00};
                         apb_write(ra, wd);
                         check(err_seen, "rnd: write unmapped -> PSLVERR");
                         apb_read(ra);
                         check(err_seen && rd == 32'd0, "rnd: read unmapped -> PSLVERR"); end
                7: begin ra = ((wd[10:8] % 5) * 4) + 1 + (wd[1:0] % 3);
                         apb_write(ra, wd);
                         check(err_seen, "rnd: misaligned write -> PSLVERR"); end
            endcase
        end
        apb_read(CMP_LO); check(rd == m_cmp_lo, "rnd end: cmp_lo");
        apb_read(CMP_HI); check(rd == m_cmp_hi, "rnd end: cmp_hi");
        apb_read(MSIP);   check(rd == {31'd0, m_msip}, "rnd end: msip");

        // ---- Ket qua ----
        if (errors == 0)
            $display("PASS: timer_apb - mtime, mtimecmp, irq_timer, MSIP, PSLVERR, 400 lenh ngau nhien dung");
        else
            $display("FAIL: timer_apb - %0d loi", errors);
        $finish;
    end
endmodule