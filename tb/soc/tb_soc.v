`timescale 1ns/1ps
`default_nettype none
// tb_soc - testbench mức SoC cho soc_top (RTL-09). Chỉ nhìn chân của chip và
// đọc tín hiệu bên trong bằng tham chiếu phân cấp để kết luận.
//
// Trước khi chạy chương trình, kiểm bộ đồng bộ reset:
//   - nhả rst_n giữa chu kỳ: rst_n_sync lên 1 đúng ở cạnh lên thứ hai
//   - kéo rst_n xuống giữa chu kỳ: rst_n_sync xuống 0 ngay, không chờ clock
// Ảnh bộ nhớ (elf2hex.py, 16 KB mỗi vùng) nạp thẳng vào mô hình sram_2k_macro.
// Core khởi động từ boot ROM (RESET_PC mặc định 0x0001_0000).
//
// Pad GPIO: chân có gpio_oe = 1 đọc lại chính gpio_o, chân còn lại đọc PAD_IN.
// UART: uart_tx nối vòng về uart_rx. Bộ giải mã 8N1 của tb đọc uart_tx theo
// BAUDDIV hiện tại của UART, in ký tự ra log và bắt lỗi start/stop bit.
//
// Kết luận giống tb_core:
//   - ghi vào tohost: 1 = PASS, giá trị lẻ khác = FAIL, mã lỗi = giá trị >> 1
//   - trap khi mtvec vẫn bằng 0: FAIL
//   - uart_tx bằng X, hoặc khung UART sai start/stop bit: FAIL
//   - quá thời gian: FAIL
//
// Plusarg: +imem=<hex> +dmem=<hex> +tohost=<hex> +test=<tên> +timeout=<chu kỳ>

