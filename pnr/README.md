# Place and route

Script Innovus, chỉ chạy trên server trường.

| File | Nội dung |
| --- | --- |
| `scripts/config.tcl` | Đường dẫn PDK, thư viện, tên net nguồn |
| `scripts/mmmc.view` | Corner slow và fast cho MMMC |
| `scripts/run_all.tcl` | Flow trọn: floorplan, power, place, CTS, route, kiểm tra. Chọn khối bằng biến `TOP` (`accel_wrapper` hoặc `soc_top`) |
| `scripts/soc_floorplan.tcl` | Floorplan SoC: lõi 405 × 405 µm, 8 SRAM macro, pin plan, power plan (PD-02) |
| `scripts/estimate_die.py` | Ước lượng kích thước die |

Chạy: `make pnr-accel` hoặc `make pnr-soc`. Thư mục `run*/`, `out*/` bị ignore. Netlist, SPEF, SDF, GDS trong `out*/` dựng từ thư viện của trường, không bao giờ commit. Chỉ copy report văn bản vào `appendix/`. Hướng dẫn: `docs/flow_notes.md`, floorplan SoC: `docs/pd02_floorplan.md`.

Chạy ở cỡ lõi khác (PD-07): `make pnr-soc TAG=_u75 CORE_W=412.0 CORE_H=413.8`. Kết quả ra `pnr/out_soc_u75` và `pnr/run_soc_u75`, lần chạy mặc định không bị đụng. Chép report: `make save-pnr-soc TAG=_u75`. Cỡ lõi theo mức utilization tính bằng `pnr/scripts/estimate_die.py`.
