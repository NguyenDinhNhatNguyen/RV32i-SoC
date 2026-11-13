# Phụ lục

Report và log chính thức copy từ server để đưa vào report. Mỗi bước một thư mục:

| Thư mục | Nội dung |
| --- | --- |
| `server_check/` | Kết quả kiểm tra server (HT-01) |
| `synth_accel/` | Genus cho accelerator, `cg0` không clock gating và `cg1` có clock gating, kèm LEC và GLS |
| `synth_blocks/` | Genus tổng hợp thử từng khối của SoC (STA-02), mỗi khối một thư mục và `summary.txt` |
| `synth_soc/` | Genus cho cả `soc_top` với `soc.sdc`, report và `summary.txt` (29/10) |
| `synth_soc_keepflop/` | Genus `soc_top` giữ mọi flop cho LEC (30/10), mạng reset chưa có buffer |
| `synth_soc_sweep/` | Quét chu kỳ Genus `soc_top` (STA-03), mỗi chu kỳ một thư mục `p<ns>` |
| `sta_soc/` | Tempus trước layout của `soc_top` (STA-03): setup, hold, recovery, removal, coverage |
| `synth_soc_reset/`, `sta_soc_reset/` | Genus và Tempus `soc_top` ngày 31/10, mạng reset có buffer |
| `synth_soc_i2c/`, `sta_soc_i2c/` | Genus và Tempus `soc_top` ngày 12/11, có DMA, SPI, PWM, I2C, netlist giao cho PnR |
| `core_signoff/` | Genus, LEC và GLS cho core `rv32_core` (D-042) |
| `pnr_accel/` | Innovus cho accelerator: timing từng bước, DRC, connectivity, antenna, công suất |
| `pnr_soc/` | Innovus cho `soc_top` (PD-04, 12/11 và 13/11), lõi 405 × 405,3 µm, `slack_summary.txt` và `pd_checks.rpt` |
| `pnr_soc_u75/`, `pnr_soc_u70/`, `pnr_soc_u65/` | Innovus `soc_top` ở ba cỡ lõi khác (PD-07, 13/11), có `drc_after_eco.rpt` khi ECO sửa DRC |
| `macro_check/` | Thông tin macro `sram_2k_macro` đọc từ LEF và `.lib` trên server (29/10, 30/10) |
| `lint_hal/` | HAL lint của `soc_top` trên main `7008da2` (VER-03, 13/11): `summary.txt` và `xrun.log` |
| `ver06_bench/` | Output `make bench-core` và `make bench-soc` ngày 12/11 (VER-06), chạy ở nhà trong Docker |

Chỉ đưa report dạng văn bản. Không đưa netlist, SPEF, SDF, database hay file nào của GPDK45.
