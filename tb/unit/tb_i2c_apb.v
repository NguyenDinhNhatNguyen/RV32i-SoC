`timescale 1ns/1ps
module tb_i2c_apb;
    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire        scl_o, scl_oe, sda_o, sda_oe, scl_i, sda_i;

    tri1 scl_line;
    tri1 sda_line;
    assign scl_line = scl_oe ? scl_o : 1'bz;
    assign sda_line = sda_oe ? sda_o : 1'bz;
    assign scl_i = scl_line;
    assign sda_i = sda_line;

    reg slave_sda = 1'bz;
    assign sda_line = slave_sda;

    i2c_apb #(.ENABLE_I2C(1)) dut1 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .scl_i(scl_i), .scl_o(scl_o), .scl_oe(scl_oe),
        .sda_i(sda_i), .sda_o(sda_o), .sda_oe(sda_oe)
    );

    reg         PSEL2 = 1'b0;
    wire [31:0] PRDATA2;
    wire        PSLVERR2;
    wire        scl_o2, scl_oe2, sda_o2, sda_oe2;

    i2c_apb #(.ENABLE_I2C(0)) dut2 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL2), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA2),
        .PREADY(), .PSLVERR(PSLVERR2),
        .scl_i(1'b1), .scl_o(scl_o2), .scl_oe(scl_oe2),
        .sda_i(1'b1), .sda_o(sda_o2), .sda_oe(sda_oe2)
    );

    localparam HALF = 10;
    always #HALF PCLK = ~PCLK;

    localparam A_DATA = 12'h000, A_CMD = 12'h004, A_CTRL = 12'h008;

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

    task wait_busy;
        integer timeout;
        begin
            timeout = 0;
            rd = 32'd1;
            while (rd[0] == 1'b1 && timeout < 5000) begin
                apb_read(A_CMD);
                timeout = timeout + 1;
            end
            check(timeout < 5000, "Wait for BUSY=0 Timeout");
        end
    endtask

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/i2c_apb.vcd");
        $dumpvars(0, tb_i2c_apb);

        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        
        check(scl_line === 1'b1, "Reset: SCL High-Z");
        check(sda_line === 1'b1, "Reset: SDA High-Z");

        apb_write(A_CTRL, 32'd4);

        // ---- 3. Master transmit 1 Byte + Slave ACK ----
        fork
            begin
                apb_write(A_DATA, 32'hA5); 
                apb_write(A_CMD, 32'h09);  
                wait_busy();
            end
            begin
                @(negedge scl_line); // START
                repeat(8) @(negedge scl_line); // 8 Data bits
                slave_sda = 1'b0;              // ACK
                @(negedge scl_line);           
                slave_sda = 1'bz;
            end
        join
        
        apb_read(A_CMD);
        check(rd[1] == 1'b0, "TX: Slave ACK_IN is 0 (ACK received)");

        // ---- 4. Master Reads 1 Byte + Sends Master ACK ----
        fork
            begin
                apb_write(A_CMD, 32'h04); 
                wait_busy();
            end
            begin
                slave_sda = 1'b0; // Bit 7
                @(negedge scl_line); slave_sda = 1'b0; // Bit 6
                @(negedge scl_line); slave_sda = 1'b1; // Bit 5
                @(negedge scl_line); slave_sda = 1'b1; // Bit 4
                @(negedge scl_line); slave_sda = 1'b1; // Bit 3
                @(negedge scl_line); slave_sda = 1'b1; // Bit 2
                @(negedge scl_line); slave_sda = 1'b0; // Bit 1
                @(negedge scl_line); slave_sda = 1'b0; // Bit 0
                @(negedge scl_line); slave_sda = 1'bz; // Release SDA
            end
        join
        
        apb_read(A_DATA);
        check(rd == 32'h3C, "RX: Data read matches Slave (0x3C)");
        
        // ---- 5. Send STOP command ----
        apb_write(A_CMD, 32'h02); 
        wait_busy();
        check(scl_line === 1'b1 && sda_line === 1'b1, "STOP condition generated (SCL/SDA High)");

        // ---- 6. Memory Access Error ----
        apb_write(12'h00C, 32'hFFFF);
        check(err_seen === 1'b1, "Write unmapped addr -> PSLVERR");

        // ---- 7. Check Disabled Mode ENABLE_I2C = 0 ----
        @(negedge PCLK); PSEL2 = 1; PWRITE = 1; PADDR = A_CMD; PENABLE = 0; PWDATA = 32'h09;
        @(negedge PCLK); PENABLE = 1;
        #(HALF-2)
        check(PSLVERR2 === 1'b1, "DUT2 (Disabled): Access -> PSLVERR");
        check(scl_oe2 === 1'b0 && sda_oe2 === 1'b0, "DUT2: Output disables correctly");
        @(negedge PCLK); PSEL2 = 0; PENABLE = 0;

        if (errors == 0)
            $display("PASS: i2c_apb - Open-Drain TX/RX, START/STOP, ACK, FSM, Dummy Logic OK!");
        else
            $display("FAIL: i2c_apb - %0d lỗi phát hiện", errors);
            
        $finish;
    end
endmodule
