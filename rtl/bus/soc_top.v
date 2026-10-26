`timescale 1ns/1ps
`default_nettype none
// soc_top - RV32I SoC (RTL-09): reset synchronizer, core, bus, memories, peripherals, accelerator.
// Spec: docs/spec/soc_spec.md. Bus and memories: docs/bus_mem.md. Wiring: docs/soc_top.md.
//
//   rv32_core ── instruction port ───────► imem_port (IMEM + boot ROM)
//       └─ data port ─► sys_bus ─┬─► imem_port (data port)
//                                ├─► sram_wrap (DMEM)
//                                └─► apb_bridge ─┬─ slot 0 timer_apb
//                                                ├─ slot 1 uart_apb
//                                                ├─ slot 2 gpio_apb
//                                                ├─ slot 6 irqc_apb
//                                                └─ slot 7 accel_apb
//
// One clock domain. The external reset rst_n goes through reset_sync, and every block
// uses rst_n_sync.
//
// Interrupts: irq_timer and irq_software come from timer_apb (mtime >= mtimecmp, MSIP).
// irq_external comes from the IRQC interrupt controller (RTL-11, slot 6), which gathers the
// UART and accelerator irq lines (bit map SOC_IRQ_* in soc_map.vh).
//
// APB slots without RTL yet: SPI (3), I2C (4), PWM (5), DMA (8). Their APB_EN bit
// is 0, so apb_bridge returns err for every access to them.
// To add a block: connect the slot's PSEL/PRDATA/PREADY/PSLVERR and set its APB_EN bit.
`include "soc_map.vh"

module soc_top #(
    parameter ENABLE_M         = 1,     // RV32M passes rv32um (RTL-12)
    parameter ENABLE_WFI_SLEEP = 1,
    parameter GPIO_W           = 32     // gpio_apb is lint clean only with W = 32
) (
    input  wire              clk,
    input  wire              rst_n,     // External reset, asynchronous, active low

    input  wire [GPIO_W-1:0] gpio_i,
    output wire [GPIO_W-1:0] gpio_o,
    output wire [GPIO_W-1:0] gpio_oe,   // 1 = the pin is an output, pads are added at chip level

    input  wire              uart_rx,   // UART 8N1, 115200 baud at 50 MHz by default
    output wire              uart_tx
);

    localparam NS = `SOC_APB_N;
    localparam [NS-1:0] APB_EN = (9'b1 << `SOC_APB_TIMER) |
                                 (9'b1 << `SOC_APB_UART)  |
                                 (9'b1 << `SOC_APB_GPIO)  |
                                 (9'b1 << `SOC_APB_IRQC)  |
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
    wire        irq_external;           // From IRQC (slot 6)
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

    // Memories
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
        .f_req     (1'b0),              // DMEM has no fetch port
        .f_gnt     (unused_dmem_f_gnt),
        .f_addr    ({(10 + `SOC_DMEM_BANK_W){1'b0}}),
        .f_rdata   (unused_dmem_f_rdata)
    );

    // APB bridge
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

    // Slot 0: CLINT-style timer (RTL-04)
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

    // Slot 7: Lab 2 accelerator behind its APB shell (RTL-05)
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

    // Slot 6: interrupt controller (RTL-11). Sources without RTL yet are tied to 0.
    wire [`SOC_IRQ_N-1:0] irq_src;

    assign irq_src[`SOC_IRQ_UART]  = uart_irq;
    assign irq_src[`SOC_IRQ_ACCEL] = accel_irq;
    assign irq_src[`SOC_IRQ_GPIO]  = 1'b0;
    assign irq_src[`SOC_IRQ_SPI]   = 1'b0;
    assign irq_src[`SOC_IRQ_DMA]   = 1'b0;

    irqc_apb #(.N(`SOC_IRQ_N)) u_irqc (
        .PCLK    (clk),
        .PRESETn (rst_n_sync),
        .PSEL    (psel[`SOC_APB_IRQC]),
        .PENABLE (penable),
        .PWRITE  (pwrite),
        .PADDR   (paddr),
        .PWDATA  (pwdata),
        .PRDATA  (prdata[`SOC_APB_IRQC*32 +: 32]),
        .PREADY  (pready[`SOC_APB_IRQC]),
        .PSLVERR (pslverr[`SOC_APB_IRQC]),
        .irq_src (irq_src),
        .irq     (irq_external)
    );

    // Slots without RTL: never selected (APB_EN = 0), tied to idle values
    assign prdata [`SOC_APB_SPI*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_SPI]           = 1'b1;
    assign pslverr[`SOC_APB_SPI]           = 1'b0;
    assign prdata [`SOC_APB_I2C*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_I2C]           = 1'b1;
    assign pslverr[`SOC_APB_I2C]           = 1'b0;
    assign prdata [`SOC_APB_PWM*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_PWM]           = 1'b1;
    assign pslverr[`SOC_APB_PWM]           = 1'b0;
    assign prdata [`SOC_APB_DMA*32 +: 32]  = 32'h0;
    assign pready [`SOC_APB_DMA]           = 1'b1;
    assign pslverr[`SOC_APB_DMA]           = 1'b0;

    // Unused: PSEL of empty slots, core_sleep (IMEM is already off because if_req = 0
    // while asleep)
    wire unused_ok = &{1'b0, psel[`SOC_APB_SPI], psel[`SOC_APB_I2C],
                       psel[`SOC_APB_PWM], psel[`SOC_APB_DMA], core_sleep};

endmodule

`default_nettype wire
