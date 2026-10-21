# Bàn giao task của Nguyên (cập nhật 21/10)

Giải thích chi tiết và lệnh chạy: xem `docs/runbook_nguyen.md`. Ở nhà mọi lệnh mô phỏng chạy qua `scripts/eda.sh` (xem `docs/setup_home.md`).

| Task | Trạng thái | Đã có trong repo | Còn phải làm |
| --- | --- | --- | --- |
| HT-02 Hỏi VPN | Xong | — | Trường không mở VPN: Cadence chỉ chạy khi lên trường |
| HT-01 Kiểm tra server | Xong 21/10 | `appendix/server_check/server_check_20261021_0749.txt` | Không còn. Kết quả: đủ tool, PDK ở `~/PDK_GPDK45` (có lib slow và fast), SRAM `sram_2k_macro` 1024 x 32 bit, 80 x 100 um, chưa có GDS |
| HT-04 Môi trường ở nhà | Hướng dẫn đã kiểm chứng trên máy Nguyên (80%) | `docs/setup_home.md`, `scripts/eda.sh`, `.vscode/` | Một bạn khác cài theo hướng dẫn, chạy `scripts/eda.sh check` ra 2 dòng PASS và gửi ảnh |
| RTL-05 Wrapper accelerator | RTL + testbench pass với lõi giả, có thêm vỏ APB3, lint 0 warning (70%) | `rtl/accel/`, `tb/unit/tb_accel_wrapper.v`, `tb/unit/tb_accel_apb.v`, `fw/accel.h` | Thay `sa_core_model.v` bằng lõi Lab 2, chỉnh `LAT`, chạy lại `scripts/eda.sh check` |
| PD-01 Chạy thử Innovus | Flow chạy trọn 21/10 (90%): LEC PASS, GLS PASS, DRC/connectivity/antenna 0 lỗi, setup +7,68 ns, hold +0,005 ns | `appendix/synth_accel/`, `appendix/pnr_accel/`, `lec/accel_rtl2gate.do` | Skew 113 ps > 80 ps: 4 flop điều khiển (`state`, `done`, `irq_en`) không qua clock gating nên nhận clock sớm hơn |
| PD-02 Ước lượng die | Đã có kích thước SRAM 80 x 100 um (30%) | `pnr/scripts/estimate_die.py` | Chờ diện tích cell chuẩn SoC từ Phát |

## Buổi lên trường tiếp theo

Server ra GitHub được, dùng `git pull` trực tiếp. Không cần `export PDK_DIR`, script tự dùng `~/PDK_GPDK45`. Chạy cả flow một lần, lệnh chỉ gõ 1 lần:

```bash
( make synth-accel && make lec-accel && make gls-accel && make pnr-accel ) > full_run.txt 2>&1 &
grep -E 'Genus xong|Compare Results|PASS|Innovus xong|LOI' full_run.txt   # xem tiến độ
```

Việc còn mở: sửa skew 113 ps của PD-01 (4 flop không clock gating).

## Bài học buổi 21/10 (Genus 21.1, Innovus 21.1, Conformal_Asic)

- Genus đọc RTL ở chế độ Verilog-2001: không khai báo `localparam` trong `generate`.
- `lp_insert_clock_gating` phải đặt trước `elaborate`. Lệnh `remove_assigns` đã bỏ, dùng thuộc tính cùng tên.
- Dofile LEC do Genus sinh cần license Conformal_Ultra. Dùng `lec/accel_rtl2gate.do` (mẫu Lab 1) với `set flatten model -gated_clock` và `set compare effort high`.
- Thư viện fast tên `fast_vdd1v0_basicCells.lib` (C hoa). File `qrc/gpdk045.tch` của Lab không đọc được.
- `BUFX2` của gsclib045 là cell cao gấp đôi, phải cấm ở cả Genus và Innovus.
- Innovus 21.1 đổi tên nhiều tuỳ chọn (`setPlaceMode -place_...`, `add_ndr`, `verifyGeometry` không có `-type`).
- Genus và Innovus không ghi đè log mà tạo `genus.log1`, `genus.log2`. `make` đã xoá log cũ trước mỗi lần chạy.

## Giả định trong wrapper cần xác nhận với code Lab 2

- Lõi là systolic array 4x4 output-stationary, toán hạng int8, tích luỹ 20 bit (theo đề Lab 01). Cần xác nhận lõi Lab 2 dùng số có dấu hay không dấu (tham số `SIGNED`).
- Đầu vào mỗi chu kỳ: N byte A (theo hàng) + N byte B (theo cột), đã skew.
- Top của Lab là `accelerator_top` với chân `a_row*`, `b_col*`, `res_out*`, `busy`, `done`. Wrapper hiện điều khiển lõi bằng `en`/`clr`. Khi ghép code Lab, nối start/busy/done của lõi vào FSM wrapper, và thêm enable cho a_out/b_out nếu lõi Lab chưa có để clock gating phủ gần hết flop.
- Độ trễ đủ kết quả: 3N - 2 chu kỳ. Nếu lõi Lab 2 khác (thêm tầng pipeline, xả kết quả tuần tự...), sửa `LAT` và phần đọc `C_BUF`.
