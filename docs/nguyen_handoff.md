# Bàn giao task của Nguyên (19/10)

| Task | Trạng thái | Đã có trong repo | Còn phải làm |
| --- | --- | --- | --- |
| HT-02 Hỏi VPN | Xong | — | Trường không mở VPN: Cadence chỉ chạy khi lên trường |
| HT-01 Kiểm tra server | Script sẵn sàng | `scripts/check_server.sh` | Lên trường, source môi trường Cadence như Lab, chạy `make check-server`, gửi file trong `appendix/server_check/` cho Phát |
| HT-04 Môi trường ở nhà | Hướng dẫn xong | `docs/setup_home.md` | Cài thử trên một máy, sửa hướng dẫn nếu lệnh khác, gửi cả nhóm |
| RTL-05 Wrapper accelerator | RTL + testbench pass với lõi giả | `rtl/accel/`, `tb/unit/tb_accel_wrapper.v`, `fw/accel.h` | Thay `sa_core_model.v` bằng lõi Lab 2, chỉnh `LAT`, chạy lại `make sim-accel` |
| PD-01 Chạy thử Innovus | Script sẵn sàng | `syn/scripts/synth_accel.tcl`, `pnr/scripts/*.tcl`, `syn/constraints/accel.sdc` | Điền đường dẫn trong `pnr/scripts/config.tcl`, chạy `make synth-accel` rồi `make pnr-accel`, sửa lệnh theo phiên bản Innovus nếu báo lỗi |
| PD-02 Ước lượng die | Công cụ sẵn sàng | `pnr/scripts/estimate_die.py` | Chờ kích thước SRAM macro (HT-01) và diện tích SoC từ Phát |

## Buổi lên trường đầu tiên (theo thứ tự)

1. `git clone` repo (hoặc `scp` nếu server không ra internet; script check sẽ báo).
2. `make check-server` → gửi báo cáo cho Phát, điền `pnr/scripts/config.tcl`.
3. `make synth-accel` → xem `syn/out_accel/reports/clock_gating.rpt`: phần lớn flop của mảng phải được gate.
4. `make pnr-accel` → copy `pnr/out_accel/reports/` vào `appendix/pnr_accel/`, commit.

## Giả định trong wrapper cần xác nhận với code Lab 2

- Lõi là systolic array N x N output-stationary, N = 4, toán hạng int8 có dấu, tích luỹ 32 bit.
- Đầu vào mỗi chu kỳ: N byte A (theo hàng) + N byte B (theo cột), đã skew.
- Có chân enable để giữ toàn bộ thanh ghi (a_out, b_out, bộ tích luỹ) khi không chạy.
- Độ trễ đủ kết quả: 3N - 2 chu kỳ. Nếu lõi Lab 2 khác (thêm tầng pipeline, xả kết quả tuần tự...), sửa `LAT` và phần đọc `C_BUF`.
