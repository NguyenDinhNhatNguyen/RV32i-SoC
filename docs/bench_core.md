# Benchmark core RV32I trên tb_core

Dhrystone 2.2 (bản trong `fw/riscv-tests/benchmarks/dhrystone`) và CoreMark 1.0 (submodule `fw/coremark`) chạy trên `tb_core` bằng Icarus.
Mục đích là đo CPI và hiệu năng trên mỗi MHz của core, chưa phải kết quả CoreMark chính thức.

## Cách chạy

```sh
git submodule update --init --recursive   # lần đầu, lấy riscv-tests và coremark
make bench-core                           # 4 lần chạy, khoảng 8 phút
make bench-core T=dhrystone               # chỉ Dhrystone, khoảng 1 phút
make bench-core T=coremark CM_ITER=10     # đổi số vòng CoreMark (mặc định 3)
```

Log ở `tb/core/out/bench/<tên>.<cấu hình>.bench.log`. Dòng `BENCH` là kết quả đo.

## Cách đo

- Bản `rv32i` dịch với `-march=rv32i_zicsr`, phép nhân chia gọi hàm mềm của libgcc, chạy trên `ENABLE_M=0`.
- Bản `rv32im` dịch với `-march=rv32im_zicsr`, chạy trên `ENABLE_M=1`.
- GCC 13.2, `-O2`, không dùng newlib. In ra UART của tb bằng `fw/bench/common/bench.c`.
- Bus không chèn stall, bật `+strict_timing` để tb kiểm đúng số bubble.
- Số chu kỳ và số lệnh lấy từ `mcycle`/`minstret`, chỉ trong vùng đo của benchmark (bỏ khởi động và phần in).
- Dhrystone/s/MHz = số lần chạy × 10^6 / số chu kỳ. DMIPS/MHz = Dhrystone/s/MHz / 1757.
- CoreMark/MHz = số vòng × 10^6 / số chu kỳ.

## Kết quả (22/10/2026, commit core 2193cd1)

| Benchmark | Cấu hình | Chu kỳ đo | Lệnh | CPI | Hiệu năng |
| --- | --- | ---: | ---: | ---: | --- |
| Dhrystone, 500 lần | rv32i, ENABLE_M=0 | 339 028 | 291 528 | 1,163 | 1474 Dhrystone/s/MHz, 0,839 DMIPS/MHz |
| Dhrystone, 500 lần | rv32im, ENABLE_M=1 | 339 028 | 276 528 | 1,226 | 1474 Dhrystone/s/MHz, 0,839 DMIPS/MHz |
| CoreMark, 3 vòng | rv32i, ENABLE_M=0 | 2 693 735 | 2 239 763 | 1,203 | 1,114 CoreMark/MHz |
| CoreMark, 3 vòng | rv32im, ENABLE_M=1 | 1 085 261 | 939 989 | 1,155 | 2,764 CoreMark/MHz |

Ghi chú:

- Dhrystone ra cùng số chu kỳ ở hai cấu hình là trùng hợp thật, không phải đọc nhầm log (kiểm lại 26/10). Mỗi cấu hình có log riêng, tổng chu kỳ cả chương trình khác nhau (364 705 và 360 178), và `make bench-core` in nhãn cấu hình trên từng dòng. Đếm từ vết lệnh (`PLUSARGS=+trace`) trong vùng đo, chu kỳ = số lệnh + số bubble:

| Cấu hình | Lệnh | Nhảy (1 bubble) | MUL (1) | DIV (33) | Tổng chu kỳ |
| --- | ---: | ---: | ---: | ---: | ---: |
| rv32i, ENABLE_M=0 | 291 528 | 47 500 | 0 | 0 | 339 028 |
| rv32im, ENABLE_M=1 | 276 528 | 45 500 | 500 | 500 × 33 = 16 500 | 339 028 |

  Mỗi lần chạy có 1 phép nhân và 1 phép chia. Bản rv32i gọi `__mulsi3`, `__divsi3` của libgcc: thêm 30 lệnh và 4 lần nhảy, tức 34 chu kỳ. Bản rv32im mất 1 + 33 = 34 chu kỳ dừng. Hai bên bằng nhau đúng 34 chu kỳ mỗi lần nên tổng trùng nhau. CPI khác nhau vì số lệnh khác nhau.
- CoreMark nhân nhiều trong phần ma trận nên RV32M nhanh gấp khoảng 2,5 lần.
- CoreMark tự kiểm CRC đúng (seedcrc 0xe9f5, list 0xe714, matrix 0x1fd7, state 0x8e3a). Dòng `ERROR! Must execute for at least 10 secs` và `Errors detected` là do mô phỏng quá ngắn so với luật chạy chính thức, `make bench-core` bỏ qua lỗi này.
- CPI chỉ phản ánh core với bộ nhớ không wait state. Số đo trên `soc_top` và phần giải thích chênh lệch ở `docs/bench_soc.md`.

## Kích thước bộ nhớ

IMEM và DMEM của tb_core mỗi vùng 16 KB (`tb/core/core_tb_map.vh`). Cả hai benchmark đều vừa:

| Chương trình | .text (IMEM) | .rodata + .data + .bss (DMEM, chưa tính stack) |
| --- | ---: | ---: |
| Dhrystone rv32i | 8 420 B | 12 396 B |
| Dhrystone rv32im | 7 008 B | 12 396 B |
| CoreMark rv32i | 15 008 B | 3 980 B |
| CoreMark rv32im | 12 892 B | 3 980 B |

CoreMark bản rv32i chỉ còn dư khoảng 1,4 KB IMEM. Nếu đổi sang `-O3` hoặc thêm thư viện in, cần IMEM 32 KB.
Dhrystone dùng nhiều DMEM vì mảng `Arr_2_Glob` 10 KB, phần còn lại khoảng 4 KB cho stack.
