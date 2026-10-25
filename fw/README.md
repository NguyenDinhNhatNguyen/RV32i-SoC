# Firmware

Firmware RV32I chạy trên mô phỏng, biên dịch bằng riscv gcc trong container.

| Thư mục, file | Nội dung |
| --- | --- |
| `common/` | Linker script (`link.ld` cho SoC, `link_isa.ld` cho riscv-tests) |
| `tests/asm/` | Test assembly của lõi (hazard, trap, ngắt, WFI, nhân chia) |
| `tests/bus/`, `tests/soc/` | Test mức bus và toàn SoC |
| `bench/` | Dhrystone, CoreMark và `crt0.S` |
| `accel.h` | Thanh ghi và hàm gọi accelerator |
| `riscv-tests/`, `riscv-arch-test/`, `coremark/` | Submodule, lấy bằng `git submodule update --init --recursive` |

Địa chỉ trong `common/link.ld` phải khớp `rtl/bus/soc_map.vh`.
