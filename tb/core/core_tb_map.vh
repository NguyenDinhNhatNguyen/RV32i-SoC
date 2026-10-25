// core_tb_map.vh - address regions used by tb_core and scripts/elf2hex.py.
// Only what the core needs to run tests: IMEM, DMEM, the UART DATA register
// (the tb prints characters at once) and the tb's own interrupt control block. The full
// SoC address map belongs to the bus/memory side, and this file must match it
// (docs/spec/core.md section 10).
// elf2hex.py reads the CORE_TB_* macros here directly, so keep the `define NAME VALUE syntax.
`ifndef CORE_TB_MAP_VH
`define CORE_TB_MAP_VH

// IMEM (and the core RESET_PC) can change at compile time. riscv-arch-test puts it at
// 0x8000_0000
// to match the Spike load address (docs/riscof.md)
`ifndef CORE_TB_IMEM_BASE
`define CORE_TB_IMEM_BASE      32'h0000_0000
`endif
// IMEM can change at compile time (iverilog -DCORE_TB_IMEM_SIZE=...), riscv-arch-test
// needs up to 2 MB
`ifndef CORE_TB_IMEM_SIZE
`define CORE_TB_IMEM_SIZE      16384          // byte
`endif
`define CORE_TB_DMEM_BASE      32'h1000_0000
`define CORE_TB_DMEM_SIZE      16384          // Bytes, stack at the top
`define CORE_TB_UART_DATA      32'h2000_1000  // UART base + offset DATA
`define CORE_TB_CTRL_BASE      32'h2FFF_0000  // tb interrupt control block, not in the SoC

`endif // CORE_TB_MAP_VH
