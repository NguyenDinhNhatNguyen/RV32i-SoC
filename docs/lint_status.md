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

Waiver chỉ dùng khi có lý do và phải có comment giải thích ngay cạnh. Hiện có (11/11):

- `lint_off UNUSEDSIGNAL`: 2 chỗ trong `accel_wrapper.v` (`s_addr[1:0]` vì chỉ truy cập word, `core_busy`/`core_done` vì wrapper tự đếm LAT).
- Dây `unused_ok` gom các bit cố ý không dùng: `rv32_regfile.v`, `rv32_btb.v`, `soc_top.v`, `uart_apb.v`, `irqc_apb.v`, `spi_apb.v`, `i2c_apb.v`.
- `gpio_apb` chỉ lint sạch với `W = 32` (ghi chú ở `soc_top.v`).

Khi thêm waiver mới, cập nhật danh sách này.

## Kết quả

| Ngày | Commit `main` | Verilator | Kết quả | Ghi chú |
| --- | --- | --- | --- | --- |
| 28/10 | `b00b132` | 5.052 | PASS 5/5 | Lần đầu. Thêm `lint-periph` và `lint-all` |
| 07/11 | `19d79c6` | 5.052 | PASS 5/5 | Có SPI, PWM (lint riêng và trong `soc_top`). `i2c_apb.v` rỗng nên SKIP, chờ Phúc push RTL (RTL-14) |
| 10/11 | `2b7c6bf` | 5.052 | FAIL | `spi_apb` mất dây `unused_ok` khi merge (`lint-soc`), `i2c_apb` có 3 warning (`lint-periph`) |
| 10/11 | `cba0199` | 5.052 | PASS 5/5 | Phát sửa `spi_apb`, `i2c_apb` và ghép I2C vào `soc_top` |
| 11/11 | `eb84067` | 5.052 | PASS 5/5 | `lint-soc` thêm cấu hình tắt SPI, PWM, I2C, DMA (9 cấu hình) |
