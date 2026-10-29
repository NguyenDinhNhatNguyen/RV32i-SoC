# Tổng hợp

| Thư mục | Nội dung | Chạy ở |
| --- | --- | --- |
| `constraints/` | SDC (clock 20 ns): `accel.sdc` cho accelerator (PD-01), `soc.sdc` cho `soc_top` (STA-01). Dùng chung cho flow trường và flow nhà | |
| `scripts/` | Script Genus: `synth_accel.tcl` (accelerator, PD-01), `synth_block.tcl` (từng khối của SoC, STA-02, cấm scan flop), `synth_soc.tcl` (cả `soc_top` với `soc.sdc`, cấm scan flop), `sweep_soc.sh` (quét chu kỳ tìm F_max, STA-03) | Server trường: `make synth-accel`, `make synth-block B=<khối>`, `make synth-blocks`, `make synth-soc`, `make synth-soc-sweep` |
| `yosys/` | Tổng hợp thử bằng Yosys và STA với Nangate45, chỉ xem xu hướng. `sta_soc_nangate.tcl` và `sram_2k_macro_bb.v` cho `soc_top` với `soc.sdc` (STA-03) | Nhà: `make synth-core-yosys`, `make sta-core-nangate`, `make sta-soc-nangate` |

Thư mục chạy `run*/` và kết quả `out*/` bị ignore. Report chính thức copy vào `appendix/`. Cách chạy và tiêu chí: `docs/flow_notes.md`.
