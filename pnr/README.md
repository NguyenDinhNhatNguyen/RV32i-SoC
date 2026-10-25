# Place and route

Script Innovus, chỉ chạy trên server trường.

| File | Nội dung |
| --- | --- |
| `scripts/config.tcl` | Đường dẫn PDK, thư viện, tên net nguồn |
| `scripts/mmmc.view` | Corner slow và fast cho MMMC |
| `scripts/run_all.tcl` | Flow trọn cho accelerator: floorplan, power, place, CTS, route, kiểm tra |
| `scripts/soc_floorplan.tcl` | Floorplan SoC với 8 SRAM macro (PD-02, chưa chạy trên server) |
| `scripts/estimate_die.py` | Ước lượng kích thước die |

Chạy: `make pnr-accel`. Thư mục `run*/`, `out*/` bị ignore. Hướng dẫn: `docs/flow_notes.md`, floorplan SoC: `docs/pd02_floorplan.md`.