module tb_soc;

    parameter ENABLE_M         = 1;
    parameter ENABLE_WFI_SLEEP = 1;
    localparam BANK_W          = 2;     // khớp SOC_IMEM_BANK_W, SOC_DMEM_BANK_W và link.ld
    localparam WORDS           = 1024 << BANK_W;
    localparam [31:0] PAD_IN   = 32'hA5C3_0F96;

    reg clk   = 1'b0;
    reg rst_n = 1'b1;
    always #5 clk = ~clk;

    wire [31:0] gpio_i, gpio_o, gpio_oe;
    wire        uart_tx;

    assign gpio_i = (gpio_oe & gpio_o) | (~gpio_oe & PAD_IN);

    soc_top #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .gpio_i  (gpio_i),
        .gpio_o  (gpio_o),
        .gpio_oe (gpio_oe),
        .uart_rx (uart_tx),             // vòng lại
        .uart_tx (uart_tx)
    );

    // ---------------------------------------------------------- nạp bộ nhớ
    reg [31:0] img_i [0:WORDS-1];
    reg [31:0] img_d [0:WORDS-1];
    reg [8*512-1:0] file;
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            img_i[i] = 32'h0;
            img_d[i] = 32'h0;
        end
        if ($value$plusargs("imem=%s", file)) $readmemh(file, img_i);
        if ($value$plusargs("dmem=%s", file)) $readmemh(file, img_d);
    end

    // Mô hình macro tự xoá về 0 ở thời điểm 0, nên chép sau đó
    genvar gb;
    generate
        for (gb = 0; gb < (1 << BANK_W); gb = gb + 1) begin : g_load
            integer j;
            initial begin
                #2;
                for (j = 0; j < 1024; j = j + 1) begin
                    dut.u_imem.u_sram.u_arr.g_multi.g_bank[gb].u_mac.mem[j] = img_i[gb*1024 + j];
                    dut.u_dmem.u_arr.g_multi.g_bank[gb].u_mac.mem[j]        = img_d[gb*1024 + j];
                end
            end
        end
    endgenerate

    // ---------------------------------------------------------- kết thúc
    integer     cycle   = 0;
    integer     instret = 0;
    integer     sleep   = 0;
    integer     n_apb   = 0;
    integer     n_uart  = 0;
    integer     timeout = 200000;
    reg  [31:0] tohost  = 32'hFFFF_FFFF;
    reg  [8*64-1:0]  test_name = "soc";
    reg  [8*128-1:0] msg;
    reg         running = 1'b0;
    reg         done    = 1'b0;

    task end_test(input pass, input [8*128-1:0] why);
        begin
            if (!done) begin
                done = 1'b1;
                if (pass)
                    $display("PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, APB %0d, sleep %0d, UART %0d byte)",
                             test_name, cycle, instret, (instret > 0) ? (1.0 * cycle / instret) : 0.0,
                             n_apb, sleep, n_uart);
                else
                    $display("FAIL: %0s: %0s (cycle %0d, instret %0d)", test_name, why, cycle, instret);
                $finish;
            end
        end
    endtask

    always @(posedge clk) begin
        if (running) begin
            cycle = cycle + 1;
            if (cycle >= timeout)
                end_test(1'b0, "timeout");
            if (uart_tx === 1'bx)
                end_test(1'b0, "uart_tx = X");
            if (dut.u_core.wb_retire && !dut.u_core.wb_trap)
                instret = instret + 1;
            if (dut.core_sleep)
                sleep = sleep + 1;
            if (dut.apb_v && dut.apb_r)
                n_apb = n_apb + 1;
            if (dut.u_core.wb_trap && dut.u_core.csr_mtvec == 32'h0) begin
                $sformat(msg, "trap at pc %08h (instr %08h) with no handler",
                         dut.u_core.wb_pc_q, dut.u_core.wb_instr_q);
                end_test(1'b0, msg);
            end
            if (dut.d_req_valid && dut.d_req_ready && dut.d_we && dut.d_addr == tohost) begin
                if (dut.d_wdata == 32'd1)
                    end_test(1'b1, "");
                else begin
                    $sformat(msg, "tohost = 0x%08h (test %0d)", dut.d_wdata, dut.d_wdata >> 1);
                    end_test(1'b0, msg);
                end
            end
        end
    end

    // ---------------------------------------------------------- giải mã UART 8N1
    // Thấy start bit thì chờ nửa bit rồi lấy mẫu mỗi bit một lần: start, 8 bit dữ liệu
    // (LSB trước), stop. Một bit dài 16 x BAUDDIV chu kỳ (BAUDDIV = 0 tính như 1).
    reg         ub_busy = 1'b0;
    integer     ub_cnt  = 0;
    integer     ub_bit  = 0;
    integer     ub_per;
    reg  [7:0]  ub_sh   = 8'h0;

    always @(posedge clk) begin
        if (running) begin
            ub_per = 16 * ((dut.u_uart.div > 16'd1) ? dut.u_uart.div : 1);
            if (!ub_busy) begin
                if (uart_tx === 1'b0) begin
                    ub_busy = 1'b1;
                    ub_cnt  = ub_per / 2;
                    ub_bit  = 0;
                end
            end else begin
                ub_cnt = ub_cnt - 1;
                if (ub_cnt == 0) begin
                    if (ub_bit == 0) begin
                        if (uart_tx !== 1'b0) end_test(1'b0, "UART: start bit sai");
                    end else if (ub_bit <= 8) begin
                        ub_sh = {uart_tx, ub_sh[7:1]};
                    end else begin
                        if (uart_tx !== 1'b1) end_test(1'b0, "UART: stop bit sai");
                        $write("%c", ub_sh);
                        $fflush;
                        n_uart  = n_uart + 1;
                        ub_busy = 1'b0;
                    end
                    ub_bit = ub_bit + 1;
                    ub_cnt = ub_per;
                end
            end
        end
    end

    // ---------------------------------------------------------- reset
    task check_rst(input exp, input [8*64-1:0] why);
        begin
            if (dut.rst_n_sync !== exp) begin
                $sformat(msg, "reset_sync: %0s (rst_n_sync = %b)", why, dut.rst_n_sync);
                end_test(1'b0, msg);
            end
        end
    endtask

    initial begin
        if ($value$plusargs("timeout=%d", timeout)) ;
        if ($value$plusargs("tohost=%h", tohost)) ;
        if ($value$plusargs("test=%s", test_name)) ;
        if (tohost == 32'hFFFF_FFFF)
            $display("WARNING: khong co +tohost=, test chi ket thuc bang timeout");

        #1 rst_n = 1'b0;                        // cạnh xuống: reset bất đồng bộ tác dụng ngay
        #1 check_rst(1'b0, "khong xuong 0 khi assert");
        repeat (3) @(posedge clk);

        // Nhả reset giữa chu kỳ, rồi kéo xuống lại khi chuỗi đồng bộ mới đi nửa đường
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk) #1 check_rst(1'b0, "len 1 som (sau 1 canh)");
        @(negedge clk) rst_n = 1'b0;
        #1 check_rst(1'b0, "khong xuong 0 ngay khi assert");
        repeat (2) @(posedge clk);

        // Nhả reset lần cuối: lên 1 đúng ở cạnh lên thứ hai
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk) #1 check_rst(1'b0, "len 1 som (sau 1 canh)");
        @(posedge clk) #1 check_rst(1'b1, "khong len 1 sau 2 canh");
        running = 1'b1;
    end

endmodule

`default_nettype wire
