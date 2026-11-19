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
// SPI: spi_mosi loops back to spi_miso, so a transfer reads back the byte it sent.
// PWM: pwm_o drives the pad of gpio_i[15] (PAD_IN bit 15 is 0, so with the PWM off the pad
// reads 0 as before). Firmware samples the PWM output through GPIO DATA_IN.
// I2C: open-drain SCL and SDA with pull-ups, i2c_*_oe = 1 pulls a line low. The slave is
// tb/models/i2c_slave_model.v at address 0x50. A swapped or dead pin breaks the frames that
// fw/tests/soc/i2c.S checks.
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
//
// With -DGLS (scripts/gls_soc.sh, VER-07) the DUT is the soc_top netlist from Genus (default
// parameters: ENABLE_M=1, ENABLE_WFI_SLEEP=1, ENABLE_DMA=1). The netlist has no internal
// signals, so gls_paths.vh (written by scripts/gls_paths.py from the netlist) gives the
// hierarchical names of the 8 sram_2k_macro instances. The tb loads the programs through
// them and ends the test on the macro write to tohost. Checks that read internal signals are
// left out: instret, sleep and APB counters, trap without handler (ends by timeout instead),
// the UART decoder (it needs BAUDDIV, the UART tests check the loopback data themselves),
// the DMA statistics and the reset synchronizer checks.
// -DGLS_HALF=<ns> sets half the clock period (default 5 ns), -DGLS_SDF=<file> annotates
// the netlist with that SDF (VER-08).

module tb_soc;

    parameter ENABLE_M         = 1;
    parameter ENABLE_WFI_SLEEP = 1;
    parameter ENABLE_DMA       = 1;     // Same default as soc_top
    localparam BANK_W          = 2;     // Matches SOC_IMEM_BANK_W, SOC_DMEM_BANK_W and link.ld
    localparam WORDS           = 1024 << BANK_W;
    localparam [31:0] PAD_IN   = 32'hA5C3_0F96;

    reg clk   = 1'b0;
    reg rst_n = 1'b1;
`ifdef GLS_HALF
    always #(`GLS_HALF) clk = ~clk;
`else
    always #5 clk = ~clk;
`endif

    wire [31:0] gpio_i, gpio_o, gpio_oe;
    wire        uart_tx;
    wire        spi_sclk, spi_mosi, spi_cs_n, pwm_o;
    wire [31:0] pad = PAD_IN | {16'd0, pwm_o, 15'd0};

    wire        i2c_scl_oe, i2c_sda_oe, i2c_slave_pull;
    tri1        i2c_scl, i2c_sda;
    assign i2c_scl = i2c_scl_oe     ? 1'b0 : 1'bz;
    assign i2c_sda = i2c_sda_oe     ? 1'b0 : 1'bz;
    assign i2c_sda = i2c_slave_pull ? 1'b0 : 1'bz;

    i2c_slave_model #(.ADDR(7'h50)) u_i2c_slave (
        .scl      (i2c_scl),
        .sda      (i2c_sda),
        .sda_pull (i2c_slave_pull)
    );

    assign gpio_i = (gpio_oe & gpio_o) | (~gpio_oe & pad);

