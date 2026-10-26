# Benchmark trên soc_top (EVA-01)

Đo CPI, DMIPS/MHz, CoreMark/MHz của core khi chạy trong `soc_top` (bus, SRAM macro, APB), so với `tb_core` ở `docs/bench_core.md`. Đo thêm speedup của accelerator nhân ma trận so với phần mềm.
Tất cả chạy bằng Icarus trên `tb/soc/tb_soc.v`, không sửa RTL hay testbench của SoC.

## Cách chạy

```sh
git submodule update --init --recursive   # lần đầu, lấy riscv-tests và coremark
make bench-soc                            # 6 lần chạy song song, khoảng 15 phút
make bench-soc T=accel_bench              # chỉ phần accelerator, khoảng 2 phút
make bench-soc T=dhrystone                # chỉ Dhrystone
```

Log ở `tb/core/out/bench_soc/<tên>.<cấu hình>.log`. Dòng `BENCH` là kết quả đo. `tb_soc` chạy khoảng 4 000 chu kỳ mỗi giây nên CoreMark rv32i mất khoảng 12 phút.

## Cách đo

- Cùng mã nguồn và cờ dịch với `bench-core` (GCC 13.2, `-O2`). Bản `rv32i` chạy trên `ENABLE_M=0`, bản `rv32im` chạy trên `ENABLE_M=1`, cả hai có `ENABLE_WFI_SLEEP=1`.
- Thêm `-DBENCH_SOC`: `crt0.S` đặt UART `BAUDDIV = 1` (16 chu kỳ mỗi bit) cho mô phỏng nhanh, và chờ UART gửi hết rồi mới ghi `tohost`. `bench_putchar` chờ khi TX FIFO đầy. Phần in nằm ngoài vùng đo.
- Chu kỳ và số lệnh lấy từ `mcycle`/`minstret` trong vùng đo, giống `bench-core`.
- `scripts/bench_soc_mon.v` là module theo dõi biên dịch cùng `tb_soc` (gốc mô phỏng thứ hai, không sửa `tb_soc`). Nó đếm trong vùng đo số chu kỳ bus dữ liệu dừng, số lệnh SB/SH, số chu kỳ lấy lệnh bị chặn và số truy cập APB. Kết quả ở dòng `BENCH soc region`.
- `soc_top` không có tham số bật tắt wait state. Wait state duy nhất của bộ nhớ là đọc–sửa–ghi của SB/SH ở `sram_wrap` (1 chu kỳ, vì macro GPDK45 không có chân ghi theo byte). Vì vậy cấu hình "không wait state" là `tb_core` (bộ nhớ lý tưởng, chạy cùng chuỗi lệnh), cấu hình "có wait state" là `soc_top`.

## Kết quả CPI (26/10/2026)

`make bench-soc` và `make bench-core` in nhãn `<chương trình> on <cấu hình>` trên mỗi dòng kết quả, ví dụ `[dhrystone_rv32im on M1W1]`.

| Benchmark | Cấu hình | Chu kỳ, `tb_core` (không wait state) | Chu kỳ, `soc_top` | Lệnh | CPI `tb_core` | CPI `soc_top` |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Dhrystone, 500 lần | rv32i, ENABLE_M=0 | 339 028 | 355 528 | 291 528 | 1,163 | 1,220 |
| Dhrystone, 500 lần | rv32im, ENABLE_M=1 | 339 028 | 355 528 | 276 528 | 1,226 | 1,286 |
| CoreMark, 3 vòng | rv32i, ENABLE_M=0 | 2 693 735 | 2 697 382 | 2 239 763 | 1,203 | 1,204 |
| CoreMark, 3 vòng | rv32im, ENABLE_M=1 | 1 085 261 | 1 088 908 | 939 989 | 1,155 | 1,158 |

| Benchmark | Cấu hình | `tb_core` | `soc_top` |
| --- | --- | --- | --- |
| Dhrystone | rv32i và rv32im | 0,839 DMIPS/MHz (1474 Dhrystone/s/MHz) | 0,800 DMIPS/MHz (1406 Dhrystone/s/MHz) |
| CoreMark | rv32i | 1,114 CoreMark/MHz | 1,112 CoreMark/MHz |
| CoreMark | rv32im | 2,764 CoreMark/MHz | 2,755 CoreMark/MHz |

