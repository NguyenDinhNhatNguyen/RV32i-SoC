// core_tb_map.vh - các vùng địa chỉ mà tb_core và scripts/elf2hex.py dùng.
// Chỉ gồm phần core cần để chạy test: IMEM, DMEM, thanh ghi DATA của UART
// (tb in ký tự ngay) và khối điều khiển ngắt riêng của tb. Bản đồ địa chỉ đầy đủ của SoC do phần bus/bộ nhớ quản
// lý, file này phải khớp với bản đó (docs/spec/core.md mục 10).
// elf2hex.py đọc thẳng các macro CORE_TB_* ở đây, giữ cú pháp `define NAME VALUE.
`ifndef CORE_TB_MAP_VH
`define CORE_TB_MAP_VH

// IMEM (và RESET_PC của core) đổi được khi dịch. riscv-arch-test đặt ở 0x8000_0000
// cho trùng địa chỉ nạp với Spike (docs/riscof.md)
`ifndef CORE_TB_IMEM_BASE
`define CORE_TB_IMEM_BASE      32'h0000_0000
`endif
// IMEM đổi được khi dịch (iverilog -DCORE_TB_IMEM_SIZE=...), riscv-arch-test cần tới 2 MB
`ifndef CORE_TB_IMEM_SIZE
`define CORE_TB_IMEM_SIZE      16384          // byte
`endif
`define CORE_TB_DMEM_BASE      32'h1000_0000
`define CORE_TB_DMEM_SIZE      16384          // byte, stack ở đỉnh
`define CORE_TB_UART_DATA      32'h2000_1000  // UART base + offset DATA
`define CORE_TB_CTRL_BASE      32'h2FFF_0000  // khối điều khiển ngắt của tb, không có trong SoC

`endif // CORE_TB_MAP_VH
