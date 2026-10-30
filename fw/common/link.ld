/* link.ld - memory layout for programs running from IMEM (docs/spec/core.md section 10.1).
 * .text in IMEM from 0x0000_0000. .rodata, .data, .bss, .tohost and the stack in DMEM.
 * Load address = run address: the testbench (or the P8 bootloader) loads IMEM
 * and DMEM directly, and nothing is copied at startup.
 * Sizes must match CORE_TB_IMEM_SIZE / CORE_TB_DMEM_SIZE in
 * tb/core/core_tb_map.vh.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    DMEM (rw)  : ORIGIN = 0x10000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text.init)               /* _start must come first */
        *(.text .text.*)
    } > IMEM

    .rodata : ALIGN(4) {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > DMEM

    .data : ALIGN(4) {
        *(.data .data.*)
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
    } > DMEM

    .tohost : ALIGN(64) {
        *(.tohost)
    } > DMEM

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.* .bss .bss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

    /* Some riscv gcc builds (Vitis on the school server) add .note.gnu.build-id. With no
     * output section for it the linker puts it at address 0, before _start.
     */
    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.note.*)
    }
}
