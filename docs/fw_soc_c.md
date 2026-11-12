# Firmware C trên SoC (VER-04)

Chương trình C chạy trên `soc_top` trong `tb_soc`. Nó kiểm tra ngoại vi, ngắt, accelerator và lệnh nhân chia từ phía phần mềm. Phần này bổ sung cho các test assembly trong `fw/tests/soc` (`make fw-soc`).

## Cách chạy

```sh
cd ~/eda/designs/rv32i-soc
scripts/eda.sh start
scripts/eda.sh run "make fw-soc-c"
```

Đạt khi dòng cuối là `fw-soc-c: 2 passed, 0 failed`.

| Bản build | Cấu hình `tb_soc` | Ghi chú |
| --- | --- | --- |
| `soc_fw_rv32i` | M0W0 (`ENABLE_M=0`, không ngủ khi WFI) | Lệnh `MUL` phải gây trap illegal instruction |
| `soc_fw_rv32im` | M1W1 (`ENABLE_M=1`, WFI ngủ, có DMA) | Kiểm tra đủ 8 lệnh của phần mở rộng M |

Timeout là 2 000 000 chu kỳ. Một lần chạy cần khoảng 65 000 chu kỳ (rv32i) và 250 000 chu kỳ (rv32im).

## File

| File | Nội dung |
| --- | --- |
| `fw/tests/soc_c/soc_fw.c` | Chương trình test |
| `fw/tests/soc_c/soc_hw.h` | Địa chỉ và bit thanh ghi của Timer, UART, GPIO, IRQC, các bit CSR |
| `fw/bench/common/crt0.S` | Khởi động: `gp`, `sp`, xóa `.bss`, đặt BAUDDIV = 1, gọi `main`, chờ UART gửi xong, ghi `tohost` |
| `fw/bench/common/bench.c` | `bench_printf` qua UART |
| `fw/common/link.ld` | `.text` ở IMEM, dữ liệu và stack ở DMEM |

`main` trả về 0 thì crt0 ghi `tohost = 1` (PASS). Trả về mã `n` thì `tohost = 2n + 1` và tb in `FAIL ... (test n)`.

## Các nhóm kiểm tra

| Mã lỗi | Nhóm | Kiểm tra |
| --- | --- | --- |
| 1-3 | `crt0` | Biến `.data` có giá trị đầu, `.bss` bằng 0, bảng `.rodata` đọc đúng |
| 4-7 | `uart` | In dòng hello, TX xong, gửi 1 byte và nhận lại qua loopback, không có cờ lỗi |
| 8-10 | `gpio` | DIR = 0 đọc `PAD_IN`, DIR = 1 đọc lại giá trị xuất, trả về trạng thái đầu |
| 11-13 | `timer` | `mtime` tăng, CSR `time` khớp `MTIME`, `MTIMECMP` có giá trị reset |
| 14-16 | `timer` | Ngắt timer đánh thức WFI, ngắt mềm MSIP, đúng `mcause` |
| 17-19 | `accel` | 3 bộ ma trận 4 x 4 (ngẫu nhiên, biên -128 và 127, ma trận đơn vị) so với golden C, chờ bằng polling |
| 20-22 | `accel_irq` | DONE của accelerator qua IRQC thành ngắt ngoài, handler xóa DONE, kết quả khớp golden |
| 23-25 | `uart_irq` | RXNE của UART qua IRQC thành ngắt ngoài, handler đọc byte |
| 26-28 | `rv32um` | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU so với mô hình dịch và cộng. Có chia cho 0 và INT_MIN / -1 |
| 26-28 | `no_m` | Bản rv32i: `MUL` gây trap mã 2, không ghi `rd` |

Mỗi nhóm in một dòng `soc_fw: <nhóm> ok` qua UART. `make fw-soc-c` gom các dòng này từ log.

Trong log có thêm hai ký tự lạ ở đầu dòng (byte 0xA7 và `<`). Đó là byte mà test UART gửi qua loopback, không phải lỗi.

## Đã kiểm tra test bắt được lỗi

Ngày 12/11 cố tình làm sai 3 chỗ trong một bản sao của `soc_fw.c`. Cả 3 đều FAIL đúng mã:

| Lỗi cài vào | Kết quả |
| --- | --- |
| Golden của accelerator lệch 1 ở hàng 2 | FAIL mã 17 |
| Thay `mulhu` bằng `mul` | FAIL mã 26, in phép tính sai |
| `PAD_IN` kỳ vọng sai 1 bit | FAIL mã 8 |

## Kết quả

| Ngày | Commit `main` | Kết quả | Ghi chú |
| --- | --- | --- | --- |
| 12/11 | `16b790b` | PASS 2/2 | rv32i 65 428 chu kỳ, rv32im 247 981 chu kỳ. `fw-soc` vẫn 131/131 |
