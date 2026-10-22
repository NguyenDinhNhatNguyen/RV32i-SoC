/* link.ld - riscv-arch-test trên tb_core. Mọi section ở IMEM từ 0x0000_0000
 * như fw/common/link_isa.ld: test Zifencei ghi lệnh vào vùng dữ liệu rồi nhảy tới đó,
 * mà core chỉ lấy lệnh từ IMEM. Kích thước IMEM do tb_core quyết định
 * (CORE_TB_IMEM_SIZE), linker chỉ đặt địa chỉ.
 */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

SECTIONS
{
    . = 0x00000000;
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
