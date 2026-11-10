`timescale 1ns/1ps
// tb_i2c_apb - self-checking testbench for i2c_apb (RTL-14). Prints "PASS: ..." when every
// check passes.
//   - Open-drain bus with pull-ups, the slave is tb/models/i2c_slave_model.v (address 0x50,
//     16-byte memory with a pointer).
//   - Write frame: START, address, pointer, data, STOP. The slave memory must hold the data.
//   - Read frame with a repeated START: the slave must see the second START before any STOP,
//     then two bytes are read (ACK, then NACK and STOP).
//   - Wrong address: the slave NACKs, STATUS.ack_in = 1.
//   - The slave counts START and STOP in the middle of a byte (sda moving while scl is high).
//   - PSLVERR on an unknown offset, and the ENABLE_I2C = 0 build.
// Registers: 0x0 DATA, 0x4 CMD (write: [0] START [1] STOP [2] READ [3] WRITE [4] ACK_OUT,
// 1 = NACK; read: [0] busy [1] ack_in), 0x8 CTRL (clock divider [15:0]).
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
    wire        scl_o, scl_oe, sda_o, sda_oe;

    // Open-drain lines with pull-ups
    tri1 scl_line;
    tri1 sda_line;
    wire slave_pull;
    assign scl_line = scl_oe ? scl_o : 1'bz;
    assign sda_line = sda_oe ? sda_o : 1'bz;
    assign sda_line = slave_pull ? 1'b0 : 1'bz;

    i2c_apb #(.ENABLE_I2C(1)) dut1 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .scl_i(scl_line), .scl_o(scl_o), .scl_oe(scl_oe),
        .sda_i(sda_line), .sda_o(sda_o), .sda_oe(sda_oe)
    );

    i2c_slave_model #(.ADDR(7'h50)) slave (
        .scl      (scl_line),
        .sda      (sda_line),
        .sda_pull (slave_pull)
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
    localparam C_START = 32'h01, C_STOP = 32'h02, C_READ = 32'h04, C_WRITE = 32'h08,
               C_NACK = 32'h10;

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

    // One byte: load DATA (unless it is a read), start the command, wait until it is done.
    // Leaves STATUS in rd.
    task xfer;
        input [7:0]  data;
        input [31:0] cmd;
        begin
            if (!cmd[2]) apb_write(A_DATA, {24'd0, data});
            apb_write(A_CMD, cmd);
            wait_busy();
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

        // ---- 1. Reset ----
        check(scl_line === 1'b1, "Reset: SCL released");
        check(sda_line === 1'b1, "Reset: SDA released");
        apb_read(A_CMD);  check(rd === 32'd2 && !err_seen, "Reset: STATUS busy = 0, ack_in = 1");
        apb_read(A_CTRL); check(rd === 32'd0, "Reset: CTRL = 0");

        // ---- 2. Clock divider ----
        apb_write(A_CTRL, 32'd4);
        apb_read(A_CTRL); check(rd === 32'd4, "CTRL reads back 4");

        // ---- 3. Write frame: START, 0xA0, pointer 3, 0x5C, STOP ----
        apb_write(A_DATA, 32'hA0);
        apb_write(A_CMD, C_START | C_WRITE);
        apb_read(A_CMD);  check(rd[0] === 1'b1, "STATUS busy = 1 right after CMD");
        wait_busy();
        check(rd[1] === 1'b0, "Write: address ACK");
        xfer(8'h03, C_WRITE);           check(rd[1] === 1'b0, "Write: pointer ACK");
        xfer(8'h5C, C_WRITE | C_STOP);  check(rd[1] === 1'b0, "Write: data ACK");
        check(slave.mem[3] === 8'h5C, "Slave memory[3] = 0x5C");
        check(slave.n_start == 1 && slave.n_stop == 1, "Write frame: 1 START, 1 STOP");
        check(scl_line === 1'b1 && sda_line === 1'b1, "Bus released after STOP");

        // ---- 4. Read frame with a repeated START ----
        xfer(8'hA0, C_START | C_WRITE); check(rd[1] === 1'b0, "Read: address (W) ACK");
        xfer(8'h03, C_WRITE);           check(rd[1] === 1'b0, "Read: pointer ACK");
        xfer(8'hA1, C_START | C_WRITE); check(rd[1] === 1'b0, "Read: address (R) ACK");
        check(slave.n_start == 3 && slave.n_stop == 1, "Repeated START seen before STOP");
        xfer(8'h00, C_READ);
        apb_read(A_DATA); check(rd === 32'h5C, "Read byte 1 = 0x5C");
        check(slave.last_ack === 1'b0, "Master ACKs byte 1");
        xfer(8'h00, C_READ | C_NACK | C_STOP);
        apb_read(A_DATA); check(rd === 32'hA4, "Read byte 2 = 0xA4 (memory[4])");
        check(slave.last_ack === 1'b1, "Master NACKs byte 2");
        check(slave.n_stop == 2, "Read frame ends with STOP");

        // ---- 5. Wrong address ----
        xfer(8'hEE, C_START | C_WRITE | C_STOP);
        check(rd[1] === 1'b1, "Address 0x77: NACK, ack_in = 1");
        check(slave.n_start == 4 && slave.n_stop == 3, "Wrong address frame: START and STOP");

        // ---- 6. Bus protocol ----
        check(slave.n_err == 0, "No START or STOP in the middle of a byte");
        check(slave.n_bytes == 9, "Slave saw 9 bytes");

        // ---- 7. Unknown offset ----
        apb_write(12'h00C, 32'hFFFF);
        check(err_seen === 1'b1, "Write unmapped addr -> PSLVERR");
        apb_read(12'h00C);
        check(err_seen === 1'b1 && rd === 32'd0, "Read unmapped addr -> PSLVERR and 0");

        // ---- 8. ENABLE_I2C = 0 ----
        @(negedge PCLK); PSEL2 = 1; PWRITE = 1; PADDR = A_CMD; PENABLE = 0; PWDATA = 32'h09;
        @(negedge PCLK); PENABLE = 1;
        #(HALF-2)
        check(PSLVERR2 === 1'b1, "DUT2 (Disabled): Access -> PSLVERR");
        check(scl_oe2 === 1'b0 && sda_oe2 === 1'b0, "DUT2: Outputs released");
        @(negedge PCLK); PSEL2 = 0; PENABLE = 0;

        if (errors == 0)
            $display("PASS: i2c_apb - write frame, repeated START read, ACK/NACK, %0s, %0d bytes",
                     "wrong address, PSLVERR, ENABLE_I2C=0", slave.n_bytes);
        else
            $display("FAIL: i2c_apb - %0d errors detected", errors);

        $finish;
    end
endmodule