`ifdef GLS
    soc_top dut (
`else
    soc_top #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP),
        .ENABLE_DMA       (ENABLE_DMA)
    ) dut (
`endif
        .clk     (clk),
        .rst_n   (rst_n),
        .gpio_i  (gpio_i),
        .gpio_o  (gpio_o),
        .gpio_oe (gpio_oe),
        .uart_rx (uart_tx),             // Loopback
        .uart_tx (uart_tx),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_mosi),            // Loopback
        .spi_cs_n(spi_cs_n),
        .pwm_o   (pwm_o),
        .i2c_scl_i (i2c_scl),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i (i2c_sda),
        .i2c_sda_oe(i2c_sda_oe)
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
`ifdef GLS
`include "gls_paths.vh"
    // Array of the macro model that holds the words (scripts/gls_soc.sh finds it in MACRO_V)
`ifndef GLS_MEM
`define GLS_MEM mem
`endif
    integer j;
    initial begin
        #2;
        for (j = 0; j < 1024; j = j + 1) begin
            `GLS_I0 .`GLS_MEM [j] = img_i[0*1024 + j];
            `GLS_I1 .`GLS_MEM [j] = img_i[1*1024 + j];
            `GLS_I2 .`GLS_MEM [j] = img_i[2*1024 + j];
            `GLS_I3 .`GLS_MEM [j] = img_i[3*1024 + j];
            `GLS_D0 .`GLS_MEM [j] = img_d[0*1024 + j];
            `GLS_D1 .`GLS_MEM [j] = img_d[1*1024 + j];
            `GLS_D2 .`GLS_MEM [j] = img_d[2*1024 + j];
            `GLS_D3 .`GLS_MEM [j] = img_d[3*1024 + j];
        end
    end
`else
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
`endif

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

`ifdef GLS
    // ---------------------------------------------------------- activity (PWR-01)
    // Window: from the reset release (running = 1) to the tohost write, the same window as
    // the cycle count. +vcd=<file>: VCD of dut (any simulator, large). -DGLS_SAIF (Xcelium):
    // $stop at both ends of the window, where the xmsim Tcl script of scripts/gls_soc.sh
    // starts and ends dumpsaif (the $toggle_* tasks are not available at simulation).
    reg [8*256-1:0] vcd_file;
    reg             vcd_on = 1'b0;
    task act_start;
        begin
            if ($value$plusargs("vcd=%s", vcd_file)) begin
                $dumpfile(vcd_file);
                $dumpvars(0, dut);
                vcd_on = 1'b1;
            end
`ifdef GLS_SAIF
            $stop;
`endif
        end
    endtask
    task act_stop;
        begin
            if (vcd_on) $dumpflush;
`ifdef GLS_SAIF
            $stop;
`endif
        end
    endtask
`endif

    task end_test(input pass, input [8*128-1:0] why);
        begin
            if (!done) begin
                done = 1'b1;
                if (!uart_nl)
                    $display("");           // Keep the result line at the start of a line
`ifdef GLS
                if (pass)
                    $display("PASS: %0s (gate level, cycles %0d)", test_name, cycle);
                else
                    $display("FAIL: %0s: %0s (gate level, cycle %0d)", test_name, why, cycle);
                act_stop;
`else
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
`endif
                $finish;
            end
        end
    endtask

`ifdef GLS
    // tohost lives in one macro: DMEM for the fw-soc programs, IMEM (base 0) for riscv-tests,
    // whose tohost is in the code image. Bank = word index [11:10], row = word index [9:0]
    // (the bank order of sram_array). The write is seen on the macro pins at the falling
    // edge, when the zero-delay netlist has settled.
    wire        th_dmem = (tohost >= 32'h1000_0000);
    wire [11:0] th_word = (th_dmem ? tohost - 32'h1000_0000 : tohost) >> 2;
    reg         th_we;
    reg  [9:0]  th_a;
    reg  [31:0] th_d;
    always @(*) begin
        case ({th_dmem, th_word[11:10]})
            3'b100:  begin th_we = !`GLS_D0 .CEN && !`GLS_D0 .WEN; th_a = `GLS_D0 .A; th_d = `GLS_D0 .D; end
            3'b101:  begin th_we = !`GLS_D1 .CEN && !`GLS_D1 .WEN; th_a = `GLS_D1 .A; th_d = `GLS_D1 .D; end
            3'b110:  begin th_we = !`GLS_D2 .CEN && !`GLS_D2 .WEN; th_a = `GLS_D2 .A; th_d = `GLS_D2 .D; end
            3'b111:  begin th_we = !`GLS_D3 .CEN && !`GLS_D3 .WEN; th_a = `GLS_D3 .A; th_d = `GLS_D3 .D; end
            3'b000:  begin th_we = !`GLS_I0 .CEN && !`GLS_I0 .WEN; th_a = `GLS_I0 .A; th_d = `GLS_I0 .D; end
            3'b001:  begin th_we = !`GLS_I1 .CEN && !`GLS_I1 .WEN; th_a = `GLS_I1 .A; th_d = `GLS_I1 .D; end
            3'b010:  begin th_we = !`GLS_I2 .CEN && !`GLS_I2 .WEN; th_a = `GLS_I2 .A; th_d = `GLS_I2 .D; end
            default: begin th_we = !`GLS_I3 .CEN && !`GLS_I3 .WEN; th_a = `GLS_I3 .A; th_d = `GLS_I3 .D; end
        endcase
    end

    always @(posedge clk) begin
        if (running) begin
            cycle = cycle + 1;
            if (cycle >= timeout)
                end_test(1'b0, "timeout");
            if (uart_tx === 1'bx)
                end_test(1'b0, "uart_tx = X");
        end
    end

    always @(negedge clk) begin
        if (running && th_we === 1'b1 && th_a == th_word[9:0]) begin
            if (th_d === 32'd1)
                end_test(1'b1, "");
            else begin
                $sformat(msg, "tohost = 0x%08h (test %0d)", th_d, th_d >> 1);
                end_test(1'b0, msg);
            end
        end
    end

`ifdef GLS_SDF
    initial $sdf_annotate(`GLS_SDF, dut);
`endif
`else
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
`endif

    // ---------------------------------------------------------- reset
    task check_rst(input exp, input [8*64-1:0] why);
        begin
`ifndef GLS
            if (dut.rst_n_sync !== exp) begin
                $sformat(msg, "reset_sync: %0s (rst_n_sync = %b)", why, dut.rst_n_sync);
                end_test(1'b0, msg);
            end
`endif
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
`ifdef GLS
        act_start;
`endif
    end

endmodule

`default_nettype wire
