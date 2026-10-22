/* link.ld - bố cục bộ nhớ cho chương trình chạy từ IMEM (docs/spec/core.md mục 10.1).
 * .text ở IMEM từ 0x0000_0000. .rodata, .data, .bss, .tohost và stack ở DMEM.
 * Địa chỉ nạp = địa chỉ chạy: testbench (hoặc bootloader P8) nạp thẳng IMEM
 * và DMEM, lúc khởi động không chép gì.
 * Kích thước phải khớp CORE_TB_IMEM_SIZE / CORE_TB_DMEM_SIZE trong
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
        *(.text.init)               /* _start phải đứng đầu */
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
}