CoreMark tự kiểm CRC đúng ở cả 2 bản (seedcrc 0xe9f5, list 0xe714, matrix 0x1fd7, state 0x8e3a). Dhrystone kiểm giá trị cuối đúng.

## Giải thích chênh lệch

Số lệnh trên `soc_top` bằng đúng `tb_core`, nên chuỗi lệnh giống hệt. Toàn bộ phần chênh là chu kỳ dừng của bus, và module theo dõi đếm được đúng bằng phần chênh:

| Benchmark | Chu kỳ thêm | SB/SH trong vùng đo | Chu kỳ dừng bus dữ liệu | Lấy lệnh bị chặn | APB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dhrystone (cả 2 bản) | 16 500 (+4,9%) | 16 500 | 16 500 | 0 | 0 |
| CoreMark (cả 2 bản) | 3 647 (+0,1% và +0,3%) | 3 647 | 3 647 | 0 | 0 |

- **Wait state SB/SH:** mỗi lệnh SB hoặc SH vào DMEM tốn thêm đúng 1 chu kỳ. Dhrystone có 33 lệnh ghi byte mỗi lần chạy: 31 ở `strcpy` (chép chuỗi 30 ký tự và byte 0 cuối, từng byte), 1 ở `Proc_4`, 1 ở `Proc_5` (đếm từ vết lệnh của `tb_core`). Vì vậy chậm 4,9% và DMIPS/MHz giảm từ 0,839 xuống 0,800. Đây là chi phí thật của phần cứng (macro không có chân ghi byte), không phải lỗi đo. CoreMark gần như chỉ ghi word nên chỉ chậm 0,1 đến 0,3%.
- **Dhrystone M=0 và M=1 cùng số chu kỳ:** trùng hợp, giải thích ở `docs/bench_core.md`. Trên `soc_top` cả hai cùng thêm 16 500 chu kỳ SB/SH nên vẫn trùng nhau (355 528).
- **Bus:** `sys_bus` không thêm chu kỳ cho đọc và ghi word vào SRAM, giống bộ nhớ lý tưởng của `tb_core`.
- **Lấy lệnh:** 0 chu kỳ bị chặn, vì `.rodata` nằm ở DMEM (`fw/common/link.ld`). Không có lệnh đọc dữ liệu nào vào IMEM để tranh cổng với lấy lệnh.
- **APB:** benchmark không truy cập ngoại vi trong vùng đo. APB chỉ ảnh hưởng tới phần accelerator bên dưới.

Muốn bỏ chênh lệch của Dhrystone thì dùng `strcpy` theo word khi địa chỉ thẳng hàng. Phần cứng không cần đổi, vì macro không có chân ghi byte.

## Speedup accelerator

Bài toán `fw/bench/accel_bench.c`: C = A × B với A, B là ma trận 16 × 16 int8 có dấu (đúng kiểu dữ liệu của lõi Lab 2), C là int32. Ba bản:

- **sw:** 3 vòng `for` bằng C. Bản rv32i nhân bằng hàm mềm của libgcc, bản rv32im dùng lệnh MUL.
- **poll:** chia thành khối 4 × 4, mỗi khối C cộng dồn 4 phép nhân khối trên accelerator (64 phép nhân khối). Mỗi phép: ghi 4 word A và 4 word B qua APB, ghi START, chờ `STATUS.DONE`, đọc 16 word C và cộng dồn, ghi 1 để xoá DONE.
- **irq:** như poll nhưng ghi CTRL = START | IRQ_EN và chờ bằng WFI. Ngắt đi qua IRQC bit 1. Handler kiểm `mcause = 0x8000000B` và `PENDING` bit 1, xoá DONE ở accelerator rồi `mret`.

Hai bản accelerator ra kết quả giống hệt bản phần mềm (so cả 256 phần tử, checksum `52119321`). Bản irq nhận đúng 64 ngắt.

| Cấu hình | sw | poll | irq | Speedup poll | Speedup irq |
| --- | ---: | ---: | ---: | ---: | ---: |
| rv32i, ENABLE_M=0 | 577 522 | 23 046 | 25 471 | 25,06× | 22,67× |
| rv32im, ENABLE_M=1 | 39 039 | 23 100 | 25 458 | 1,69× | 1,53× |

