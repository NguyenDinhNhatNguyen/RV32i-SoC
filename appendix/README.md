# Phụ lục

Report và log chính thức copy từ server để đưa vào report. Mỗi bước một thư mục:

| Thư mục | Nội dung |
| --- | --- |
| `server_check/` | Kết quả kiểm tra server (HT-01) |
| `synth_accel/` | Genus cho accelerator, `cg0` không clock gating và `cg1` có clock gating, kèm LEC và GLS |
| `synth_blocks/` | Genus tổng hợp thử từng khối của SoC (STA-02), mỗi khối một thư mục và `summary.txt` |
| `synth_soc/` | Genus cho cả `soc_top` với `soc.sdc`, report và `summary.txt` |
| `pnr_accel/` | Innovus cho accelerator: timing từng bước, DRC, connectivity, antenna, công suất |

Chỉ đưa report dạng văn bản. Không đưa netlist, SPEF, SDF, database hay file nào của GPDK45.
