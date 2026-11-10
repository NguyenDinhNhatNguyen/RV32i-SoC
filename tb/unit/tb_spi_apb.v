`timescale 1ns/1ps
// Self-checking testbench for spi_apb (RTL-13)
// Prints "PASS: ..." if all tests pass successfully.

module tb_spi_apb;
    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    
    // Bus signals for DUT 1 (Enabled SPI)
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        sclk;
    wire        mosi;
    wire        cs_n;
    
    // Loopback: MOSI tied directly to MISO for automated testing
    wire        miso = mosi; 

    // Instantiate DUT 1: Enable SPI feature
    spi_apb #(.ENABLE_SPI(1)) dut1 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    // Bus signals for DUT 2 (Disabled SPI - Dummy Logic)
    reg         PSEL2 = 1'b0;
    wire [31:0] PRDATA2;
    wire        PREADY2;
    wire        PSLVERR2;
    wire        sclk2, mosi2, cs_n2;

    // Instantiate DUT 2: Disable SPI feature to test area optimization
    spi_apb #(.ENABLE_SPI(0)) dut2 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL2), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA2),
        .PREADY(PREADY2), .PSLVERR(PSLVERR2),
        .sclk(sclk2), .mosi(mosi2), .miso(1'b0), .cs_n(cs_n2)
    );

    localparam HALF = 10; // 50 MHz
    always #HALF PCLK = ~PCLK;

    localparam A_DATA = 12'h000, A_STATUS = 12'h004, A_CTRL = 12'h008;

    integer errors = 0;
    reg [31:0] rd;
    reg        err_seen;
    
    task check;
        input        cond;
        input [8*60-1:0] tag;
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
        integer w;
        begin
            for (w = 0; w < n; w = w + 1) @(posedge PCLK);
        end
    endtask

    // Polling task to check BUSY flag
    task wait_busy;
        integer timeout;
        begin
            timeout = 0;
            rd = 32'd1;
            while (rd[0] == 1'b1 && timeout < 1000) begin
                apb_read(A_STATUS);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "Wait for BUSY=0 Timeout");
        end
    endtask

    // Edge monitor for every mode. A slave samples mosi on the leading sclk edge when
    // CPHA = 0 and on the trailing edge when CPHA = 1, so after the sampling edge sclk equals
    // ~(CPOL ^ CPHA). mosi must not change in the same time step as that edge (hold time).
    // The check waits 1 ns so every update of that time step has happened.
    realtime t_mosi = -1.0;
    realtime t_edge;
    integer  n_samp = 0;            // Sampling edges seen during transfers
    integer  n_hold = 0;            // mosi changed on a sampling edge
    // busy, CPOL, CPHA as they were before the PCLK edge that moves sclk (busy drops on the
    // last edge of a transfer)
    reg      mon_busy = 1'b0, mon_cpol = 1'b0, mon_cpha = 1'b0;
    always @(negedge PCLK) begin
        mon_busy = dut1.gen_spi.busy;
        mon_cpol = dut1.gen_spi.ctrl_cpol;
        mon_cpha = dut1.gen_spi.ctrl_cpha;
    end
    always @(mosi) t_mosi = $realtime;
    always @(sclk)
        if (mon_busy === 1'b1 && sclk === ~(mon_cpol ^ mon_cpha)) begin
            t_edge = $realtime;
            n_samp = n_samp + 1;
            #1;
            if (t_mosi == t_edge) begin
                n_hold = n_hold + 1;
                $display("FAIL: mosi changed on the sampling edge (CPOL=%0d CPHA=%0d, t=%0t)",
                         mon_cpol, mon_cpha, $time);
            end
        end

    initial begin
        #500000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/spi_apb.vcd");
        $dumpvars(0, tb_spi_apb);

        // ---- 1. Reset Initialization ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        
        check(sclk === 1'b0, "Reset: sclk = 0 (CPOL=0 default)");
        check(cs_n === 1'b1, "Reset: cs_n = 1 (Not selected)");
        apb_read(A_STATUS); check(rd === 32'd0 && !err_seen, "Reset: BUSY = 0");
        apb_read(A_CTRL);   check(rd === 32'd1 && !err_seen, "Reset: CTRL = 1 (cs_n=1)");

        // ---- 2. SPI Mode 0: DIV = 2, CPHA = 0, CPOL = 0, CS_N = 0 ----
        apb_write(A_CTRL, {16'd0, 8'd2, 5'd0, 1'b0, 1'b0, 1'b0});
        check(!err_seen, "Write CTRL Mode 0: OK");
        apb_read(A_CTRL);
        check(rd[15:8] == 8'd2 && rd[2] == 1'b0 && rd[0] == 1'b0, "Read CTRL: DIV=2, CS_N=0");
        check(cs_n === 1'b0, "SPI CS_N is asserted (0)");

        // ---- 3. Transfer byte 0xA5 in Mode 0 ----
        apb_write(A_DATA, 32'hA5);
        wait_busy();
        apb_read(A_DATA);
        check(rd === 32'hA5, "RX Data = 0xA5 (Loopback match Mode 0)");

        // ---- 4. SPI Mode 1: DIV = 2, CPHA = 1, CPOL = 0, CS_N = 0 ----
        apb_write(A_CTRL, {16'd0, 8'd2, 5'd0, 1'b1, 1'b0, 1'b0});
        wait_clks(2);
        check(sclk === 1'b0, "CPOL=0: sclk idles at 0 for Mode 1");
        
        apb_write(A_DATA, 32'h33);
        wait_busy();
        apb_read(A_DATA);
        check(rd === 32'h33, "RX Data = 0x33 (Loopback match Mode 1)");

        // ---- 5. SPI Mode 2: DIV = 2, CPHA = 0, CPOL = 1, CS_N = 0 ----
        apb_write(A_CTRL, {16'd0, 8'd2, 5'd0, 1'b0, 1'b1, 1'b0});
        wait_clks(2);
        check(sclk === 1'b1, "CPOL=1: sclk idles at 1 for Mode 2");
        
        apb_write(A_DATA, 32'hCC);
        wait_busy();
        apb_read(A_DATA);
        check(rd === 32'hCC, "RX Data = 0xCC (Loopback match Mode 2)");

        // ---- 6. SPI Mode 3: DIV = 1, CPHA = 1, CPOL = 1, CS_N = 0 ----
        apb_write(A_CTRL, {16'd0, 8'd1, 5'd0, 1'b1, 1'b1, 1'b0});
        wait_clks(2);
        check(sclk === 1'b1, "CPOL=1: sclk idles at 1 for Mode 3");
        
        apb_write(A_DATA, 32'h5A);
        wait_busy();
        apb_read(A_DATA);
        check(rd === 32'h5A, "RX Data = 0x5A (Loopback match Mode 3)");

        // ---- 7. Mode 0 with alternating bits, so mosi toggles on every bit ----
        apb_write(A_CTRL, {16'd0, 8'd2, 5'd0, 1'b0, 1'b0, 1'b0});
        apb_write(A_DATA, 32'h55);
        wait_busy();
        apb_read(A_DATA);
        check(rd === 32'h55, "RX Data = 0x55 (Loopback match Mode 0)");
        check(n_samp == 5 * 8, "Edge monitor: 8 sampling edges per transfer");
        check(n_hold == 0, "Edge monitor: mosi never changes on a sampling edge");

        // ---- 8. De-assert CS_N (End transmission) ----
        apb_write(A_CTRL, {16'd0, 8'd1, 5'd0, 1'b1, 1'b1, 1'b1});
        wait_clks(2);
        check(cs_n === 1'b1, "SPI CS_N is de-asserted (1)");

        // ---- 9. PSLVERR Trap (Unmapped address access) ----
        apb_write(12'h00C, 32'hFFFF);
        check(err_seen === 1'b1, "Write unmapped addr -> PSLVERR");
        apb_read(12'h00C);
        check(err_seen === 1'b1 && rd === 32'd0, "Read unmapped addr -> PSLVERR & 0");

        // ---- 10. Check Disabled Mode ENABLE_SPI = 0 (DUT 2) ----
        @(negedge PCLK); PSEL2 = 1; PWRITE = 0; PADDR = A_CTRL; PENABLE = 0;
        @(negedge PCLK); PENABLE = 1;
        #(HALF-2)
        check(PSLVERR2 === 1'b1, "DUT2 (Disabled): Access -> PSLVERR");
        check(cs_n2 === 1'b1, "DUT2 (Disabled): cs_n always 1");
        check(sclk2 === 1'b0, "DUT2 (Disabled): sclk always 0");
        @(negedge PCLK); PSEL2 = 0; PENABLE = 0;

        // ---- Conclusion ----
        if (errors == 0)
            $display("PASS: spi_apb - APB R/W, CPOL/CPHA modes 0-3, %0s",
                     "mosi hold on every sampling edge, TX/RX loopback, PSLVERR");
        else
            $display("FAIL: spi_apb - %0d errors detected", errors);
            
        $finish;
    end
endmodule
