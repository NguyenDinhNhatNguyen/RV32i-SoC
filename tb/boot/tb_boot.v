`timescale 1ns/1ps
`default_nettype none
// tb_boot - UART bootloader test on soc_top (docs/boot.md). The boot ROM is the real
// rtl/mem/boot_rom_init.vh, nothing inside the chip is forced.
//
// A host model plays the PC on the UART pins, at the baud the chip uses (16 x BAUDDIV cycles
// per bit):
//   - Sends MAGIC once every 2 byte times until READY comes back (as scripts/uart_pack.py)
//   - For each packet i (+pkt<i>=<hex from uart_pack.py --hex>): sends SYNC and the header,
//     waits for ACK/NAK. After ACK sends data and crc, waits for ACK/NAK.
//     +exp<i>=A (both ACK), H (header NAK), D (data NAK). The first byte of each file (MAGIC)
//     is not sent again.
//   - Prints the bytes that come after the last ACK (output of the loaded program).
//
// Checks:
//   - Every answer as expected, no extra bytes before the program runs
//   - IMEM writes: none for a header NAK, len / 4 for an accepted header
//   - First fetch outside the boot ROM is at +jump=<hex>, and not before +min_jump=<cycles>
//   - The program writes 1 to TOHOST and printed "boot ok\n"
// With +npkt=0 the host stays silent: the bootloader must time out (or skip the UART with
// strap 0) and run the program that +imem=<hex> preloaded in IMEM.
// gpio_i[0] is the boot strap (+strap=1 UART boot, default), the other pins read 0.
// make sim-boot compiles this bench twice: with the committed boot ROM and with a ROM built
// for simulation (short timeout, BAUDDIV 1).
//
// Plusargs: +test=<name> +strap=<0|1> +npkt=<n> +pkt<i>=<hex> +exp<i>=<A|H|D> +imem=<hex>
//           +jump=<hex> +min_jump=<cycles> +max_jump=<cycles> +magic_delay=<cycles>
//           +timeout=<cycles>
`include "soc_map.vh"

module tb_boot;

    parameter ENABLE_M         = 1;
    parameter ENABLE_WFI_SLEEP = 1;
    localparam BANK_W          = 2;     // Matches SOC_IMEM_BANK_W
    localparam WORDS           = 1024 << BANK_W;
    localparam [31:0] TOHOST   = 32'h1000_0000;
    localparam [7:0] MAGIC = 8'hA5, READY = 8'h3E, ACK = 8'h06, NAK = 8'h15;
    localparam PKT_MAX         = 20000;

    reg clk   = 1'b0;
    reg rst_n = 1'b1;
    always #5 clk = ~clk;

    reg  host_tx = 1'b1;                // PC -> chip
    wire uart_tx;                       // Chip -> PC
    wire [31:0] gpio_o, gpio_oe;
    reg         strap = 1'b1;

    soc_top #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .gpio_i  ({31'h0, strap}),
        .gpio_o  (gpio_o),
        .gpio_oe (gpio_oe),
        .uart_rx (host_tx),
        .uart_tx (uart_tx)
    );

    // ---------------------------------------------------------- IMEM preload
    reg [31:0] img_i [0:WORDS-1];
    reg [8*512-1:0] file;
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            img_i[i] = 32'h0;
        if ($value$plusargs("imem=%s", file)) $readmemh(file, img_i);
    end

    genvar gb;
    generate
        for (gb = 0; gb < (1 << BANK_W); gb = gb + 1) begin : g_load
            integer j;
            initial begin
                #2;                     // The macro model clears itself at time 0
                for (j = 0; j < 1024; j = j + 1)
                    dut.u_imem.u_sram.u_arr.g_multi.g_bank[gb].u_mac.mem[j] = img_i[gb*1024 + j];
            end
        end
    endgenerate

    // ---------------------------------------------------------- result
    integer     cycle    = 0;
    integer     timeout  = 3000000;
    reg  [8*64-1:0]  test_name = "boot";
    reg  [8*160-1:0] msg;
    reg         done     = 1'b0;
    reg         host_end = 1'b0;        // Host finished, the bytes now come from the program
    reg  [8*16-1:0]  prog_out = 0;      // Last 16 bytes printed by the program
    integer     n_out    = 0;
    integer     n_imem_w = 0;           // IMEM writes from the data port
    integer     jump_cyc = -1;
    reg  [31:0] jump_pc  = 32'h0;
    reg  [31:0] exp_jump = 32'h0;
    integer     min_jump = 0;
    integer     max_jump = 32'h7FFF_FFFF;
    integer     load_cyc = 0;           // SYNC of the last packet to its last ACK
    integer     load_len = 0;

    task fail(input [8*160-1:0] why);
        begin
            if (!done) begin
                done = 1'b1;
                $display("");
                $display("FAIL: %0s: %0s (cycle %0d)", test_name, why, cycle);
                $finish;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (cycle >= timeout)
                fail("timeout");
            if (uart_tx === 1'bx)
                fail("uart_tx = X");
            if (dut.imem_v && dut.imem_r && dut.s_we)
                n_imem_w = n_imem_w + 1;
            // First instruction fetch that leaves the boot ROM
            if (jump_cyc < 0 && dut.if_req && dut.if_gnt && dut.if_addr < `SOC_BOOT_BASE) begin
                jump_cyc = cycle;
                jump_pc  = dut.if_addr;
            end
            if (dut.u_core.wb_trap) begin
                $sformat(msg, "trap at pc %08h", dut.u_core.wb_pc_q);
                fail(msg);
            end
            if (dut.d_req_valid && dut.d_req_ready && dut.d_we && dut.d_addr == TOHOST)
                check_end(dut.d_wdata);
        end
    end

    task check_end(input [31:0] val);
        begin
            if (val != 32'd1) begin
                $sformat(msg, "program wrote 0x%08h to tohost", val);
                fail(msg);
            end else if (!host_end) begin
                fail("program ran before the host finished");
            end else if (jump_pc != exp_jump) begin
                $sformat(msg, "jumped to 0x%08h, expected 0x%08h", jump_pc, exp_jump);
                fail(msg);
            end else if (jump_cyc < min_jump || jump_cyc > max_jump) begin
                $sformat(msg, "left the boot ROM at cycle %0d, expected %0d to %0d",
                         jump_cyc, min_jump, max_jump);
                fail(msg);
            end else if (n_out != 8 || prog_out[8*8-1:0] != "boot ok\n") begin
                $sformat(msg, "%0d bytes after the host finished, expected only \"boot ok\"",
                         n_out);
                fail(msg);
            end else if (!done) begin
                done = 1'b1;
                $display("");
                if (load_len > 0)
                    $display({"PASS: %0s (jump to 0x%08h at cycle %0d, ",
                              "last load %0d bytes in %0d cycles)"},
                             test_name, jump_pc, jump_cyc, load_len, load_cyc);
                else
                    $display("PASS: %0s (jump to 0x%08h at cycle %0d, no load)",
                             test_name, jump_pc, jump_cyc);
                $finish;
            end
        end
    endtask

    // ---------------------------------------------------------- PC side: receiver
    // Same sampling as the tb_soc decoder: half a bit after the start edge, then once per bit
    function integer bit_cycles(input dummy);
        bit_cycles = 16 * ((dut.u_uart.div > 16'd1) ? dut.u_uart.div : 1);
    endfunction

    reg  [7:0]  rx_q [0:255];
    integer     rx_wr = 0, rx_rd = 0;
    reg         rb_busy = 1'b0;
    integer     rb_cnt = 0, rb_bit = 0;
    reg  [7:0]  rb_sh = 8'h0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (!rb_busy) begin
                if (uart_tx === 1'b0) begin
                    rb_busy = 1'b1;
                    rb_cnt  = bit_cycles(0) / 2;
                    rb_bit  = 0;
                end
            end else begin
                rb_cnt = rb_cnt - 1;
                if (rb_cnt == 0) begin
                    if (rb_bit == 0) begin
                        if (uart_tx !== 1'b0) fail("UART: bad start bit");
                    end else if (rb_bit <= 8) begin
                        rb_sh = {uart_tx, rb_sh[7:1]};
                    end else begin
                        if (uart_tx !== 1'b1) fail("UART: bad stop bit");
                        if (host_end) begin
                            $write("%c", rb_sh);
                            $fflush;
                            prog_out = {prog_out[8*15-1:0], rb_sh};
                            n_out    = n_out + 1;
                        end else begin
                            rx_q[rx_wr % 256] = rb_sh;
                            rx_wr = rx_wr + 1;
                        end
                        rb_busy = 1'b0;
                    end
                    rb_bit = rb_bit + 1;
                    rb_cnt = bit_cycles(0);
                end
            end
        end
    end

    // Wait up to n cycles for a byte from the chip, ok = 0 when none came
    task get_byte(input integer n, output [7:0] b, output ok);
        integer k;
        begin
            ok = 1'b0;
            b  = 8'h0;
            for (k = 0; k < n && rx_rd == rx_wr; k = k + 1)
                @(posedge clk);
            if (rx_rd != rx_wr) begin
                b     = rx_q[rx_rd % 256];
                rx_rd = rx_rd + 1;
                ok    = 1'b1;
            end
        end
    endtask

    // ---------------------------------------------------------- PC side: transmitter
    task send_byte(input [7:0] b);
        integer k, per;
        begin
            per = bit_cycles(0);
            host_tx = 1'b0;
            repeat (per) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                host_tx = b[k];
                repeat (per) @(posedge clk);
            end
            host_tx = 1'b1;
            repeat (per) @(posedge clk);
        end
    endtask

    reg  [7:0]  pkt [0:PKT_MAX-1];
    integer     pkt_len;

    task load_pkt(input [8*512-1:0] name);
        integer fd, r;
        begin
            pkt_len = 0;
            fd = $fopen(name, "r");
            if (fd == 0) fail("cannot open packet file");
            r = 1;
            while (r == 1 && pkt_len < PKT_MAX) begin
                r = $fscanf(fd, "%h\n", pkt[pkt_len]);
                if (r == 1) pkt_len = pkt_len + 1;
            end
            $fclose(fd);
            if (pkt_len < 15 || pkt[0] != MAGIC) fail("bad packet file");
        end
    endtask

    // Expect one answer byte within 20 byte times
    task expect_byte(input [7:0] want, input [8*32-1:0] what);
        reg [7:0] b;
        reg       ok;
        begin
            get_byte(200 * bit_cycles(0), b, ok);
            if (!ok) begin
                $sformat(msg, "no answer after %0s", what);
                fail(msg);
            end else if (b != want) begin
                $sformat(msg, "after %0s got 0x%02h, expected 0x%02h", what, b, want);
                fail(msg);
            end
        end
    endtask

    // ---------------------------------------------------------- host program
    integer     npkt = 0, p, k, magic_delay = 0, w0, t0;
    reg  [7:0]  b;
    reg         ok;
    reg  [8*16-1:0] fmt;
    reg  [8*8-1:0]  expc;

    initial begin
        if ($value$plusargs("test=%s", test_name)) ;
        if ($value$plusargs("timeout=%d", timeout)) ;
        if ($value$plusargs("npkt=%d", npkt)) ;
        if ($value$plusargs("jump=%h", exp_jump)) ;
        if ($value$plusargs("min_jump=%d", min_jump)) ;
        if ($value$plusargs("max_jump=%d", max_jump)) ;
        if ($value$plusargs("strap=%d", strap)) ;
        if ($value$plusargs("magic_delay=%d", magic_delay)) ;

        #1 rst_n = 1'b0;                // Falling edge, so the asynchronous reset acts
        repeat (5) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        if (npkt > 0) begin
            repeat (magic_delay) @(posedge clk);
            ok = 1'b0;
            while (!ok) begin
                send_byte(MAGIC);
                get_byte(20 * bit_cycles(0), b, ok);
                if (ok && b != READY) begin
                    $sformat(msg, "got 0x%02h while waiting for READY", b);
                    fail(msg);
                end
            end
            for (p = 0; p < npkt; p = p + 1) begin
                $sformat(fmt, "pkt%0d=%%s", p);
                if (!$value$plusargs(fmt, file)) fail("missing +pkt<i>");
                $sformat(fmt, "exp%0d=%%s", p);
                expc = "A";
                if ($value$plusargs(fmt, expc)) ;
                load_pkt(file);
                w0 = n_imem_w;
                t0 = cycle;
                for (k = 1; k < 10; k = k + 1)           // SYNC and header
                    send_byte(pkt[k]);
                if (expc[7:0] == "H") begin
                    expect_byte(NAK, "bad header");
                    if (n_imem_w != w0) fail("IMEM written after a bad header");
                end else begin
                    expect_byte(ACK, "header");
                    for (k = 10; k < pkt_len; k = k + 1) // Data and crc
                        send_byte(pkt[k]);
                    expect_byte(expc[7:0] == "D" ? NAK : ACK, "data");
                    if (n_imem_w - w0 != (pkt_len - 14) / 4) fail("wrong number of IMEM writes");
                    load_cyc = cycle - t0;
                    load_len = pkt_len - 1;
                end
                $display("host: packet %0d (%0d bytes) answered as expected (%0s)",
                         p, pkt_len - 1, expc[7:0] == "A" ? "ACK" : "NAK");
            end
        end
        // No byte may arrive before the program starts
        if (rx_rd != rx_wr) fail("extra bytes from the bootloader");
        host_end = 1'b1;
    end

endmodule

`default_nettype wire
