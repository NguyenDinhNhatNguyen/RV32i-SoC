# Nhật ký lint RTL (VER-03)

Mục tiêu: toàn bộ RTL lint sạch (0 warning) sau mỗi lần merge vào `main`, giữ tới RTL freeze 15/11.

## Cách chạy

Luôn chạy trong Docker của nhóm (Verilator 5.052). Verilator cài thẳng trên máy thường cũ hơn và báo sai, ví dụ không biết mã `UNUSEDSIGNAL`.

```sh
cd ~/eda/designs/rv32i-soc
git pull
scripts/eda.sh start
scripts/eda.sh run "make lint-all"
```

Đạt khi dòng cuối là `LINT-ALL PASS`. `make lint-all` chạy lần lượt:

| Target | Phủ |
| --- | --- |
| `lint-accel` | `rtl/accel`, top `accel_apb` |
| `lint-core` | Từng khối `rtl/core`, các tổ hợp `ENABLE_M`, `ENABLE_WFI_SLEEP`, `ENABLE_BTB` |
| `lint-bus` | Từng khối `rtl/bus` và `rtl/mem`, các giá trị `N_MASTER`, `BANK_W` |
| `lint-periph` | Từng khối `rtl/periph`, tham số mặc định |
| `lint-soc` | `soc_top` với `ENABLE_M` × `ENABLE_WFI_SLEEP` × `ENABLE_DMA` (8 cấu hình), thêm 1 cấu hình tắt SPI, PWM, I2C, DMA |

Một target lỗi thì các target sau vẫn chạy, cuối cùng in bảng tổng kết.

## Khi có warning

1. Không tự sửa RTL của người khác. Gửi dòng `%Warning` cho chủ khối (bảng phân công trong `README.md`).
2. Ghi một dòng FAIL vào bảng dưới, kèm tên khối và mã warning.
3. Chạy lại sau khi chủ khối sửa xong, ghi thêm một dòng PASS.

Waiver chỉ dùng khi có lý do và phải có comment giải thích ngay cạnh. Hiện có (12/11):

- `lint_off UNUSEDSIGNAL`: 2 chỗ trong `accel_wrapper.v` (`s_addr[1:0]` vì chỉ truy cập word, `core_busy`/`core_done` vì wrapper tự đếm LAT).
- Dây `unused_ok` gom các bit cố ý không dùng: `rv32_regfile.v`, `rv32_btb.v`, `soc_top.v`, `uart_apb.v`, `irqc_apb.v`, `spi_apb.v`, `i2c_apb.v`.
- `gpio_apb` chỉ lint sạch với `W = 32` (ghi chú ở `soc_top.v`).

Khi thêm waiver mới, cập nhật danh sách này.

## HAL trên server (trước RTL freeze)

HAL là công cụ lint của Cadence, có sẵn trong Xcelium 24.03 trên server. Chạy một lần trước 15/11 để có thêm góc nhìn cho báo cáo. Tiêu chí của nhóm vẫn là 0 warning Verilator, warning HAL chỉ ghi lại và báo chủ khối nếu là lỗi thật.

Trên server, trong thư mục repo:

```sh
git pull
make lint-hal
bash scripts/save_reports.sh lint/run_hal appendix/lint_hal
```

- `make lint-hal` chạy `xrun -hal` trên `soc_top` (cùng file với `lint-soc`, tham số mặc định), in số thông báo theo mức (`*F`, `*E`, `*W`, `*N`) và theo rule, lưu ở `lint/run_hal/summary.txt`.
- Lệnh báo lỗi khi có `*F`, hoặc `*E` của rule không nằm trong danh sách waive. Khi đó xem `lint/run_hal/xrun.log` và báo chủ khối như mục trên.
- Danh sách waive mặc định chỉ có `CBPAHI` (biến `WAIVE` trong `scripts/hal_lint.sh`). `make lint-hal WAIVE=` thì mọi `*E` đều làm FAIL.
- Nếu báo `no HAL log` thì bản `xrun` này không nhận `-hal`. Thử `hal -help` để xem lệnh HAL riêng và ghi lại vào đây.
- Lệnh thứ ba copy `summary.txt` và log vào `appendix/lint_hal/` để commit. RTL không chứa gì của PDK nên log commit được.

### Waiver HAL: `CBPAHI`

`xmhelp hal CBPAHI`: thanh ghi hoặc cổng ra được lái bởi một đường tổ hợp đi qua nhiều cấp module. Đây là hướng dẫn để dễ đóng timing, không phải lỗi chức năng. Mức mặc định của Cadence là `E`.

Lần chạy 13/11 có 576 thông báo `CBPAHI` và không có `*E` nào khác. Nhiều nhất ở `accel_wrapper.v` (259), `pe.v` (128), `rv32_btb.v` (40), `rv32_regfile.v` (31), `rv32_core.v` (27). Ví dụ ở core: tín hiệu chờ của bus (`wb_wait`) qua `pipe_stall` và `ex_go` tới các flop `ex_*_q`. Đường này cố ý có trong thiết kế: pipeline phải dừng ngay trong chu kỳ bus chưa sẵn sàng.

Nhóm không sửa RTL theo rule này. Lý do:

- Muốn hết `CBPAHI` phải chèn flop vào đường stall và đường giải mã APB. Việc đó đổi hành vi theo chu kỳ của core và accelerator ngay trước RTL freeze.
- Timing của các đường này đã được kiểm bằng STA (Genus và Tempus, `docs/sta_results.md`).

Waiver nằm ở `WAIVE` trong `scripts/hal_lint.sh`. `summary.txt` vẫn đếm `CBPAHI` theo từng file để đưa vào báo cáo.

## Kết quả HAL

| Ngày | Commit | Xcelium | `*F` | `*E` | `*W` | `*N` | Kết quả | Ghi chú |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| 13/11 | `7008da2` | 24.03-s013 | 0 | 576 | 1931 | 707 | PASS sau waiver | Cả 576 `*E` là `CBPAHI`. `*W` nhiều nhất: `MAXLEN` 343 (dòng dài), `STYVAL` 319, `SYNPRT` 175, `NBGEND` 149. Report ở `appendix/lint_hal/` |

## Kết quả

| Ngày | Commit `main` | Verilator | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 28/10 | `b00b132` | 5.052 | PASS 5/5 | Lần đầu. Thêm `lint-periph` và `lint-all` |
| 07/11 | `19d79c6` | 5.052 | PASS 5/5 | Có SPI, PWM (lint riêng và trong `soc_top`). `i2c_apb.v` rỗng nên SKIP, chờ Phúc push RTL (RTL-14) |
| 10/11 | `2b7c6bf` | 5.052 | FAIL | `spi_apb` mất dây `unused_ok` khi merge (`lint-soc`), `i2c_apb` có 3 warning (`lint-periph`) |
| 10/11 | `cba0199` | 5.052 | PASS 5/5 | Phát sửa `spi_apb`, `i2c_apb` và ghép I2C vào `soc_top` |
| 11/11 | `eb84067` | 5.052 | PASS 5/5 | `lint-soc` thêm cấu hình tắt SPI, PWM, I2C, DMA (9 cấu hình) |
| 12/11 | `16b790b` | 5.052 | PASS 5/5 | Sau `eced27a` (localparam của `i2c_apb` ra ngoài generate) và `b3c6518`. Waiver không đổi |
| 13/11 | `c92f53c` | 5.052 | PASS 5/5 | Sau PD-07 và HAL. So với `16b790b` RTL chỉ đổi 1 dòng ở `accel_apb.v`. Waiver không đổi |
