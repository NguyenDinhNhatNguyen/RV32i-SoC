/* link.ld - riscv-arch-test on tb_core. Every section is in IMEM, as in fw/common/link_isa.ld:
 * the Zifencei tests write instructions into the data region and jump there, but the core
 * fetches only from IMEM.
 * IMEM starts at 0x8000_0000 (tb_core_arch_*.vvp is compiled with this CORE_TB_IMEM_BASE),
 * the same load address as Spike, because the signature of some tests (misalign-jal-01)
 * depends on addresses. The IMEM size is set by tb_core (CORE_TB_IMEM_SIZE).
 */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

SECTIONS
{
    . = 0x80000000;
    .text.init : { *(.text.init) }
    . = ALIGN(64);
    .tohost : { *(.tohost) }
    .text : { *(.text) }
    . = ALIGN(64);
    .data : { *(.data) }
    .data.string : { *(.data.string) }
    .bss : { *(.bss) }
    _end = .;
}
