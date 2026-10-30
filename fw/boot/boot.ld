/* boot.ld - boot ROM layout: 1 KB at 0x0001_0000 (SOC_BOOT_BASE, SOC_BOOT_SIZE in
 * rtl/bus/soc_map.vh). Code only, the bootloader keeps everything in registers.
 * The linker stops with an error if the code does not fit. Any other section (data, rodata)
 * lands outside ROM and scripts/gen_boot_rom.py rejects it.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00010000, LENGTH = 1K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > ROM

    /* Some riscv gcc builds (Vitis on the school server) add .note.gnu.build-id. Drop it
     * so that the ROM image holds only code.
     */
    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.note.*)
    }
}
