/* link_isa.ld - bố cục bộ nhớ cho riscv-tests env p (docs/spec/core.md mục 10.3).
 * Mọi section nằm trong IMEM từ 0x0000_0000. rv32ui-p-fence_i ghi lệnh vào .data
 * rồi nhảy tới đó, mà core chỉ lấy lệnh từ IMEM (hoặc boot ROM), nên .data
 * cũng phải ở IMEM. Load/store vào IMEM đi qua bus dữ liệu như firmware thật.
 * Kích thước phải khớp CORE_TB_IMEM_SIZE trong tb/core/core_tb_map.vh.
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
        *(.text.init)               /* _start phải đứng đầu */
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
}
