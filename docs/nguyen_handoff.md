# Bàn giao task của Nguyên (cập nhật 25/10)

Giải thích chi tiết và lệnh chạy: xem `docs/runbook_nguyen.md`. Ở nhà mọi lệnh mô phỏng chạy qua `scripts/eda.sh` (xem `docs/setup_home.md`).

| Task | Trạng thái | Đã có trong repo | Còn phải làm |
| --- | --- | --- | --- |
| HT-02 Hỏi VPN | Xong | — | Trường không mở VPN: Cadence chỉ chạy khi lên trường |
| HT-01 Kiểm tra server | Xong 21/10 | `appendix/server_check/server_check_20261021_0749.txt` | Không còn. Kết quả: đủ tool, PDK ở `~/PDK_GPDK45` (có lib slow và fast), SRAM `sram_2k_macro` 1024 x 32 bit, 80 x 100 um, không có GDS và CDL (thầy xác nhận không cần, 22/10) |
| HT-04 Môi trường ở nhà | **Xong 25/10**: Hiếu cài theo hướng dẫn trên máy của mình và chạy được | `docs/setup_home.md`, `scripts/eda.sh`, `.vscode/` | Không còn |
| RTL-05 Wrapper accelerator | **Xong 25/10**: ghép lõi Lab 2, check 2 PASS, `fw-soc` 126/126 | `rtl/accel/`, `tb/unit/tb_accel_*.v`, `fw/accel.h` | Không còn. Tỉ lệ clock gating xác nhận bằng Genus cùng PD-01 |
| PD-01 Chạy thử Innovus | Flow chạy trọn 21/10 (90%): LEC PASS, GLS PASS, DRC/connectivity/antenna 0 lỗi, setup +7,68 ns, hold +0,005 ns | `appendix/synth_accel/`, `appendix/pnr_accel/`, `lec/accel_rtl2gate.do` | **Chưa xong được vì cần server:** lõi accelerator đổi sang Lab 2 nên phải chạy lại cả flow, và sửa skew 113 ps > 80 ps (4 flop điều khiển không qua clock gating) |
| PD-02 Ước lượng die | Ước lượng xong 25/10 (70%): die 421 × 422 µm, 8 macro 2 hàng, pin plan, power plan | `docs/pd02_floorplan.md`, `pnr/scripts/soc_floorplan.tcl` | **Chưa xong được vì cần server:** chạy thử script trên Innovus (PD-03), chọn hướng macro theo `macro_info.sh`, thay diện tích bằng số Genus (STA-02) |

## Buổi lên trường tiếp theo

Server ra GitHub được, dùng `git pull` trực tiếp. Không cần `export PDK_DIR`, script tự dùng `~/PDK_GPDK45`. Chạy cả flow một lần, lệnh chỉ gõ 1 lần:

```bash
( make synth-accel && make lec-accel && make gls-accel && make pnr-accel ) > full_run.txt 2>&1 &
grep -E 'Genus xong|Compare Results|PASS|Innovus xong|LOI' full_run.txt   # xem tiến độ
```

Thứ tự buổi tới:

1. `bash scripts/macro_info.sh` rồi dán output: chọn hướng macro và lớp ring cho `soc_floorplan.tcl`.
2. Chạy lại cả flow accelerator (lệnh trên) vì lõi đã đổi sang Lab 2. Xem `clock_gating.rpt` và skew.
3. Nếu skew vẫn > 80 ps: thử đặt `lp_clock_gating_min_flops` nhỏ hơn để 4 flop điều khiển cũng qua clock gating, rồi chạy lại.

## Bài học buổi 21/10 (Genus 21.1, Innovus 21.1, Conformal_Asic)

- Genus đọc RTL ở chế độ Verilog-2001: không khai báo `localparam` trong `generate`.
- `lp_insert_clock_gating` phải đặt trước `elaborate`. Lệnh `remove_assigns` đã bỏ, dùng thuộc tính cùng tên.
- Trường có license **Conformal_Asic** (log LEC: `Check out Conformal_Asic 24.1 license`). Dofile LEC do Genus sinh đòi Conformal_Ultra nên không chạy được, dùng `lec/accel_rtl2gate.do` (mẫu Lab 1) với `set flatten model -gated_clock` và `set compare effort high`.
- Thư viện fast tên `fast_vdd1v0_basicCells.lib` (C hoa). File `qrc/gpdk045.tch` của Lab không đọc được.
- `BUFX2` của gsclib045 là cell cao gấp đôi, phải cấm ở cả Genus và Innovus.
- Innovus 21.1 đổi tên nhiều tuỳ chọn (`setPlaceMode -place_...`, `add_ndr`, `verifyGeometry` không có `-type`).
- Genus và Innovus không ghi đè log mà tạo `genus.log1`, `genus.log2`. `make` đã xoá log cũ trước mỗi lần chạy.

## Lõi Lab 2 đã ghép (25/10)

Trả lời 4 câu hỏi và các chỗ sửa trong `pe.v`, `accelerator_top.v`: xem `docs/runbook_nguyen.md` mục 3.
