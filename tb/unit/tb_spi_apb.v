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

        // ---- 7. Sampling Phase & Edge Alignment Verification ----
        // Leader feedback: Verify MOSI phase vs SCLK edges
        // Mode 0 (CPOL=0, CPHA=0): Data is driven on negedge, sampled on posedge.
        // Therefore, MOSI is ONLY allowed to change when SCLK is LOW.
        apb_write(A_CTRL, {16'd0, 8'd2, 5'd0, 1'b0, 1'b0, 1'b0}); // Set Mode 0
        
        fork
            // Thread 1: Transmit 0x55 (01010101) to force alternating bits and MOSI toggles
            begin
                apb_write(A_DATA, 32'h55);
                wait_busy();
            end
            
            // Thread 2: Strict Phase/Edge Monitor
            begin
                integer phase_errors;
                phase_errors = 0;
                
                // Monitor for the duration of the transfer
                // 0x55 (01010101) will cause MOSI to toggle exactly 7 times
                repeat(7) begin 
                    @(mosi); // Trigger exactly at the picosecond MOSI changes state
                    
                    // In Mode 0, if MOSI changes state while SCLK is HIGH (during the sampling window)
                    // it is a critical phase violation.
                    if (sclk === 1'b1) begin
                        phase_errors = phase_errors + 1;
                        $display("PHASE ERROR: MOSI changed while SCLK was HIGH at %0t", $time);
                    end
                end
                check(phase_errors == 0, "Edge Alignment: MOSI changes correctly only on driving edge");
            end
        join

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
            $display("PASS: spi_apb - APB R/W, CPOL/CPHA Modes 0-3, Sampling Phase, TX/RX Loopback, PSLVERR OK!");
        else
            $display("FAIL: spi_apb - %0d errors detected", errors);
            
        $finish;
    end
endmodule
