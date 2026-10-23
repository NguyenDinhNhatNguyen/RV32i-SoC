`timescale 1ns/1ps
// Testbench tu kiem tra cho gpio_apb. Cuoi cung in "PASS: ..." neu moi kiem tra dung.
module tb_gpio_apb;
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
    reg  [31:0] gpio_i = 32'd0;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;

    gpio_apb #(.W(32)) dut (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe(gpio_oe)
    );

    localparam HALF = 10;      // nua chu ky (ns): 50 MHz
    always #HALF PCLK = ~PCLK;

    localparam DATA_OUT = 12'h000, DATA_IN = 12'h004, DIR = 12'h008;

    integer errors = 0;
    reg [31:0] rd;
    reg        err_seen;
    integer    k, sel, seed;
    reg [31:0] wd;
    reg [11:0] ra;
    reg [31:0] m_out, m_dir;

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
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/gpio_apb.vcd");
        $dumpvars(0, tb_gpio_apb);

        // ---- 1. Reset ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        check(gpio_o == 32'd0,  "reset: gpio_o = 0");
        check(gpio_oe == 32'd0, "reset: gpio_oe = 0 (all input)");
        apb_read(DATA_OUT); check(rd == 32'd0 && !err_seen, "reset: DATA_OUT = 0");
        apb_read(DIR);      check(rd == 32'd0 && !err_seen, "reset: DIR = 0");

        // ---- 2. DATA_OUT ghi/doc ----
        apb_write(DATA_OUT, 32'hA5A51234);
        check(!err_seen, "write DATA_OUT: no PSLVERR");
        check(gpio_o == 32'hA5A51234, "gpio_o follows DATA_OUT");
        apb_read(DATA_OUT); check(rd == 32'hA5A51234, "DATA_OUT readback");
        apb_write(DATA_OUT, 32'h5A5ACDEF);
        check(gpio_o == 32'h5A5ACDEF, "gpio_o updates on 2nd write");

        // ---- 3. DIR ghi/doc, gpio_oe ----
        apb_write(DIR, 32'hFFFF0000);
        check(gpio_oe == 32'hFFFF0000, "gpio_oe follows DIR");
        apb_read(DIR); check(rd == 32'hFFFF0000, "DIR readback");
        apb_write(DIR, 32'h0000000F);
        check(gpio_oe == 32'h0000000F, "gpio_oe updates on 2nd write");

        // ---- 4. DATA_IN doc chan ngoai (qua dong bo 2 flop) ----
        gpio_i = 32'h12345678;
        wait_clks(4);
        apb_read(DATA_IN);
        check(rd == 32'h12345678 && !err_seen, "DATA_IN = gpio_i");
        gpio_i = 32'hCAFEF00D;
        wait_clks(4);
        apb_read(DATA_IN);
        check(rd == 32'hCAFEF00D, "DATA_IN tracks gpio_i");
        // DATA_IN doc duoc bat ke DIR
        apb_write(DIR, 32'hFFFFFFFF);
        apb_read(DATA_IN);
        check(rd == 32'hCAFEF00D, "DATA_IN independent of DIR");

        // ---- 5. Ghi vao DATA_IN (chi doc) -> PSLVERR, khong doi gi ----
        apb_write(DATA_OUT, 32'h0F0F0F0F);
        apb_write(DATA_IN, 32'hFFFFFFFF);
        check(err_seen == 1'b1, "write DATA_IN -> PSLVERR");
        apb_read(DATA_OUT);
        check(rd == 32'h0F0F0F0F, "DATA_OUT unchanged after DATA_IN write");
        apb_read(DATA_IN);
        check(rd == 32'hCAFEF00D, "DATA_IN unchanged after write");

        // ---- 6. Dia chi sai -> PSLVERR ----
        apb_write(12'h00C, 32'h1);
        check(err_seen == 1'b1, "write offset 0xC -> PSLVERR");
        apb_read(12'h00C);
        check(err_seen == 1'b1 && rd == 32'd0, "read offset 0xC -> PSLVERR, rdata 0");
        apb_write(12'h002, 32'h1);
        check(err_seen == 1'b1, "misaligned write -> PSLVERR");
        apb_read(DATA_OUT);
        check(rd == 32'h0F0F0F0F && !err_seen, "state unchanged after bad access");

        // ---- 7. Reset giua chung ----
        PRESETn = 0; wait_clks(2); PRESETn = 1; wait_clks(2);
        check(gpio_o == 32'd0 && gpio_oe == 32'd0, "async reset clears regs");

        // ---- 8. Ngau nhien: doi chieu mo hinh trong tb ----
        seed = 32'h0BADCAFE;
        apb_write(DATA_OUT, 32'd0); m_out = 32'd0;
        apb_write(DIR, 32'd0);      m_dir = 32'd0;
        for (k = 0; k < 400; k = k + 1) begin
            sel = $random(seed) & 7;
            wd  = $random(seed);
            case (sel)
                0: begin apb_write(DATA_OUT, wd); m_out = wd;
                         check(!err_seen && gpio_o == m_out, "rnd: write DATA_OUT"); end
                1: begin apb_write(DIR, wd); m_dir = wd;
                         check(!err_seen && gpio_oe == m_dir, "rnd: write DIR"); end
                2: begin apb_read(DATA_OUT);
                         check(!err_seen && rd == m_out, "rnd: read DATA_OUT"); end
                3: begin apb_read(DIR);
                         check(!err_seen && rd == m_dir, "rnd: read DIR"); end
                4: begin gpio_i = wd; wait_clks(3); apb_read(DATA_IN);
                         check(!err_seen && rd == wd, "rnd: read DATA_IN"); end
                5: begin apb_write(DATA_IN, wd);
                         check(err_seen, "rnd: write DATA_IN -> PSLVERR"); end
                6: begin ra = 12'h00C + {wd[7:0], 2'b00};
                         apb_write(ra, wd);
                         check(err_seen, "rnd: write unmapped -> PSLVERR");
                         apb_read(ra);
                         check(err_seen && rd == 32'd0, "rnd: read unmapped -> PSLVERR"); end
                7: begin ra = ((wd[10:8] % 3) * 4) + 1 + (wd[1:0] % 3);
                         apb_write(ra, wd);
                         check(err_seen, "rnd: misaligned write -> PSLVERR"); end
            endcase
        end
        apb_read(DATA_OUT); check(rd == m_out, "rnd end: DATA_OUT");
        apb_read(DIR);      check(rd == m_dir, "rnd end: DIR");
        check(gpio_o == m_out && gpio_oe == m_dir, "rnd end: pins");

        // ---- Ket qua ----
        if (errors == 0)
            $display("PASS: gpio_apb - DATA_OUT, DATA_IN, DIR, PSLVERR, 400 lenh ngau nhien dung");
        else
            $display("FAIL: gpio_apb - %0d loi", errors);
        $finish;
    end
endmodule
