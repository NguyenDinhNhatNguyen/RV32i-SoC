# Phụ lục

Report và log chính thức copy từ server để đưa vào report. Mỗi bước một thư mục:

| Thư mục | Nội dung |
| --- | --- |
| `server_check/` | Kết quả kiểm tra server (HT-01) |
| `synth_accel/` | Genus cho accelerator, `cg0` không clock gating và `cg1` có clock gating, kèm LEC và GLS |
| `pnr_accel/` | Innovus cho accelerator: timing từng bước, DRC, connectivity, antenna, công suất |

Chỉ đưa report dạng văn bản. Không đưa netlist, SPEF, SDF, database hay file nào của GPDK45.
