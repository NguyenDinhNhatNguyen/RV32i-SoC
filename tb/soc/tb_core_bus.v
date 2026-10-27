`timescale 1ns/1ps
`default_nettype none
// tb_core_bus - rv32_core on the real SoC bus and memories (RTL-03, RTL-08):
// sys_bus, imem_port (IMEM 4 macros + boot ROM), sram_wrap (DMEM 4 macros),
// apb_bridge with a fake UART in the tb (slot 1) and accel_apb (slot 7).
// Not soc_top (that is tb_soc.v): no reset synchronizer, Timer, GPIO or interrupt controller.
//
// The core boots at the default RESET_PC 0x0001_0000. The UART bootloader reads the boot strap
// from GPIO, there is no GPIO here, so the bus error traps to its mtvec, which jumps to IMEM.
// Memory images (elf2hex.py, 16 KB per region) load straight into the sram_2k_macro model
// by hierarchical reference. Result rules, as in tb_core:
//   - Write to tohost: 1 = PASS, another odd value = FAIL, error code = value >> 1
//   - A trap while mtvec is still 0: FAIL
//   - Timeout: FAIL
// Fake UART: a word write to offset 0 of the UART slot prints the low byte as a character.
// It has 1 wait state cycle (PREADY = 0) to exercise the APB path with wait states.
//
// Plusargs: +imem=<hex> +dmem=<hex> +tohost=<hex> +test=<name> +timeout=<cycles>
`include "soc_map.vh"

module tb_core_bus;

    parameter ENABLE_M         = 1;
    parameter ENABLE_WFI_SLEEP = 1;
    localparam BANK_W          = 2;        // 16 KB per region, matches core_tb_map.vh and link.ld
    localparam WORDS           = 1024 << BANK_W;

    reg clk   = 1'b0;
    reg rst_n = 1'b1;
    always #5 clk = ~clk;
    initial #1 rst_n = 1'b0;    // Async reset acts before the first clock edge

    // ---------------------------------------------------------- core
    wire        if_req, if_gnt, if_err;
    wire [31:0] if_addr, if_rdata;
    wire        d_req_valid, d_req_ready, d_we;
    wire [31:0] d_addr, d_wdata;
    wire [3:0]  d_be;
    wire        d_rsp_valid, d_rsp_err;
    wire [31:0] d_rsp_rdata;
    reg  [63:0] mtime = 64'h0;
    wire        core_sleep;
    wire        accel_irq;

    rv32_core #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP)
    ) u_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .if_req_o      (if_req),
        .if_addr_o     (if_addr),
        .if_gnt_i      (if_gnt),
        .if_rdata_i    (if_rdata),
        .if_err_i      (if_err),
        .d_req_valid_o (d_req_valid),
        .d_req_ready_i (d_req_ready),
        .d_addr_o      (d_addr),
        .d_we_o        (d_we),
        .d_be_o        (d_be),
        .d_wdata_o     (d_wdata),
        .d_rsp_valid_i (d_rsp_valid),
        .d_rsp_rdata_i (d_rsp_rdata),
        .d_rsp_err_i   (d_rsp_err),
        .irq_software_i(1'b0),
        .irq_timer_i   (1'b0),
        .irq_external_i(1'b0),
        .mtime_i       (mtime),
        .core_sleep_o  (core_sleep)
    );

    // ---------------------------------------------------------- bus
    wire [31:0] s_addr, s_wdata;
    wire        s_we;
    wire [3:0]  s_be;
    wire        imem_v, imem_r, imem_rv, dmem_v, dmem_r, dmem_rv, apb_v, apb_r, apb_rv, apb_e;
    wire [31:0] imem_rd, dmem_rd, apb_rd;

    sys_bus #(.N_MASTER(1), .IMEM_BANK_W(BANK_W), .DMEM_BANK_W(BANK_W)) u_bus (
        .clk            (clk),
        .rst_n          (rst_n),
        .m_req_valid    (d_req_valid),
        .m_req_ready    (d_req_ready),
        .m_addr         (d_addr),
        .m_we           (d_we),
        .m_be           (d_be),
        .m_wdata        (d_wdata),
        .m_rsp_valid    (d_rsp_valid),
        .m_rsp_rdata    (d_rsp_rdata),
        .m_rsp_err      (d_rsp_err),
        .s_addr         (s_addr),
        .s_we           (s_we),
        .s_be           (s_be),
        .s_wdata        (s_wdata),
        .imem_req_valid (imem_v),
        .imem_req_ready (imem_r),
        .imem_rsp_valid (imem_rv),
        .imem_rsp_rdata (imem_rd),
        .dmem_req_valid (dmem_v),
        .dmem_req_ready (dmem_r),
        .dmem_rsp_valid (dmem_rv),
        .dmem_rsp_rdata (dmem_rd),
        .apb_req_valid  (apb_v),
        .apb_req_ready  (apb_r),
        .apb_rsp_valid  (apb_rv),
        .apb_rsp_rdata  (apb_rd),
        .apb_rsp_err    (apb_e)
    );

    imem_port #(.BANK_W(BANK_W)) u_imem (
        .clk       (clk),
        .rst_n     (rst_n),
        .if_req    (if_req),
        .if_addr   (if_addr),
        .if_gnt    (if_gnt),
        .if_rdata  (if_rdata),
        .if_err    (if_err),
        .req_valid (imem_v),
        .req_ready (imem_r),
        .req_addr  (s_addr),
        .req_we    (s_we),
        .req_be    (s_be),
        .req_wdata (s_wdata),
        .rsp_valid (imem_rv),
        .rsp_rdata (imem_rd)
    );

    wire        unused_f_gnt;
    wire [31:0] unused_f_rdata;

    sram_wrap #(.BANK_W(BANK_W)) u_dmem (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (dmem_v),
        .req_ready (dmem_r),
        .req_addr  (s_addr),
        .req_we    (s_we),
        .req_be    (s_be),
        .req_wdata (s_wdata),
        .rsp_valid (dmem_rv),
        .rsp_rdata (dmem_rd),
        .f_req     (1'b0),
        .f_gnt     (unused_f_gnt),
        .f_addr    ({(10+BANK_W){1'b0}}),
        .f_rdata   (unused_f_rdata)
    );

    // ---------------------------------------------------------- APB
    localparam NS = `SOC_APB_N;
    localparam [NS-1:0] APB_EN = (9'b1 << `SOC_APB_UART) | (9'b1 << `SOC_APB_ACCEL);

    wire [NS-1:0]    psel;
    wire             penable, pwrite;
    wire [11:0]      paddr;
    wire [31:0]      pwdata;
    reg  [NS*32-1:0] prdata;
    reg  [NS-1:0]    pready, pslverr;
    wire [31:0]      accel_prdata;
    wire             accel_pready, accel_pslverr;

    apb_bridge #(.APB_EN(APB_EN)) u_apb (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (apb_v),
        .req_ready (apb_r),
        .req_addr  (s_addr),
        .req_we    (s_we),
        .req_be    (s_be),
        .req_wdata (s_wdata),
        .rsp_valid (apb_rv),
        .rsp_rdata (apb_rd),
        .rsp_err   (apb_e),
        .psel      (psel),
        .penable   (penable),
        .pwrite    (pwrite),
        .paddr     (paddr),
        .pwdata    (pwdata),
        .prdata    (prdata),
        .pready    (pready),
        .pslverr   (pslverr)
    );

    accel_apb u_accel (
        .pclk    (clk),
        .presetn (rst_n),
        .psel    (psel[`SOC_APB_ACCEL]),
        .penable (penable),
        .pwrite  (pwrite),
        .paddr   (paddr),
        .pwdata  (pwdata),
        .prdata  (accel_prdata),
        .pready  (accel_pready),
        .pslverr (accel_pslverr),
        .irq     (accel_irq)
    );

    // Fake UART: 1 wait state cycle, reads return 0
    reg uart_wait_q = 1'b0;
    always @(posedge clk)
        uart_wait_q <= psel[`SOC_APB_UART] & ~penable;

    always @(*) begin
        prdata  = {NS*32{1'b0}};
        pready  = {NS{1'b1}};
        pslverr = {NS{1'b0}};
        pready[`SOC_APB_UART]                  = ~uart_wait_q;
        prdata[`SOC_APB_ACCEL*32 +: 32]        = accel_prdata;
        pready[`SOC_APB_ACCEL]                 = accel_pready;
        pslverr[`SOC_APB_ACCEL]                = accel_pslverr;
    end

    always @(posedge clk)
        if (psel[`SOC_APB_UART] && penable && !uart_wait_q && pwrite && paddr == 12'h0) begin
            $write("%c", pwdata[7:0]);
            $fflush;
        end

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
                #1;
                for (j = 0; j < 1024; j = j + 1) begin
                    u_imem.u_sram.u_arr.g_multi.g_bank[gb].u_mac.mem[j] = img_i[gb*1024 + j];
                    u_dmem.u_arr.g_multi.g_bank[gb].u_mac.mem[j]        = img_d[gb*1024 + j];
                end
            end
        end
    endgenerate

    // ---------------------------------------------------------- end of test
    integer     cycle   = 0;
    integer     instret = 0;
    integer     timeout = 200000;
    integer     n_imem_data = 0, n_apb = 0, n_part = 0, n_boot = 0;
    reg  [31:0] tohost  = 32'hFFFF_FFFF;
    reg  [8*64-1:0] test_name = "core_bus";
    reg  [8*128-1:0] msg;
    reg         done    = 1'b0;

    task end_test(input pass, input [8*128-1:0] why);
        begin
            if (!done) begin
                done = 1'b1;
                if (pass)
                    $display("PASS: %0s (cycles %0d, instret %0d, CPI %0.3f, IMEM data %0d, APB %0d, byte/half writes %0d)",
                             test_name, cycle, instret, (instret > 0) ? (1.0 * cycle / instret) : 0.0,
                             n_imem_data, n_apb, n_part);
                else
                    $display("FAIL: %0s: %0s (cycle %0d, instret %0d)", test_name, why, cycle, instret);
                $finish;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            mtime <= mtime + 64'd1;
            if (cycle >= timeout)
                end_test(1'b0, "timeout");
            if (u_core.wb_retire && !u_core.wb_trap)
                instret = instret + 1;
            if (u_core.wb_trap && u_core.csr_mtvec == 32'h0) begin
                $sformat(msg, "trap at pc %08h (instr %08h) with no handler", u_core.wb_pc_q, u_core.wb_instr_q);
                end_test(1'b0, msg);
            end
            if (if_req && if_gnt && if_addr[31:16] == 16'h0001)
                n_boot = n_boot + 1;
            if (imem_v && imem_r) n_imem_data = n_imem_data + 1;
            if (apb_v && apb_r)   n_apb = n_apb + 1;
            if (d_req_valid && d_req_ready && d_we && d_be != 4'hF) n_part = n_part + 1;
            if (d_req_valid && d_req_ready && d_we && d_addr == tohost) begin
                if (n_boot == 0)
                    end_test(1'b0, "did not get past the boot ROM");
                else if (d_wdata == 32'd1)
                    end_test(1'b1, "");
                else begin
                    $sformat(msg, "tohost = 0x%08h (test %0d)", d_wdata, d_wdata >> 1);
                    end_test(1'b0, msg);
                end
            end
        end
    end

    initial begin
        if ($value$plusargs("timeout=%d", timeout)) ;
        if ($value$plusargs("tohost=%h", tohost)) ;
        if ($value$plusargs("test=%s", test_name)) ;
        if (tohost == 32'hFFFF_FFFF)
            $display("WARNING: no +tohost=, the test can only end by timeout");
        repeat (5) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
    end

endmodule

`default_nettype wire
