`timescale 1ns/1ps
// Self-checking testbench for pwm_apb (RTL-13).
// Prints "PASS: ..." if all tests pass successfully.

module tb_pwm_apb;
    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    
    // Bus signals for DUT 1 (Enabled PWM)
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        pwm_out;

    // Bus signals for DUT 2 (Disabled PWM - Dummy Logic)
    reg         PSEL2 = 1'b0;
    wire [31:0] PRDATA2;
    wire        PREADY2;
    wire        PSLVERR2;
    wire        pwm_out2;

    // Instantiate DUT 1: Enable PWM feature
    pwm_apb #(.ENABLE_PWM(1)) dut1 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR), .pwm_out(pwm_out)
    );

    // Instantiate DUT 2: Disable PWM feature to test area optimization
    pwm_apb #(.ENABLE_PWM(0)) dut2 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL2), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA2),
        .PREADY(PREADY2), .PSLVERR(PSLVERR2), .pwm_out(pwm_out2)
    );

    localparam HALF = 10;      // 50 MHz (20ns/cycle)
    always #HALF PCLK = ~PCLK;

    localparam A_PERIOD = 12'h000, A_DUTY = 12'h004, A_CTRL = 12'h008;

    integer errors = 0;
    reg [31:0] rd;
    reg        err_seen;
    integer    i; // Loop counter of the cycle-exact check

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

    initial begin
        #500000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/pwm_apb.vcd");
        $dumpvars(0, tb_pwm_apb);

        // ---- 1. Reset ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        
        check(pwm_out === 1'b0, "Reset: pwm_out = 0");
        apb_read(A_PERIOD); check(rd === 32'd0 && !err_seen, "Reset: PERIOD = 0");
        apb_read(A_DUTY);   check(rd === 32'd0 && !err_seen, "Reset: DUTY = 0");
        apb_read(A_CTRL);   check(rd === 32'd0 && !err_seen, "Reset: CTRL = 0 (Disabled)");

        // ---- 2. Read/Write Registers (PWM not enabled yet) ----
        apb_write(A_PERIOD, 32'd10);
        check(!err_seen, "Write PERIOD: OK");
        apb_write(A_DUTY, 32'd4);
        check(!err_seen, "Write DUTY: OK");
        
        apb_read(A_PERIOD); check(rd === 32'd10, "Read PERIOD: 10");
        apb_read(A_DUTY);   check(rd === 32'd4,  "Read DUTY: 4");
        
        wait_clks(15);
        check(pwm_out === 1'b0, "PWM disabled: pwm_out keeps 0");

        // ---- 3. Measure PWM Output (Period = 10, Duty = 4) ----
        apb_write(A_CTRL, 32'd1); // Enable PWM
        
        // Wait for the first rising edge of the PWM output
        @(posedge pwm_out);
        
        // Move to the middle of the cycle (negedge PCLK)
        // so sampling never races with the clock edge
        #(HALF);
        
        // Check the output on 10 cycles in a row
        for (i = 0; i < 10; i = i + 1) begin
            if (i < 4) begin
                check(pwm_out === 1'b1, "PWM Cycle High (Duty)");
            end else begin
                check(pwm_out === 1'b0, "PWM Cycle Low");
            end
            // Go to the middle of the next cycle
            #(HALF*2); 
        end

        // ---- 4. Check Behavior when Duty = 0 ----
        apb_write(A_DUTY, 32'd0);
        wait_clks(20);
        check(pwm_out === 1'b0, "PWM with DUTY=0: Always LOW");

        // ---- 5. Check Behavior when Duty >= Period ----
        apb_write(A_DUTY, 32'd20); // Duty (20) > Period (10)
        wait_clks(2); // Wait to cross edge
        wait_clks(20);
        check(pwm_out === 1'b1, "PWM with DUTY >= PERIOD: Always HIGH");

        // ---- 6. Memory Access Error (PSLVERR) ----
        apb_write(12'h00C, 32'hFFFF);
        check(err_seen === 1'b1, "Write to unmapped address -> PSLVERR");
        apb_read(12'h00C);
        check(err_seen === 1'b1 && rd === 32'd0, "Read unmapped address -> PSLVERR & 0");

        // ---- 7. Check ENABLE_PWM = 0 Mode (DUT 2) ----
        @(negedge PCLK); PSEL2 = 1; PWRITE = 0; PADDR = A_PERIOD; PENABLE = 0;
        @(negedge PCLK); PENABLE = 1;
        #(HALF-2) 
        check(PSLVERR2 === 1'b1, "DUT2 (No PWM): Any access -> PSLVERR");
        check(PRDATA2 === 32'd0, "DUT2 (No PWM): Read data -> 0");
        check(pwm_out2 === 1'b0, "DUT2 (No PWM): Output always 0");
        @(negedge PCLK); PSEL2 = 0; PENABLE = 0;

        // ---- Conclusion ----
        if (errors == 0)
            $display("PASS: pwm_apb - APB R/W, Period, Duty, Limits, PSLVERR, Dummy Logic OK!");
        else
            $display("FAIL: pwm_apb - %0d error", errors);
            
        $finish;
    end
endmodule
