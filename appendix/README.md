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
| `synth_soc_reset/`, `sta_soc_reset/` | Genus và Tempus `soc_top` ngày 31/10, mạng reset có buffer, netlist giao cho PnR |
| `core_signoff/` | Genus, LEC và GLS cho core `rv32_core` (D-042) |
| `pnr_accel/` | Innovus cho accelerator: timing từng bước, DRC, connectivity, antenna, công suất |

Chỉ đưa report dạng văn bản. Không đưa netlist, SPEF, SDF, database hay file nào của GPDK45.
