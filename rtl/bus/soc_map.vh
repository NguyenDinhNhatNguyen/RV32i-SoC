// soc_map.vh - SoC address map (docs/spec/soc_spec.md section 3).
// Single source for sys_bus, apb_bridge, imem_port and soc_top.
// tb/core/core_tb_map.vh and fw/common/link.ld must match the values here.
// No `timescale or `default_nettype, because this file is included in the middle of .v files.
`ifndef SOC_MAP_VH
`define SOC_MAP_VH

// Region selected by addr[31:28]
`define SOC_RGN_MEM0        4'h0            // IMEM and boot ROM
`define SOC_RGN_DMEM        4'h1
`define SOC_RGN_PERIPH      4'h2            // APB peripherals, block selected by addr[15:12]
`define SOC_RGN_ACCEL       4'h3
`define SOC_RGN_DMA         4'h4

// Memories. Default is option C of SoC spec section 7.2: each region is 16 KB = 4
// sram_2k_macro (1024 x 32 bit = 4 KB). Macro count = 2^BANK_W, size = 4096 << BANK_W bytes.
// To change the option, edit BANK_W and SIZE together (A: 0 and 4096, B: 1 and 8192).
// IMEM is at most 64 KB (BANK_W <= 4) so it does not overlap the boot ROM.
`define SOC_IMEM_BANK_W     2
`define SOC_DMEM_BANK_W     2
`define SOC_IMEM_BASE       32'h0000_0000
`define SOC_IMEM_SIZE       32'd16384
`define SOC_BOOT_BASE       32'h0001_0000   // rv32_core reset vector, fetch port reads only
`define SOC_BOOT_SIZE       32'd1024
`define SOC_DMEM_BASE       32'h1000_0000
`define SOC_DMEM_SIZE       32'd16384

// Peripherals, 4 KB each
`define SOC_TIMER_BASE      32'h2000_0000
`define SOC_UART_BASE       32'h2000_1000
`define SOC_GPIO_BASE       32'h2000_2000
`define SOC_SPI_BASE        32'h2000_3000
`define SOC_I2C_BASE        32'h2000_4000
`define SOC_PWM_BASE        32'h2000_5000
`define SOC_IRQC_BASE       32'h2000_6000   // Simple interrupt controller (RTL-11)
`define SOC_ACCEL_BASE      32'h3000_0000
`define SOC_DMA_BASE        32'h4000_0000

// APB slot index (bit of PSEL in apb_bridge). Slots 0..6 equal addr[15:12] in region 0x2.
`define SOC_APB_TIMER       0
`define SOC_APB_UART        1
`define SOC_APB_GPIO        2
`define SOC_APB_SPI         3
`define SOC_APB_I2C         4
`define SOC_APB_PWM         5
`define SOC_APB_IRQC        6
`define SOC_APB_ACCEL       7
`define SOC_APB_DMA         8
`define SOC_APB_N           9

`endif
