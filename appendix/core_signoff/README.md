# Sign-off core `rv32_core`

Report Genus, Conformal LEC và GLS Xcelium của core (`ENABLE_M=1`, BTB 8 entry, clock gating bật), copy từ server. Cách chạy và các sửa cho server ở `docs/genus_core.md` mục 6 và 7, D-042 trong `docs/core_decisions.md`.

## Kết quả chính

| Bước | Kết quả |
| --- | --- |
| Genus | Clock 20 ns, WNS +320.7 ps, TNS 0. 9974 cell (2221 cell tuần tự), diện tích 30226 µm². Công suất 0.219 mW |
| LEC | 2199 Equivalent, 0 Non-equivalent, 68 Abort (DFF của khối nhân và chia, thiếu license Ultra) |
| GLS | 49/49 PASS (rv32ui và rv32um) trên netlist kèm SDF, clock 20 ns |

Report Genus tạo ngày 28/10. LEC và GLS chạy ngày 30/10.

## Danh sách file

`synthesis/` (Genus 21.10, `slow_vdd1v0`, PVT 0.9 V 125 °C):

| File | Nội dung |
| --- | --- |
| `run_info.txt` | Tham số lần chạy: chu kỳ, clock gating, BTB, WNS |
| `qor.rpt` | Tóm tắt slack, số cell, diện tích |
| `area.rpt` | Diện tích theo instance |
| `gates.rpt` | Số lượng và diện tích từng loại cell |
| `power.rpt` | Công suất leakage, internal, switching theo nhóm |
| `clock_gating.rpt` | Thống kê clock gating |
| `timing.rpt` | Đường critical |
| `timing_paths.rpt` | Nhiều đường timing hơn để xem phân bố slack |
| `timing_lint.rpt` | Kiểm tra ràng buộc SDC (input, output, clock) |
| `post_syn_design_lint.rpt` | `check_design` sau tổng hợp |

`lec/` (Conformal 24.1):

| File | Nội dung |
| --- | --- |
| `lec_verification.rpt` | Verification report. Compare Results ghi ABORT do 68 điểm abort, không có Non-equivalent |
| `lec_unmapped.rpt` | Điểm không map, là latch ICG unreachable |

`gls/` (Xcelium 24.03, chọn 2 log trong 49 bài):

| File | Nội dung |
| --- | --- |
| `rv32ui-p-add.log` | Bài `add` trên netlist kèm SDF, PASS |
| `rv32um-p-mul.log` | Bài `mul` trên netlist kèm SDF, PASS |

Không đưa netlist, SDF hay file nào của GPDK45.
