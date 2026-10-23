`timescale 1ns/1ps
`default_nettype none
// tb_apb_bridge - kiểm tra apb_bridge (RTL-03).
//   - Khe 0, 1, 2, 5, 6: mô hình APB slave có thanh ghi, wait state ngẫu nhiên
//     (PREADY = 0 từ 0 tới 3 chu kỳ), PSLVERR khi offset >= 0x100.
//   - Khe 7: accel_apb thật (accelerator Lab 2 qua wrapper).
//   - Khe 3, 4, 8 tắt bằng APB_EN: phải trả err mà không có giao dịch APB.
//   - Địa chỉ ngoài mọi khe và truy cập không đủ word: err ngay, không có giao dịch APB.
//   - Kiểm tra giao thức APB3: PSEL one-hot, SETUP rồi ACCESS, tín hiệu giữ
//     nguyên khi PREADY = 0, khe tắt không bao giờ được chọn.
//   - Cuối cùng chạy một phép nhân ma trận 4x4 trên accelerator qua cầu và so với phần mềm.
// Plusarg: +seed=<n> +n=<số yêu cầu ngẫu nhiên>
`include "soc_map.vh"

module tb_apb_bridge;

    localparam NS = `SOC_APB_N;
    // Tắt SPI, I2C, DMA
    localparam [NS-1:0] APB_EN = ~((9'b1 << `SOC_APB_SPI) | (9'b1 << `SOC_APB_I2C) | (9'b1 << `SOC_APB_DMA));

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         req_valid = 1'b0;
    wire        req_ready;
    reg  [31:0] req_addr  = 32'h0;
    reg         req_we    = 1'b0;
    reg  [3:0]  req_be    = 4'hF;
    reg  [31:0] req_wdata = 32'h0;
    wire        rsp_valid, rsp_err;
    wire [31:0] rsp_rdata;

    wire [NS-1:0]    psel;
    wire             penable, pwrite;
    wire [11:0]      paddr;
    wire [31:0]      pwdata;
    wire [NS*32-1:0] prdata;
    wire [NS-1:0]    pready, pslverr;

    apb_bridge #(.APB_EN(APB_EN)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_we    (req_we),
        .req_be    (req_be),
        .req_wdata (req_wdata),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata),
        .rsp_err   (rsp_err),
        .psel      (psel),
        .penable   (penable),
        .pwrite    (pwrite),
        .paddr     (paddr),
        .pwdata    (pwdata),
        .prdata    (prdata),
        .pready    (pready),
        .pslverr   (pslverr)
    );

    integer seed = 1, seed0, n_req = 3000;
    integer errors = 0, cycle = 0;

    task fail(input [8*80-1:0] msg);
        begin
            errors = errors + 1;
            if (errors <= 10)
                $display("FAIL: %0s (cycle %0d)", msg, cycle);
        end
    endtask

    // ---------------------------------------------------------- mô hình slave khe thường
    reg  [31:0] regs [0:NS*64-1];       // 64 word mỗi khe
    integer     wait_q = 0;
    integer     i;
    initial for (i = 0; i < NS*64; i = i + 1) regs[i] = 32'h0;

    wire             acc_phase = penable;
    wire             bad_off   = (paddr[11:8] != 4'h0);
    genvar s;
    generate
        for (s = 0; s < NS; s = s + 1) begin : g_slv
            if (s == `SOC_APB_ACCEL) begin : g_accel
                wire unused_irq;
                accel_apb u_accel (
                    .pclk    (clk),
                    .presetn (rst_n),
                    .psel    (psel[s]),
                    .penable (penable),
                    .pwrite  (pwrite),
                    .paddr   (paddr),
                    .pwdata  (pwdata),
                    .prdata  (prdata[s*32 +: 32]),
                    .pready  (pready[s]),
                    .pslverr (pslverr[s]),
                    .irq     (unused_irq)
                );
            end else begin : g_model
                assign pready[s]           = psel[s] & acc_phase & (wait_q == 0);
                assign pslverr[s]          = psel[s] & acc_phase & bad_off;
                assign prdata[s*32 +: 32]  = (psel[s] & acc_phase & ~bad_off) ? regs[s*64 + paddr[7:2]] : 32'hDEAD_BEEF;
            end
        end
    endgenerate

    // Wait state chọn ở pha SETUP, giảm dần ở pha ACCESS. Ghi khi hoàn thành.
    integer  sel_idx;
    always @(*) begin
        sel_idx = -1;
        for (i = 0; i < NS; i = i + 1)
            if (psel[i]) sel_idx = i;
    end

    always @(posedge clk) begin
        if ((|psel) && !penable)
            wait_q <= $unsigned($random(seed)) % 4;
        else if ((|psel) && penable && wait_q != 0)
            wait_q <= wait_q - 1;
        if (sel_idx >= 0 && sel_idx != `SOC_APB_ACCEL && penable && pready[sel_idx] && pwrite && !bad_off)
            regs[sel_idx*64 + paddr[7:2]] <= pwdata;
    end

    // ---------------------------------------------------------- kiểm tra giao thức APB
    reg [NS-1:0] psel_q    = 0;
    reg          penable_q = 1'b0, pwrite_q = 1'b0;
    reg [11:0]   paddr_q   = 12'h0;
    reg [31:0]   pwdata_q  = 32'h0;
    reg          done_q    = 1'b0;     // chu kỳ trước kết thúc một giao dịch
    integer      n_apb     = 0;        // số giao dịch APB đã bắt đầu

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if ((psel & (psel - 1'b1)) != 0)          fail("PSEL khong one-hot");
            if ((psel & ~APB_EN) != 0)                fail("chon khe dang tat");
            if (penable && psel == 0)                 fail("PENABLE khi khong co PSEL");
            if (psel_q != 0 && !penable_q && !done_q) begin
                if (psel !== psel_q || !penable)      fail("SETUP khong chuyen sang ACCESS");
            end
            if (psel_q != 0 && penable_q && !done_q) begin
                if (psel !== psel_q || paddr !== paddr_q || pwrite !== pwrite_q ||
                    (pwrite && pwdata !== pwdata_q) || !penable)
                    fail("tin hieu APB doi khi PREADY = 0");
            end
            if (psel != 0 && !penable) n_apb = n_apb + 1;
            done_q    <= (sel_idx >= 0) && penable && pready[sel_idx];
            psel_q    <= psel;
            penable_q <= penable;
            pwrite_q  <= pwrite;
            paddr_q   <= paddr;
            pwdata_q  <= pwdata;
        end
    end

    // ---------------------------------------------------------- master
    // Đặt yêu cầu ở cạnh xuống, chờ được nhận, rồi chờ phản hồi.
    // lat = số chu kỳ từ lúc nhận tới lúc có rsp_valid, trừ 1.
    integer lat;
    integer apb_before;
    reg [31:0] rd;
    reg        er;

    task xfer(input we, input [31:0] addr, input [3:0] be, input [31:0] wdata);
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_we    = we;
            req_addr  = addr;
            req_be    = be;
            req_wdata = wdata;
            while (req_ready !== 1'b1) @(negedge clk);
            apb_before = n_apb;
            @(negedge clk);
            req_valid = 1'b0;
            req_addr  = 32'hxxxx_xxxx;
            req_wdata = 32'hxxxx_xxxx;
            lat = 0;
            while (rsp_valid !== 1'b1) begin
                @(negedge clk);
                lat = lat + 1;
            end
            rd = rsp_rdata;
            er = rsp_err;
        end
    endtask

    reg [31:0] shadow [0:NS*64-1];      // giá trị kỳ vọng của thanh ghi mô hình
    initial for (i = 0; i < NS*64; i = i + 1) shadow[i] = 32'h0;

    integer n_ok = 0, n_slverr = 0, n_off = 0, n_dis = 0, n_be = 0, n_info = 0;
    integer k, kind, slot;
    reg [31:0] a, w;
    reg [3:0]  be;
    reg        we, exp_err, exp_apb;
    reg [31:0] exp_rd;

    // Phép nhân ma trận cho accelerator
    reg signed [7:0]  ma [0:15];
    reg signed [7:0]  mb [0:15];
    reg signed [31:0] mc;

    initial begin
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("n=%d", n_req)) ;
        seed0 = seed;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        for (k = 0; k < n_req; k = k + 1) begin
            we = $random(seed);
            w  = $random(seed);
            be = 4'hF;
            kind = $unsigned($random(seed)) % 20;
            exp_err = 1'b0; exp_apb = 1'b1; exp_rd = 32'h0;
            if (kind < 12) begin                        // thanh ghi khe thường
                case ($unsigned($random(seed)) % 5)
                    0: slot = 0; 1: slot = 1; 2: slot = 2; 3: slot = 5; default: slot = 6;
                endcase
                a = (`SOC_TIMER_BASE + slot * 32'h1000) + (($unsigned($random(seed)) % 64) << 2);
                if (!we) exp_rd = shadow[slot*64 + a[7:2]];
                else     shadow[slot*64 + a[7:2]] = w;
                n_ok = n_ok + 1;
            end else if (kind < 14) begin               // PSLVERR từ slave
                case ($unsigned($random(seed)) % 3)
                    0: a = 32'h2000_0100 + (($unsigned($random(seed)) % 960) << 2);
                    1: a = 32'h2000_6F00;
                    default: begin a = 32'h3000_0400; end        // accel_apb báo lỗi
                endcase
                exp_err = 1'b1;
                n_slverr = n_slverr + 1;
            end else if (kind < 16) begin               // ngoài mọi khe
                case ($unsigned($random(seed)) % 5)
                    0: a = 32'h2000_7000 + ($unsigned($random(seed)) % 9) * 32'h1000;
                    1: a = 32'h2001_0000;
                    2: a = 32'h3000_1000;
                    3: a = 32'h4001_0000;
                    default: a = 32'h5000_0000;
                endcase
                exp_err = 1'b1; exp_apb = 1'b0;
                n_off = n_off + 1;
            end else if (kind < 18) begin               // khe tắt
                case ($unsigned($random(seed)) % 3)
                    0: a = `SOC_SPI_BASE;
                    1: a = `SOC_I2C_BASE + 32'h10;
                    default: a = `SOC_DMA_BASE;
                endcase
                exp_err = 1'b1; exp_apb = 1'b0;
                n_dis = n_dis + 1;
            end else if (kind < 19) begin               // không đủ word
                a  = `SOC_UART_BASE;
                be = ($unsigned($random(seed)) % 2) ? 4'b0001 : 4'b0011;
                exp_err = 1'b1; exp_apb = 1'b0;
                n_be = n_be + 1;
            end else begin                              // đọc INFO của accelerator
                a = `SOC_ACCEL_BASE + 32'h8;
                we = 1'b0;
                exp_rd = {8'd4, 8'd8, 8'd20, 8'd10};
                n_info = n_info + 1;
            end

            xfer(we, a, be, w);
            if (er !== exp_err) begin
                $display("      addr %h we %b be %b: err %b, mong doi %b", a, we, be, er, exp_err);
                fail("err sai");
            end
            if (!exp_err && !we && rd !== exp_rd) begin
                $display("      addr %h: doc %h, mong doi %h", a, rd, exp_rd);
                fail("du lieu doc sai");
            end
            if ((we || exp_err) && rd !== 32'h0)
                fail("rdata khac 0 khi ghi hoac loi");
            if (!exp_apb && (n_apb != apb_before || lat != 0))
                fail("loi ngay phai tra o chu ky sau, khong co giao dich APB");
            if (exp_apb && (n_apb != apb_before + 1 || lat < 2))
                fail("giao dich APB sai so luong hoac qua nhanh");
        end

        // ------------------------------------------- nhân ma trận trên accelerator
        for (k = 0; k < 16; k = k + 1) begin
            ma[k] = $random(seed);
            mb[k] = $random(seed);
        end
        for (k = 0; k < 4; k = k + 1) begin
            xfer(1'b1, `SOC_ACCEL_BASE + 32'h100 + 4*k, 4'hF, {ma[4*k+3], ma[4*k+2], ma[4*k+1], ma[4*k]});
            xfer(1'b1, `SOC_ACCEL_BASE + 32'h200 + 4*k, 4'hF, {mb[4*k+3], mb[4*k+2], mb[4*k+1], mb[4*k]});
        end
        xfer(1'b1, `SOC_ACCEL_BASE + 32'h0, 4'hF, 32'h1);           // START
        rd = 32'h0;
        k  = 0;
        while (!rd[1] && k < 100) begin
            xfer(1'b0, `SOC_ACCEL_BASE + 32'h4, 4'hF, 32'h0);       // STATUS
            k = k + 1;
        end
        if (!rd[1]) fail("accelerator khong bao DONE");
        for (k = 0; k < 16; k = k + 1) begin
            mc = ma[(k/4)*4+0] * mb[0*4 + k%4] + ma[(k/4)*4+1] * mb[1*4 + k%4] +
                 ma[(k/4)*4+2] * mb[2*4 + k%4] + ma[(k/4)*4+3] * mb[3*4 + k%4];
            xfer(1'b0, `SOC_ACCEL_BASE + 32'h300 + 4*k, 4'hF, 32'h0);
            if (er || rd !== mc) begin
                $display("      C[%0d] = %h, mong doi %h", k, rd, mc);
                fail("ket qua accelerator sai");
            end
        end
        xfer(1'b1, `SOC_ACCEL_BASE + 32'h300, 4'hF, 32'h0);         // ghi C_BUF: PSLVERR
        if (!er) fail("ghi C_BUF phai loi");

        repeat (3) @(posedge clk);
        if (errors == 0)
            $display("PASS: tb_apb_bridge: %0d doc/ghi khe thuong, %0d PSLVERR, %0d ngoai khe, %0d khe tat, %0d khong du word, %0d doc INFO, nhan ma tran tren accel_apb dung (seed %0d)",
                     n_ok, n_slverr, n_off, n_dis, n_be, n_info, seed0);
        else
            $display("FAIL: tb_apb_bridge: %0d loi (seed %0d)", errors, seed0);
        $finish;
    end

endmodule

`default_nettype wire
