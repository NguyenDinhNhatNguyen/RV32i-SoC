/* link_isa.ld - memory layout for riscv-tests env p (docs/spec/core.md section 10.3).
 * Every section is in IMEM from 0x0000_0000. rv32ui-p-fence_i writes instructions into .data
 * and jumps there, but the core fetches only from IMEM (or the boot ROM), so .data
 * must also be in IMEM. Loads and stores to IMEM go over the data bus like real firmware.
 * The size must match CORE_TB_IMEM_SIZE in tb/core/core_tb_map.vh.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text.init)               /* _start must come first */
        *(.text .text.*)
    } > IMEM

    .tohost : ALIGN(64) {
        *(.tohost)
    } > IMEM

    .data : ALIGN(64) {
        *(.rodata .rodata.* .srodata .srodata.*)
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > IMEM

    .bss (NOLOAD) : ALIGN(4) {
        *(.sbss .sbss.* .bss .bss.* COMMON)
    } > IMEM

    /* Some riscv gcc builds (Vitis on the school server) add .note.gnu.build-id. With no
     * output section for it the linker puts it at address 0, before _start.
     */
    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.note.*)
    }
}
