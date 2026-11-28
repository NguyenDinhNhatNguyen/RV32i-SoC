# Tổng hợp

| Thư mục | Nội dung | Chạy ở |
| --- | --- | --- |
| `constraints/` | SDC (mặc định clock 20 ns): `accel.sdc` cho accelerator (PD-01), `core.sdc` cho `rv32_core` đứng riêng (Nhân, `docs/genus_core.md`), `soc.sdc` cho `soc_top` (STA-01, signoff 100 MHz đặt `SOC_PERIOD` 10 ns). Dùng chung cho flow trường và flow nhà | |
| `scripts/` | Script Genus: `synth_accel.tcl` (accelerator, PD-01), `synth_block.tcl` (từng khối của SoC, STA-02, cấm scan flop), `synth_soc.tcl` (cả `soc_top` với `soc.sdc`, cấm scan flop, `SYN_EXTRA_LIBS` thêm thư viện LVT hoặc HVT để thử ở V2-20), `sweep_soc.sh` (quét chu kỳ tìm F_max, STA-03), `power_soc.tcl` (công suất netlist `soc_top` theo SAIF, PWR-01), `synth_core.tcl` và `sweep_core.sh` (`rv32_core` đứng riêng và quét chu kỳ, Nhân, `docs/genus_core.md`). `synth_block.tcl` còn tổng hợp được PicoRV32 cho EVA-02 (`B=picorv32`, `picorv32_I`, `picorv32_IM`) | Server trường: `make synth-accel`, `make synth-block B=<khối>`, `make synth-blocks`, `make synth-soc`, `make synth-soc-sweep`, `make power-soc`, `make synth-core`, `make synth-core-sweep` |
| `yosys/` | Tổng hợp thử bằng Yosys và STA với Nangate45, chỉ xem xu hướng. `sta_soc_nangate.tcl` và `sram_2k_macro_bb.v` cho `soc_top` với `soc.sdc` (STA-03) | Nhà: `make synth-core-yosys`, `make sta-core-nangate`, `make sta-soc-nangate` |

Thư mục chạy `run*/` và kết quả `out*/` bị ignore. Report chính thức copy vào `appendix/`. Cách chạy và tiêu chí: `docs/flow_notes.md`.
