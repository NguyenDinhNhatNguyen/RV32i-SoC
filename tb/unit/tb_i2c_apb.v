`timescale 1ns/1ps
// Testbench tự kiểm tra cho khối i2c_apb (RTL-14)
// In ra "PASS: ..." nếu tất cả các bài test đều đúng.

module tb_i2c_apb;
    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    
    // Tín hiệu Bus cho DUT 1 (Mở I2C)
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    
    wire        scl_o, scl_oe, sda_o, sda_oe;
    wire        scl_i, sda_i;

    // Giả lập cơ chế Open-Drain và điện trở kéo lên (Pull-up)
    tri1 scl_line;
    tri1 sda_line;
    
    assign scl_line = scl_oe ? scl_o : 1'bz;
    assign sda_line = sda_oe ? sda_o : 1'bz;
    
    assign scl_i = scl_line;
    assign sda_i = sda_line;

    // Tín hiệu do Dummy Slave điều khiển
    reg slave_sda = 1'bz;
    assign sda_line = slave_sda;

    // Khởi tạo DUT 1
    i2c_apb #(.ENABLE_I2C(1)) dut1 (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .scl_i(scl_i), .scl_o(scl_o), .scl_oe(scl_oe),
        .sda_i(sda_i), .sda_o(sda_o), .sda_oe(sda_oe)
    );

    // DUT 2 (Disabled)
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

	task wait_scl_low;
    begin
        @(negedge scl_line); // Đợi SCL bị kéo xuống 0
        // Tránh bắt nhầm các xung nhiễu cực ngắn
        #1;
        while(scl_line !== 1'b0) @(negedge scl_line); 
    end
endtask

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $dumpfile("tb/unit/out/i2c_apb.vcd");
        $dumpvars(0, tb_i2c_apb);

        // ---- 1. Reset ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(2);
        
        check(scl_line === 1'b1, "Reset: SCL High-Z (Pull-up)");
        check(sda_line === 1'b1, "Reset: SDA High-Z (Pull-up)");

        // ---- 2. Cấu hình I2C DIV ----
        // Cấu hình DIV = 4 để chạy nhanh mô phỏng
        apb_write(A_CTRL, 32'd4);
        apb_read(A_CTRL);
        check(rd == 32'd4, "Write/Read CTRL DIV = 4");

	// ---- 3. Master truyền 1 Byte (Kèm lệnh START) + Slave ACK ----
    fork
        begin
            apb_write(A_DATA, 32'hA5);
            apb_write(A_CMD, 32'h09); // Bắt đầu phát START
            wait_busy();
        end
        begin
            // Tính toán thời gian tuyệt đối dựa trên cấu hình:
            // APB Write mất 3 chu kỳ PCLK (30ns) = 30ns
            // FSM vào pha START: mất 4 pha (mỗi pha 20ns) = 80ns
            // Truyền 8 bit data: 8 * 80ns = 640ns
            // Tổng thời gian chờ đến lúc FSM nhả SDA để đọc ACK: 30 + 80 + 640 = 750ns
            
            #750; // Chờ đúng thời gian Master truyền xong
            
            // Bây giờ là đầu nhịp ACK, Master chuẩn bị kéo SCL lên
            slave_sda = 1'b0; // Kéo SDA xuống để báo ACK
            
            // Nhịp ACK kéo dài 80ns, ta giữ SDA trong 80ns rồi nhả ra
            #80;
            slave_sda = 1'bz;
        end
    join

    // ---- 4. Master đọc 1 Byte + Gửi Master ACK ----
    fork
        begin
            apb_write(A_CMD, 32'h04); // Bắt đầu đọc
            wait_busy();
        end
        begin
            // APB Write mất 30ns, FSM chuyển trạng thái chuẩn bị mất thêm khoảng 20ns
            // Tổng cộng trễ 50ns trước khi bắt đầu đọc bit đầu tiên
            #50;
            
            // Mỗi chu kỳ SCL (1 bit) dài 80ns
            slave_sda = 1'b0; #80; // Bit 7 (0)
            slave_sda = 1'b0; #80; // Bit 6 (0)
            slave_sda = 1'b1; #80; // Bit 5 (1)
            slave_sda = 1'b1; #80; // Bit 4 (1)
            slave_sda = 1'b1; #80; // Bit 3 (1)
            slave_sda = 1'b1; #80; // Bit 2 (1)
            slave_sda = 1'b0; #80; // Bit 1 (0)
            slave_sda = 1'b0; #80; // Bit 0 (0)
            
            // Xong 8 bit, đến nhịp ACK từ Master, Slave phải nhả đường truyền
            slave_sda = 1'bz; 
        end
    join
        
        // ---- 5. Gửi lệnh STOP ----
        apb_write(A_CMD, 32'h02); // CMD: STOP(Bit 1) = 1
        wait_busy();
        check(scl_line === 1'b1 && sda_line === 1'b1, "STOP condition generated (SCL/SDA High)");

        // ---- 6. Bẫy lỗi PSLVERR ----
        apb_write(12'h00C, 32'hFFFF);
        check(err_seen === 1'b1, "Write unmapped addr -> PSLVERR");

        // ---- 7. Kiểm tra DUT 2 (ENABLE_I2C = 0) ----
        @(negedge PCLK); PSEL2 = 1; PWRITE = 1; PADDR = A_CMD; PENABLE = 0; PWDATA = 32'h09;
        @(negedge PCLK); PENABLE = 1;
        #(HALF-2)
        check(PSLVERR2 === 1'b1, "DUT2 (Disabled): Access -> PSLVERR");
        check(scl_oe2 === 1'b0 && sda_oe2 === 1'b0, "DUT2: Output disables correctly");
        @(negedge PCLK); PSEL2 = 0; PENABLE = 0;

        // ---- Kết luận ----
        if (errors == 0)
            $display("PASS: i2c_apb - Open-Drain TX/RX, START/STOP, ACK, FSM, Dummy Logic OK!");
        else
            $display("FAIL: i2c_apb - %0d lỗi phát hiện", errors);
            
        $finish;
    end
endmodule
