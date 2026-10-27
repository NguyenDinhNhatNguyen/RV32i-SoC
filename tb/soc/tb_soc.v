`timescale 1ns/1ps
`default_nettype none
// tb_soc - SoC-level testbench for soc_top (RTL-09). It only drives the chip pins and
// reads internal signals by hierarchical reference to decide the result.
//
// Before running the program it checks the reset synchronizer:
//   - Release rst_n mid-cycle: rst_n_sync rises exactly on the second rising edge
//   - Pull rst_n low mid-cycle: rst_n_sync drops to 0 at once, without a clock
// Memory images (elf2hex.py, 16 KB per region) load straight into the sram_2k_macro model.
// The core boots from the boot ROM (default RESET_PC 0x0001_0000). PAD_IN bit 0 is 0, so the
// boot strap gpio_i[0] = 0 and the UART bootloader jumps straight to IMEM (docs/boot.md).
//
// GPIO pads: a pin with gpio_oe = 1 reads back its own gpio_o, the others read PAD_IN.
// UART: uart_tx loops back to uart_rx. The tb 8N1 decoder samples uart_tx with the
// UART's current BAUDDIV, prints characters to the log and catches start/stop bit errors.
//
// Result rules, as in tb_core:
//   - Write to tohost: 1 = PASS, another odd value = FAIL, error code = value >> 1
//   - A trap while mtvec is still 0: FAIL
//   - uart_tx is X, or a UART frame has a bad start/stop bit: FAIL
//   - Timeout: FAIL
//
// ENABLE_DMA = 1 builds soc_top with the DMA (RTL-15). The PASS line then also shows how many
// words the DMA wrote and how many cycles it was busy.
//
// Plusargs: +imem=<hex> +dmem=<hex> +tohost=<hex> +test=<name> +timeout=<cycles>

module tb_soc;

    parameter ENABLE_M         = 1;
    parameter ENABLE_WFI_SLEEP = 1;
    parameter ENABLE_DMA       = 0;
    localparam BANK_W          = 2;     // Matches SOC_IMEM_BANK_W, SOC_DMEM_BANK_W and link.ld
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
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP),
        .ENABLE_DMA       (ENABLE_DMA)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .gpio_i  (gpio_i),
        .gpio_o  (gpio_o),
        .gpio_oe (gpio_oe),
        .uart_rx (uart_tx),             // Loopback
        .uart_tx (uart_tx)
    );

    // ---------------------------------------------------------- memory load
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

    // The macro model clears itself at time 0, so copy after that
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

    // ---------------------------------------------------------- end of test
    integer     cycle   = 0;
    integer     instret = 0;
    integer     sleep   = 0;
    integer     n_apb   = 0;
    integer     n_uart  = 0;
    integer     n_dma_w = 0;            // Words written by the DMA (ENABLE_DMA = 1)
    integer     n_dma_c = 0;            // Cycles the DMA was busy
    reg         uart_nl = 1'b1;         // Last UART character was a newline (or none yet)
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
                if (!uart_nl)
                    $display("");           // Keep the result line at the start of a line
                if (pass && ENABLE_DMA != 0)
                    $display({"PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, APB %0d, sleep %0d, ",
                              "UART %0d byte, DMA %0d words in %0d busy cycles)"},
                             test_name, cycle, instret,
                             (instret > 0) ? (1.0 * cycle / instret) : 0.0,
                             n_apb, sleep, n_uart, n_dma_w, n_dma_c);
                else if (pass)
                    $display({"PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, APB %0d, sleep %0d, ",
                              "UART %0d byte)"},
                             test_name, cycle, instret,
                             (instret > 0) ? (1.0 * cycle / instret) : 0.0,
                             n_apb, sleep, n_uart);
                else
                    $display("FAIL: %0s: %0s (cycle %0d, instret %0d)",
                             test_name, why, cycle, instret);
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

    // ---------------------------------------------------------- UART 8N1 decoder
    // On a start bit, wait half a bit and then sample once per bit: start, 8 data bits
    // (LSB first), stop. One bit lasts 16 x BAUDDIV cycles (BAUDDIV = 0 counts as 1).
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
                        if (uart_tx !== 1'b0) end_test(1'b0, "UART: bad start bit");
                    end else if (ub_bit <= 8) begin
                        ub_sh = {uart_tx, ub_sh[7:1]};
                    end else begin
                        if (uart_tx !== 1'b1) end_test(1'b0, "UART: bad stop bit");
                        $write("%c", ub_sh);
                        $fflush;
                        n_uart  = n_uart + 1;
                        uart_nl = (ub_sh == 8'h0A);
                        ub_busy = 1'b0;
                    end
                    ub_bit = ub_bit + 1;
                    ub_cnt = ub_per;
                end
            end
        end
    end

    // ---------------------------------------------------------- DMA statistics
    generate
        if (ENABLE_DMA != 0) begin : g_dma_stat
            always @(posedge clk) begin
                if (running) begin
                    if (dut.m_req_valid[1] && dut.m_req_ready[1] && dut.m_we[1])
                        n_dma_w = n_dma_w + 1;
                    if (dut.g_dma.u_dma.st != 3'd0)
                        n_dma_c = n_dma_c + 1;
                end
            end
        end
    endgenerate

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
            $display("WARNING: no +tohost=, the test can only end by timeout");

        #1 rst_n = 1'b0;                        // Falling edge: the asynchronous reset acts at once
        #1 check_rst(1'b0, "did not drop to 0 on assert");
        repeat (3) @(posedge clk);

        // Release reset mid-cycle, then pull it low again halfway through the synchronizer
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk) #1 check_rst(1'b0, "rose too early (after 1 edge)");
        @(negedge clk) rst_n = 1'b0;
        #1 check_rst(1'b0, "did not drop to 0 at once on assert");
        repeat (2) @(posedge clk);

        // Final release: rises exactly on the second rising edge
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk) #1 check_rst(1'b0, "rose too early (after 1 edge)");
        @(posedge clk) #1 check_rst(1'b1, "did not rise after 2 edges");
        running = 1'b1;
    end

endmodule

`default_nettype wire