Đơn vị là chu kỳ cho cả phép nhân 16 × 16.

Chu kỳ của một phép nhân khối (poll, đo bằng `mcycle`, mỗi số gồm 1 lệnh `csrr`):

| Bước | Chu kỳ | Ghi chú |
| --- | ---: | --- |
| Nạp A và B | 41 | 8 lệnh đọc DMEM và 8 lệnh ghi APB |
| START tới DONE | 24 | Accelerator tính 12 chu kỳ, phần còn lại là ghi START và đọc STATUS qua APB |
| Đọc C và cộng dồn | 164 | 16 lệnh đọc APB, khoảng 10 chu kỳ mỗi word |
| Xoá DONE | 6 | 1 lệnh ghi APB |
| Tổng | 235 | |

Nhận xét:

- Accelerator chỉ tính 12 chu kỳ trên 235 chu kỳ của mỗi khối. Khoảng 95% thời gian là chuyển dữ liệu qua APB. Riêng đọc 16 word C đã chiếm 70%.
- Với rv32i, phần mềm phải gọi hàm nhân mềm (khoảng 140 chu kỳ mỗi phép nhân–cộng) nên accelerator nhanh hơn 25 lần dù tốn phí APB.
- Với rv32im, lệnh MUL làm phần mềm chỉ còn khoảng 9,5 chu kỳ mỗi phép nhân–cộng, nên accelerator chỉ nhanh hơn 1,69 lần. Nếu bỏ hết phí APB (64 × 12 = 768 chu kỳ) thì giới hạn trên khoảng 51 lần.
- Bản irq chậm hơn poll khoảng 37 chu kỳ mỗi khối: vào trap, handler (xoá DONE và đọc `PENDING` qua APB), `mret`, thức dậy sau WFI. Đổi lại, lõi ngủ trong lúc chờ và có thể làm việc khác. Vòng chờ là `csrc MIE`, kiểm cờ, `wfi`, `csrs MIE`, không race, nhờ core nhận ngắt ngay ở lệnh sau `csrs mstatus` (D-038).
- Số truy cập APB khớp với tính tay. Poll: 64 × (8 + 1 + 16 + 1) cộng 192 lần đọc STATUS = 1856. Irq: 64 × (8 + 1 + 16) cộng 3 truy cập của handler mỗi lần = 1792.
- Bản accelerator còn 1024 lệnh SB (xoá mảng cộng dồn bằng `memset` từng byte của `bench.c`), tốn 1024 chu kỳ wait state, khoảng 4% thời gian.

Hướng tăng speedup: bộ đệm C đọc được nhiều phần tử mỗi lần đọc (gói 2 kết quả 16 bit vào 1 word nếu đủ), hoặc DMA chép C về DMEM. Cả hai cần đổi RTL accelerator hoặc thêm DMA.

## Giới hạn đo

- Mô phỏng RTL bằng Icarus, chưa tính trễ thật của macro và dây. Tần số chính thức lấy từ Genus và Innovus.
- CoreMark chỉ chạy 3 vòng (luật chính thức cần ít nhất 10 giây), nên đây chưa phải điểm CoreMark chính thức. Dòng `ERROR! Must execute for at least 10 secs` là bình thường. `scripts/bench_soc_run.sh` bỏ qua dòng này giống `bench-core`.
- `soc_top` không có tham số tắt wait state, nên so sánh "không wait state" dùng `tb_core`. Hai bên chạy đúng cùng số lệnh, nên so sánh vẫn công bằng.
- Vùng đo của module theo dõi tính từ lệnh `csrr minstret` này tới lệnh kia, nên nhiều hơn số `mcycle` của firmware 3 chu kỳ.
- `BAUDDIV = 1` chỉ dùng cho mô phỏng. Phần in nằm ngoài vùng đo nên không ảnh hưởng kết quả.
- Phép nhân 16 × 16 được chọn để vừa IMEM và DMEM 16 KB và chạy nhanh trong mô phỏng. Ma trận lớn hơn cho speedup gần như không đổi, vì chi phí mỗi khối cố định.
