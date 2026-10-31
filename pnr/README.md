# Place and route

Script Innovus, chỉ chạy trên server trường.

| File | Nội dung |
| --- | --- |
| `scripts/config.tcl` | Đường dẫn PDK, thư viện, tên net nguồn |
| `scripts/mmmc.view` | Corner slow và fast cho MMMC |
| `scripts/run_all.tcl` | Flow trọn: floorplan, power, place, CTS, route, kiểm tra. Chọn khối bằng biến `TOP` (`accel_wrapper` hoặc `soc_top`) |
| `scripts/soc_floorplan.tcl` | Floorplan SoC: lõi 394 × 395 µm, 8 SRAM macro, pin plan, power plan (PD-02) |
| `scripts/estimate_die.py` | Ước lượng kích thước die |

Chạy: `make pnr-accel` hoặc `make pnr-soc`. Thư mục `run*/`, `out*/` bị ignore. Netlist, SPEF, SDF, GDS trong `out*/` dựng từ thư viện của trường, không bao giờ commit. Chỉ copy report văn bản vào `appendix/`. Hướng dẫn: `docs/flow_notes.md`, floorplan SoC: `docs/pd02_floorplan.md`.
