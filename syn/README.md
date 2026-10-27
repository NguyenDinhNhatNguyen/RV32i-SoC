# Tổng hợp

| Thư mục | Nội dung | Chạy ở |
| --- | --- | --- |
| `constraints/` | SDC (clock 20 ns): `accel.sdc` cho accelerator (PD-01), `soc.sdc` cho `soc_top` (STA-01). Dùng chung cho flow trường và flow nhà | |
| `scripts/` | Script Genus: `synth_accel.tcl` (accelerator, PD-01), `synth_block.tcl` (từng khối của SoC, STA-02, cấm scan flop) | Server trường: `make synth-accel`, `make synth-block B=<khối>`, `make synth-blocks` |
| `yosys/` | Tổng hợp thử bằng Yosys và STA với Nangate45, chỉ xem xu hướng | Nhà: `make synth-core-yosys`, `make sta-core-nangate` |

Thư mục chạy `run*/` và kết quả `out*/` bị ignore. Report chính thức copy vào `appendix/`. Cách chạy và tiêu chí: `docs/flow_notes.md`.
