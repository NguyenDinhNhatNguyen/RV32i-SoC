# Kiểm tra tương đương (Conformal)

`accel_rtl2gate.do` so RTL với netlist Genus của accelerator, theo mẫu `run_lec_cg.do` của Lab 1. Không dùng dofile Genus sinh ra vì nó cần license Conformal_Ultra.

Chạy trên server: `make lec-accel` (sau `make synth-accel`). Đạt khi 0 non-equivalent.

Các file khác:

| File | Nội dung |
| --- | --- |
| `core_rtl2gate.do` | LEC của `rv32_core` (D-042, `docs/genus_core.md`) |
| `soc_rtl2gate.do.in`, `run_lec_soc.sh` | LEC của `soc_top`, RTL ↔ netlist Genus (LEC-01, LEC-02). Script sinh `soc_rtl2gate.do` từ file mẫu rồi chạy Conformal, cách dùng ở `docs/lec_soc.md` |
| `precheck_lec02.sh` | Kiểm tra trước khi chạy LEC-02: netlist, trạng thái git, RTL đổi sau commit chốt |
| `soc_gate2gate.do.in`, `run_lec_g2g.sh` | LEC-03: netlist tổng hợp ↔ netlist sau layout (`pnr/out_soc_p9/soc_top_pnr.v`). `DRY_RUN=1` và `CHECK=1` để kiểm tra đầu vào, `docs/lec_soc.md` |
| `apb_bridge_rtl2gate.do.in`, `run_lec_apb_bridge.sh` | LEC riêng khối `apb_bridge` (`docs/lec_soc.md` mục 5) |
