# Place and route

Script Innovus, chỉ chạy trên server trường.

| File | Nội dung |
| --- | --- |
| `scripts/config.tcl` | Đường dẫn PDK, thư viện, tên net nguồn |
| `scripts/mmmc.view` | Corner slow và fast cho MMMC |
| `scripts/run_all.tcl` | Flow trọn: floorplan, power, place, CTS, route, kiểm tra. Chọn khối bằng biến `TOP` (`accel_wrapper` hoặc `soc_top`) |
| `scripts/soc_floorplan.tcl` | Floorplan SoC: lõi mặc định 405 × 405 µm (đổi bằng `CORE_W`, `CORE_H`), 8 SRAM macro, pin plan, power plan (PD-02) |
| `scripts/estimate_die.py` | Ước lượng kích thước die |
| `scripts/pd08_vss_fix.tcl` | Ghi lại các lệnh sửa lưới `VSS` của PD-08 (26/11) trên `_p9`. Chạy lại thì lưu sang database mới, không ghi đè `route_trim.enc` |

Chạy: `make pnr-accel` hoặc `make pnr-soc`. Thư mục `run*/`, `out*/` bị ignore. Netlist, SPEF, SDF, GDS trong `out*/` dựng từ thư viện của trường, không bao giờ commit. Chỉ copy report văn bản vào `appendix/`. Hướng dẫn: `docs/flow_notes.md`, floorplan SoC: `docs/pd02_floorplan.md`.

Layout chính thức (18/11): `make pnr-soc TAG=_p9 CORE_W=420.0 CORE_H=420.7` trên netlist STA-04, kết quả và các bước ECO ở `docs/pnr_soc_status.md` mục 6. Layout cuối (26/11) là `pnr/run_soc_p9/DBS/route_trim.enc` sau PD-08, GDS `pnr/out_soc_p9/soc_top_final.gds` (`docs/pnr_soc_status.md` mục 8).

Chạy ở cỡ lõi khác (PD-07): ví dụ `make pnr-soc TAG=_p9_412 CORE_W=412.0 CORE_H=413.8` (lần chạy 26/11 trên netlist chính thức, so sánh ở `docs/pnr_soc_status.md` mục 7). Kết quả ra `pnr/out_soc_p9_412` và `pnr/run_soc_p9_412`, lần chạy mặc định không bị đụng. Chép report: `make save-pnr-soc TAG=_p9_412`. Cỡ lõi theo mức utilization tính bằng `pnr/scripts/estimate_die.py`.
