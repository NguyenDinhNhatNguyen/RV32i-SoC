# Phân tích công suất và IR drop (Voltus)

| File | Nội dung |
| --- | --- |
| `ir_static.tcl` | IR drop tĩnh của `soc_top` trong Innovus/Voltus, theo Lab 06 mục 3.2 (LEC-04) |
| `run_ir.sh` | Chạy `ir_static.tcl` bằng `innovus -batch` và tóm tắt kết quả |
| `voltus_collect.sh` | Chỉ đọc: thu thập đường dẫn database, thư viện và QRC trên server |
| `run_power_post.sh`, `power_post.tcl` | PWR-02: công suất sau layout theo testcase (SPEF của `_p9`, SAIF của PWR-01). Chạy `bash power/run_power_post.sh`, bảng ở `power/run_post/summary.md` |

Cách chạy, kết quả 20/11, sign-off trên layout cuối 26/11 và giới hạn: `docs/ir_drop.md`. Công suất theo testcase (PWR-01, PWR-02) dùng SAIF từ GLS, xem `docs/power_soc.md`. Thư mục `run*/` bị ignore.
