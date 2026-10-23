/* link.ld - riscv-arch-test trên tb_core. Mọi section ở IMEM như fw/common/link_isa.ld:
 * test Zifencei ghi lệnh vào vùng dữ liệu rồi nhảy tới đó, mà core chỉ lấy lệnh từ IMEM.
 * IMEM bắt đầu ở 0x8000_0000 (tb_core_arch_*.vvp dịch với CORE_TB_IMEM_BASE này),
 * trùng địa chỉ nạp của Spike, vì signature của một số test (misalign-jal-01) phụ
 * thuộc địa chỉ. Kích thước IMEM do tb_core quyết định (CORE_TB_IMEM_SIZE).
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
