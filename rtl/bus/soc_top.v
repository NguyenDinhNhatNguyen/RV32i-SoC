`timescale 1ns/1ps
`default_nettype none
// soc_top - SoC RV32I (RTL-09): bộ đồng bộ reset, core, bus, bộ nhớ, ngoại vi, accelerator.
// Đặc tả: docs/spec/soc_spec.md. Bus và bộ nhớ: docs/bus_mem.md. Sơ đồ nối: docs/soc_top.md.
//
//   rv32_core ── cổng lệnh ──────────────► imem_port (IMEM + boot ROM)
//       └─ cổng dữ liệu ─► sys_bus ─┬─► imem_port (cổng dữ liệu)
//                                   ├─► sram_wrap (DMEM)
//                                   └─► apb_bridge ─┬─ khe 0 timer_apb
//                                                   ├─ khe 1 uart_apb
//                                                   ├─ khe 2 gpio_apb
//                                                   └─ khe 7 accel_apb
//
// Một miền clock. Reset ngoài rst_n qua reset_sync, mọi khối dùng rst_n_sync.
//
// Ngắt: irq_timer và irq_software từ timer_apb (mtime >= mtimecmp, MSIP).
// irq_external chờ bộ gom ngắt IRQC (RTL-11, khe 6), tạm nối 0. irq của
// UART và accelerator đã kéo tới đây để nối vào IRQC.
//
// Khe APB chưa có RTL: SPI (3), I2C (4), PWM (5), IRQC (6), DMA (8). Bit APB_EN = 0
// nên apb_bridge trả err cho mọi truy cập vào đó.
// Thêm khối mới: nối PSEL/PRDATA/PREADY/PSLVERR của khe và bật bit trong APB_EN.
`include "soc_map.vh"

module soc_top #(
    parameter ENABLE_M         = 1,     // RV32M đã pass rv32um (RTL-12)
    parameter ENABLE_WFI_SLEEP = 1,
    parameter GPIO_W           = 32     // gpio_apb chỉ lint sạch với W = 32
) (
    input  wire              clk,
    input  wire              rst_n,     // reset ngoài, bất đồng bộ, tích cực thấp

    input  wire [GPIO_W-1:0] gpio_i,
    output wire [GPIO_W-1:0] gpio_o,
    output wire [GPIO_W-1:0] gpio_oe,   // 1 = chân là ngõ ra, pad nối ở mức chip

    input  wire              uart_rx,   // UART 8N1, mặc định 115200 baud ở 50 MHz
    output wire              uart_tx
);

    localparam NS = `SOC_APB_N;
    localparam [NS-1:0] APB_EN = (9'b1 << `SOC_APB_TIMER) |
                                 (9'b1 << `SOC_APB_UART)  |
                                 (9'b1 << `SOC_APB_GPIO)  |
                                 (9'b1 << `SOC_APB_ACCEL);

    // Reset
    wire rst_n_sync;

    reset_sync u_rst (
        .clk     (clk),
        .rst_n_i (rst_n),
        .rst_n_o (rst_n_sync)
    );

    // Core
    wire        if_req, if_gnt, if_err;
    wire [31:0] if_addr, if_rdata;
    wire        d_req_valid, d_req_ready, d_we;
    wire [31:0] d_addr, d_wdata;
    wire [3:0]  d_be;
    wire        d_rsp_valid, d_rsp_err;
    wire [31:0] d_rsp_rdata;
    wire        irq_timer, irq_software;
    wire        irq_external = 1'b0;    // chờ IRQC (RTL-11)
    wire [63:0] mtime;
    wire        core_sleep;

    rv32_core #(
        .ENABLE_M         (ENABLE_M),
        .ENABLE_WFI_SLEEP (ENABLE_WFI_SLEEP)
    ) u_core (
        .clk            (clk),
        .rst_n          (rst_n_sync),
        .if_req_o       (if_req),
        .if_addr_o      (if_addr),
        .if_gnt_i       (if_gnt),
        .if_rdata_i     (if_rdata),
        .if_err_i       (if_err),
        .d_req_valid_o  (d_req_valid),
        .d_req_ready_i  (d_req_ready),
        .d_addr_o       (d_addr),
        .d_we_o         (d_we),
        .d_be_o         (d_be),
        .d_wdata_o      (d_wdata),
        .d_rsp_valid_i  (d_rsp_valid),
        .d_rsp_rdata_i  (d_rsp_rdata),
        .d_rsp_err_i    (d_rsp_err),
        .irq_software_i (irq_software),
        .irq_timer_i    (irq_timer),
        .irq_external_i (irq_external),
        .mtime_i        (mtime),
        .core_sleep_o   (core_sleep)
    );

    // Bus
    wire [31:0] s_addr, s_wdata;
    wire        s_we;
    wire [3:0]  s_be;
    wire        imem_v, imem_r, imem_rv;
    wire        dmem_v, dmem_r, dmem_rv;
    wire        apb_v, apb_r, apb_rv, apb_e;
    wire [31:0] imem_rd, dmem_rd, apb_rd;

    sys_bus #(
        .N_MASTER    (1),
        .IMEM_BANK_W (`SOC_IMEM_BANK_W),
        .DMEM_BANK_W (`SOC_DMEM_BANK_W)
    ) u_bus (
        .clk            (clk),
        .rst_n          (rst_n_sync),
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

    // Bộ nhớ
    imem_port #(.BANK_W(`SOC_IMEM_BANK_W)) u_imem (
        .clk       (clk),
        .rst_n     (rst_n_sync),
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

    wire        unused_dmem_f_gnt;
    wire [31:0] unused_dmem_f_rdata;

    sram_wrap #(.BANK_W(`SOC_DMEM_BANK_W)) u_dmem (
        .clk       (clk),
        .rst_n     (rst_n_sync),
        .req_valid (dmem_v),
        .req_ready (dmem_r),
        .req_addr  (s_addr),
        .req_we    (s_we),
        .req_be    (s_be),
        .req_wdata (s_wdata),
        .rsp_valid (dmem_rv),
        .rsp_rdata (dmem_rd),
        .f_req     (1'b0),              // DMEM không có cổng lấy lệnh
        .f_gnt     (unused_dmem_f_gnt),
        .f_addr    ({(10 + `SOC_DMEM_BANK_W){1'b0}}),
        .f_rdata   (unused_dmem_f_rdata)
    );

    // Cầu APB
    wire [NS-1:0]    psel;
    wire             penable, pwrite;
    wire [11:0]      paddr;
    wire [31:0]      pwdata;
    wire [NS*32-1:0] prdata;
    wire [NS-1:0]    pready, pslverr;

    apb_bridge #(.APB_EN(APB_EN)) u_apb (
        .clk       (clk),
        .rst_n     (rst_n_sync),
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

    // Khe 0: Timer kiểu CLINT (RTL-04)
    timer_apb u_timer (
        .PCLK         (clk),
        .PRESETn      (rst_n_sync),
        .PSEL         (psel[`SOC_APB_TIMER]),
        .PENABLE      (penable),
        .PWRITE       (pwrite),
        .PADDR        (paddr),
        .PWDATA       (pwdata),
        .PRDATA       (prdata[`SOC_APB_TIMER*32 +: 32]),
        .PREADY       (pready[`SOC_APB_TIMER]),
        .PSLVERR      (pslverr[`SOC_APB_TIMER]),
        .irq_timer    (irq_timer),
        .irq_software (irq_software),
        .mtime_o      (mtime)
    );

    // Khe 1: UART 8N1 (RTL-10)
    wire uart_irq;

    uart_apb u_uart (
        .PCLK     (clk),
        .PRESETn  (rst_n_sync),
        .PSEL     (psel[`SOC_APB_UART]),
        .PENABLE  (penable),
        .PWRITE   (pwrite),
        .PADDR    (paddr),
        .PWDATA   (pwdata),
        .PRDATA   (prdata[`SOC_APB_UART*32 +: 32]),
        .PREADY   (pready[`SOC_APB_UART]),
        .PSLVERR  (pslverr[`SOC_APB_UART]),
        .uart_txd (uart_tx),
        .uart_rxd (uart_rx),
        .irq      (uart_irq)
    );

    // Khe 2: GPIO (RTL-04)
    gpio_apb #(.W(GPIO_W)) u_gpio (
        .PCLK    (clk),
        .PRESETn (rst_n_sync),
        .PSEL    (psel[`SOC_APB_GPIO]),
        .PENABLE (penable),
        .PWRITE  (pwrite),
        .PADDR   (paddr),
        .PWDATA  (pwdata),
        .PRDATA  (prdata[`SOC_APB_GPIO*32 +: 32]),
        .PREADY  (pready[`SOC_APB_GPIO]),
        .PSLVERR (pslverr[`SOC_APB_GPIO]),
        .gpio_i  (gpio_i),
        .gpio_o  (gpio_o),
        .gpio_oe (gpio_oe)
    );

    // Khe 7: accelerator Lab 2 qua lớp vỏ APB (RTL-05)
    wire accel_irq;

    accel_apb u_accel (
        .pclk    (clk),
        .presetn (rst_n_sync),
        .psel    (psel[`SOC_APB_ACCEL]),
        .penable (penable),
        .pwrite  (pwrite),
        .paddr   (paddr),
        .pwdata  (pwdata),
        .prdata  (prdata[`SOC_APB_ACCEL*32 +: 32]),
        .pready  (pready[`SOC_APB_ACCEL]),
        .pslverr (pslverr[`SOC_APB_ACCEL]),
        .irq     (accel_irq)
    );

    // Khe chưa có RTL: không bao giờ được chọn (APB_EN = 0), nối giá trị rảnh
    assign prdata [`SOC_APB_SPI*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_SPI]           = 1'b1;
    assign pslverr[`SOC_APB_SPI]           = 1'b0;
    assign prdata [`SOC_APB_I2C*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_I2C]           = 1'b1;
    assign pslverr[`SOC_APB_I2C]           = 1'b0;
    assign prdata [`SOC_APB_PWM*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_PWM]           = 1'b1;
    assign pslverr[`SOC_APB_PWM]           = 1'b0;
    assign prdata [`SOC_APB_IRQC*32 +: 32] = 32'h0;
    assign pready [`SOC_APB_IRQC]          = 1'b1;
    assign pslverr[`SOC_APB_IRQC]          = 1'b0;
    assign prdata [`SOC_APB_DMA*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_DMA]           = 1'b1;
    assign pslverr[`SOC_APB_DMA]           = 1'b0;

    // Chưa dùng: PSEL của khe trống, irq của UART và accelerator chờ IRQC,
    // core_sleep (IMEM đã tắt nhờ if_req = 0 khi ngủ)
    wire unused_ok = &{1'b0, psel[`SOC_APB_SPI], psel[`SOC_APB_I2C],
                       psel[`SOC_APB_PWM], psel[`SOC_APB_IRQC], psel[`SOC_APB_DMA],
                       uart_irq, accel_irq, core_sleep};

endmodule

`default_nettype wire
