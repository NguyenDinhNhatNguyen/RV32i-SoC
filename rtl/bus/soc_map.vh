// soc_map.vh - bản đồ địa chỉ SoC (docs/spec/soc_spec.md mục 3).
// Nguồn duy nhất cho sys_bus, apb_bridge, imem_port và soc_top.
// tb/core/core_tb_map.vh và fw/common/link.ld phải khớp các giá trị ở đây.
// Không có `timescale hay `default_nettype vì file được include vào giữa file .v.
`ifndef SOC_MAP_VH
`define SOC_MAP_VH

// Vùng chọn bằng addr[31:28]
`define SOC_RGN_MEM0        4'h0            // IMEM và boot ROM
`define SOC_RGN_DMEM        4'h1
`define SOC_RGN_PERIPH      4'h2            // ngoại vi APB, khối chọn bằng addr[15:12]
`define SOC_RGN_ACCEL       4'h3
`define SOC_RGN_DMA         4'h4

// Bộ nhớ. Mặc định phương án C của spec SoC mục 7.2: mỗi vùng 16 KB = 4 macro
// sram_2k_macro (1024 x 32 bit = 4 KB). Số macro = 2^BANK_W, kích thước = 4096 << BANK_W byte.
// Đổi phương án thì sửa BANK_W và SIZE cùng lúc (A: 0 và 4096, B: 1 và 8192).
// IMEM tối đa 64 KB (BANK_W <= 4) để không chồng lên boot ROM.
`define SOC_IMEM_BANK_W     2
`define SOC_DMEM_BANK_W     2
`define SOC_IMEM_BASE       32'h0000_0000
`define SOC_IMEM_SIZE       32'd16384
`define SOC_BOOT_BASE       32'h0001_0000   // reset vector của rv32_core, chỉ cổng lệnh đọc được
`define SOC_BOOT_SIZE       32'd1024
`define SOC_DMEM_BASE       32'h1000_0000
`define SOC_DMEM_SIZE       32'd16384

// Ngoại vi, mỗi khối 4 KB
`define SOC_TIMER_BASE      32'h2000_0000
`define SOC_UART_BASE       32'h2000_1000
`define SOC_GPIO_BASE       32'h2000_2000
`define SOC_SPI_BASE        32'h2000_3000
`define SOC_I2C_BASE        32'h2000_4000
`define SOC_PWM_BASE        32'h2000_5000
`define SOC_IRQC_BASE       32'h2000_6000   // bộ gom ngắt rút gọn (RTL-11)
`define SOC_ACCEL_BASE      32'h3000_0000
`define SOC_DMA_BASE        32'h4000_0000

// Chỉ số khe APB (bit của PSEL trong apb_bridge). Khe 0..6 trùng addr[15:12] của vùng 0x2.
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
