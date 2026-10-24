`timescale 1ns/1ps
// Testbench tu kiem tra cho uart_apb (+ uart_fifo). In "PASS: ..." neu moi kiem tra dung.
// Ghi chu: bit tren duong truyen = 16 * DIV chu ky clk. DIV mac dinh 27 -> 8640 ns/bit.
// Phan lon bai dung DIV = 2 (640 ns/bit) cho nhanh; 2 bai dung baud mac dinh de kiem tra thoi gian that.
module tb_uart_apb;
    localparam HALF = 10;                 // 50 MHz
    localparam DEPTH = 8;                 // phai khop FIFO_AW = 3

    reg         PCLK = 1'b0;
    reg         PRESETn = 1'b0;
    reg         PSEL = 1'b0;
    reg         PENABLE = 1'b0;
    reg         PWRITE = 1'b0;
    reg  [11:0] PADDR = 12'd0;
    reg  [31:0] PWDATA = 32'd0;
    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        uart_txd;
    wire        irq;
    reg         rxd_drv = 1'b1;
    reg         loop = 1'b0;
    wire        uart_rxd = loop ? uart_txd : rxd_drv;

    uart_apb #(.FIFO_AW(3), .DIV_RESET(16'd27)) dut (
        .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .uart_txd(uart_txd), .uart_rxd(uart_rxd), .irq(irq)
    );

    always #HALF PCLK = ~PCLK;

    localparam A_DATA = 12'h000, A_STATUS = 12'h004, A_CTRL = 12'h008, A_BAUD = 12'h00C;
    localparam [31:0] S_TXF = 32'h01, S_TXE = 32'h02, S_TXB = 32'h04, S_RXF = 32'h08,
                      S_RXNE = 32'h10, S_OVR = 32'h20, S_FE = 32'h40, S_TXOVF = 32'h80;

    integer errors = 0;
    reg [31:0] rd;
    reg        err_seen;
    integer    i, j, t0, t1, seed;
    reg [7:0]  b;
    reg [7:0]  expq [0:63];

    // ------------------------------------------------------------------ helpers
    task check;
        input        cond;
        input [8*48-1:0] tag;
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

    // gui 1 khung vao chan RX voi do rong bit bitns (ns); stop_val = 0 de tao loi khung
    task rx_send;
        input [7:0]   d;
        input integer bitns;
        input         stop_val;
        integer k;
        begin
            rxd_drv = 1'b0; #(bitns);
            for (k = 0; k < 8; k = k + 1) begin rxd_drv = d[k]; #(bitns); end
            rxd_drv = stop_val; #(bitns);
            rxd_drv = 1'b1;
        end
    endtask

    // doc STATUS va kiem tra theo mask: (STATUS & mask) == val
    task status_is;
        input [31:0] mask;
        input [31:0] val;
        input [8*48-1:0] tag;
        begin
            apb_read(A_STATUS);
            check((rd & mask) === val && !err_seen, tag);
        end
    endtask

    // doc 1 byte tu RX FIFO va so sanh
    task rx_expect;
        input [7:0] exp;
        input [8*48-1:0] tag;
        begin
            apb_read(A_DATA);
            check(rd === {24'd0, exp} && !err_seen, tag);
        end
    endtask

    // ------------------------------------------------------------------ monitor TX
    // Giai ma duong uart_txd doc lap voi DUT, theo do rong bit mon_bit (ns)
    integer mon_bit = 8640;
    reg [7:0] txq [0:255];
    integer tx_cnt = 0;
    integer tx_bad = 0;
    integer mi;
    reg [7:0] mb;

    always @(negedge uart_txd) begin : MON
        #(mon_bit/2);
        if (uart_txd !== 1'b0) tx_bad = tx_bad + 1;      // start bit ngan / nhieu
        for (mi = 0; mi < 8; mi = mi + 1) begin
            #(mon_bit);
            mb[mi] = uart_txd;
        end
        #(mon_bit);
        if (uart_txd !== 1'b1) tx_bad = tx_bad + 1;      // stop bit sai
        txq[tx_cnt] = mb;
        tx_cnt = tx_cnt + 1;
    end

    task wait_tx;
        input integer n;
        input integer timeout_ns;
        integer tw;
        begin
            tw = 0;
            while (tx_cnt < n && tw < timeout_ns) begin #100; tw = tw + 100; end
            check(tx_cnt >= n, "TX frames arrived before timeout");
        end
    endtask

    task mon_reset;
        input integer bitns;
        begin
            mon_bit = bitns; tx_cnt = 0; tx_bad = 0;
        end
    endtask

    task wait_rx_data;                      // cho den khi RXNE (toi da ~ 200 us)
        integer pw;
        begin
            pw = 0;
            apb_read(A_STATUS);
            while (!(rd & S_RXNE) && pw < 600) begin
                apb_read(A_STATUS); pw = pw + 1;
            end
            check((rd & S_RXNE) != 0, "RXNE appeared before timeout");
        end
    endtask

    initial begin
        #20000000;
        $display("FAIL: timeout");
        $finish;
    end

    // ------------------------------------------------------------------ test
    initial begin
        $dumpfile("tb/unit/out/uart_apb.vcd");
        $dumpvars(0, tb_uart_apb);
        seed = 32'h0A2701;
        if (!$value$plusargs("seed=%d", seed)) seed = 32'h0A2701;

        // ---- 1. Reset ----
        wait_clks(3);
        PRESETn = 1;
        wait_clks(3);
        check(uart_txd === 1'b1, "reset: TXD idle high");
        check(irq === 1'b0,      "reset: irq low");
        apb_read(A_CTRL);   check(rd === 32'h3 && !err_seen,  "reset: CTRL = 0x03");
        apb_read(A_BAUD);   check(rd === 32'd27 && !err_seen, "reset: BAUDDIV = 27");
        apb_read(A_STATUS); check(rd === S_TXE && !err_seen,  "reset: STATUS = TXE only");
        apb_read(A_DATA);   check(rd === 32'd0 && !err_seen,  "reset: DATA read empty = 0, no error");

        // ---- 2. TX 1 byte o baud mac dinh: thoi gian that ----
        mon_reset(8640);                                    // 16 * 27 * 20 ns
        apb_write(A_DATA, 32'h55);
        check(!err_seen, "TX: write DATA no PSLVERR");
        @(negedge uart_txd); t0 = $time;
        @(posedge uart_txd); t1 = $time;                    // 0x55: bit 0 = 1
        check((t1 - t0) >= 8639 && (t1 - t0) <= 8641, "TX: start bit width = 8640 ns @115200");
        apb_read(A_STATUS);
        check((rd & (S_TXE | S_TXB)) != S_TXE, "TX: busy or FIFO not empty while sending");
        wait_tx(1, 150000);
        check(txq[0] === 8'h55, "TX: byte 0x55 on the wire");
        check(tx_bad == 0, "TX: start/stop bits ok");
        #(3*8640);
        status_is(S_TXE | S_TXB | S_TXF, S_TXE, "TX: idle again after frame");

        // ---- 3. Doi sang DIV = 2 (nhanh). Ghi/doc BAUDDIV ----
        apb_write(A_BAUD, 32'd2);
        apb_read(A_BAUD); check(rd === 32'd2, "BAUDDIV readback");

        // ---- 4. TX FIFO day, tran, bo byte thu 9, gui dung thu tu ----
        mon_reset(640);
        apb_write(A_CTRL, 32'h2);                           // TXEN=0, RXEN=1
        for (i = 0; i < DEPTH; i = i + 1) begin
            expq[i] = 8'h10 + i * 8'h11;
            apb_write(A_DATA, {24'd0, expq[i]});
        end
        status_is(S_TXF | S_TXE, S_TXF, "TXFIFO: full after 8 writes, TX disabled");
        status_is(S_TXOVF, 32'd0, "TXFIFO: no overflow yet");
        apb_write(A_DATA, 32'hEE);                          // thu 9: bi bo
        status_is(S_TXOVF, S_TXOVF, "TXFIFO: 9th write sets TXOVF");
        apb_write(A_STATUS, S_TXOVF);
        status_is(S_TXOVF, 32'd0, "TXFIFO: TXOVF cleared by W1C");
        apb_write(A_CTRL, 32'h3);                           // bat TX
        wait_tx(DEPTH, 200000);
        #(4*640);
        check(tx_cnt == DEPTH, "TXFIFO: exactly 8 frames (9th dropped)");
        for (i = 0; i < DEPTH; i = i + 1)
            check(txq[i] === expq[i], "TXFIFO: bytes in order");
        check(tx_bad == 0, "TXFIFO: all frames well formed");

        // ---- 5. RX: nhieu byte, thu tu, co STATUS ----
        for (i = 0; i < 5; i = i + 1) begin
            expq[i] = 8'hA0 + i * 8'h07;
            rx_send(expq[i], 640, 1'b1);
        end
        #(2*640);
        status_is(S_RXNE | S_RXF | S_OVR | S_FE, S_RXNE, "RX: data available, no errors");
        for (i = 0; i < 5; i = i + 1) rx_expect(expq[i], "RX: bytes in order");
        status_is(S_RXNE, 32'd0, "RX: empty after reading all");

        // ---- 6. RX FIFO day -> overrun, byte thu 9 bi bo ----
        for (i = 0; i < DEPTH + 1; i = i + 1) begin
            expq[i] = 8'h30 + i;
            rx_send(expq[i], 640, 1'b1);
            #(640);
        end
        status_is(S_RXF | S_OVR, S_RXF | S_OVR, "RX: FIFO full + overrun set");
        for (i = 0; i < DEPTH; i = i + 1) rx_expect(expq[i], "RX full: first 8 bytes kept");
        status_is(S_RXNE, 32'd0, "RX full: 9th byte dropped");
        apb_write(A_STATUS, S_OVR);
        status_is(S_OVR, 32'd0, "RX: overrun cleared by W1C");

        // ---- 7. Loi khung (stop = 0): khong day byte, co FE, hoi phuc ----
        rx_send(8'h3C, 640, 1'b0);
        #(2*640);
        status_is(S_FE | S_RXNE, S_FE, "FE: flag set, byte discarded");
        rx_send(8'hC3, 640, 1'b1);
        #(2*640);
        rx_expect(8'hC3, "FE: receiver recovers, next byte ok");
        apb_write(A_STATUS, S_FE);
        status_is(S_FE, 32'd0, "FE: cleared by W1C");

        // ---- 8. Break (giu thap lau): chi bao FE, khong sinh byte, hoi phuc ----
        rxd_drv = 1'b0; #(25*640); rxd_drv = 1'b1; #(3*640);
        status_is(S_FE | S_RXNE, S_FE, "BREAK: FE only, no phantom byte");
        apb_write(A_STATUS, S_FE);
        rx_send(8'h5A, 640, 1'b1); #(2*640);
        rx_expect(8'h5A, "BREAK: byte after break received");

        // ---- 9. Nhieu ngan tren start bit bi bo qua ----
        rxd_drv = 1'b0; #150; rxd_drv = 1'b1; #(3*640);
        status_is(S_FE | S_RXNE, 32'd0, "GLITCH: short start pulse ignored");
        rx_send(8'h81, 640, 1'b1); #(2*640);
        rx_expect(8'h81, "GLITCH: next byte ok");

        // ---- 10. Dung sai toc do +-3% ----
        rx_send(8'h96, 659, 1'b1); #(2*640);
        rx_expect(8'h96, "TOL: +3% bit time received");
        rx_send(8'h69, 621, 1'b1); #(2*640);
        rx_expect(8'h69, "TOL: -3% bit time received");

        // ---- 11. Tat RX: khong nhan ----
        apb_write(A_CTRL, 32'h1);                           // RXEN = 0
        rx_send(8'h77, 640, 1'b1); #(2*640);
        status_is(S_RXNE, 32'd0, "RXEN=0: byte ignored");
        apb_write(A_CTRL, 32'h3);

        // ---- 12. Ngat ----
        apb_write(A_CTRL, 32'h2 | 32'h8);                   // RXEN + RXIE
        wait_clks(3); check(irq === 1'b0, "IRQ: RXIE, no data -> low");
        rx_send(8'h12, 640, 1'b1); #(2*640);
        check(irq === 1'b1, "IRQ: RXIE, data -> high");
        rx_expect(8'h12, "IRQ: read data");
        wait_clks(3); check(irq === 1'b0, "IRQ: low after data read");

        apb_write(A_CTRL, 32'h2 | 32'h10);                  // RXEN + ERRIE
        wait_clks(3); check(irq === 1'b0, "IRQ: ERRIE, no error -> low");
        rx_send(8'h00, 640, 1'b0); #(2*640);
        check(irq === 1'b1, "IRQ: ERRIE, FE -> high");
        apb_write(A_STATUS, S_FE); wait_clks(3);
        check(irq === 1'b0, "IRQ: ERRIE low after W1C");

        mon_reset(640);
        apb_write(A_CTRL, 32'h2 | 32'h4);                   // TX tat, TXIE bat
        wait_clks(3); check(irq === 1'b1, "IRQ: TXIE, FIFO empty -> high");
        apb_write(A_DATA, 32'h42); wait_clks(3);
        check(irq === 1'b0, "IRQ: TXIE low when FIFO has data");
        apb_write(A_CTRL, 32'h3);                           // bat TX, tat TXIE
        wait_tx(1, 50000);
        check(txq[0] === 8'h42, "IRQ: queued byte sent after TXEN");
        #(3*640);

        // ---- 13. BAUDDIV = 0 hoat dong nhu 1 ----
        apb_write(A_BAUD, 32'd0);
        apb_read(A_BAUD); check(rd === 32'd0, "BAUDDIV=0 readback");
        mon_reset(320);                                     // 16 clk/bit
        apb_write(A_DATA, 32'h6B);
        wait_tx(1, 20000);
        check(txq[0] === 8'h6B && tx_bad == 0, "BAUDDIV=0 behaves like 1");
        #(3*320);
        rx_send(8'hD2, 320, 1'b1); #(2*320);
        rx_expect(8'hD2, "BAUDDIV=0: RX also works");
        apb_write(A_BAUD, 32'd2);

        // ---- 14. Loopback TX -> RX, byte le (ngau nhien), roi burst 8 byte ----
        loop = 1'b1;
        mon_reset(640);
        for (i = 0; i < 16; i = i + 1) begin
            b = $random(seed);
            apb_write(A_DATA, {24'd0, b});
            wait_rx_data;
            rx_expect(b, "LOOP: random byte round trip");
        end
        for (i = 0; i < DEPTH; i = i + 1) begin
            expq[i] = $random(seed);
            apb_write(A_DATA, {24'd0, expq[i]});
        end
        wait_tx(16 + DEPTH, 200000);
        #(3*640);
        status_is(S_OVR | S_FE | S_TXOVF, 32'd0, "LOOP: burst, no error flags");
        status_is(S_RXF, S_RXF, "LOOP: burst fills RX FIFO");
        for (i = 0; i < DEPTH; i = i + 1) rx_expect(expq[i], "LOOP: burst bytes in order");
        check(tx_bad == 0, "LOOP: every TX frame well formed");
        loop = 1'b0;

        // ---- 15. Loopback o baud mac dinh (115200) ----
        apb_write(A_BAUD, 32'd27);
        mon_reset(8640);
        loop = 1'b1;
        apb_write(A_DATA, 32'hA7);
        wait_clks(12000);                                   // ~ 240 us > 1 khung (86.4 us)
        wait_rx_data;
        rx_expect(8'hA7, "LOOP@115200: byte round trip");
        check(tx_bad == 0, "LOOP@115200: frame well formed");
        loop = 1'b0;

        // ---- 16. Truy cap sai ----
        apb_write(12'h010, 32'h1);  check(err_seen, "bad addr 0x10 write -> PSLVERR");
        apb_read(12'h010);          check(err_seen && rd === 32'd0, "bad addr 0x10 read -> PSLVERR, 0");
        apb_write(12'h002, 32'h1);  check(err_seen, "misaligned write -> PSLVERR");
        apb_read(12'h006);          check(err_seen && rd === 32'd0, "misaligned read -> PSLVERR, 0");
        apb_write(A_STATUS, 32'h1F); check(!err_seen, "write STATUS RO bits: ignored, no error");
        apb_read(A_STATUS); check((rd & S_TXE) != 0, "STATUS RO bits unchanged");

        // ---- Ket qua ----
        if (errors == 0)
            $display("PASS: uart_apb - TX/RX 8N1, baud, FIFO, loi, ngat, loopback dung");
        else
            $display("FAIL: uart_apb - %0d loi", errors);
        $finish;
    end
endmodule
