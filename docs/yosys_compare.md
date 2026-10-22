# Tổng hợp thử bằng Yosys (chỉ xem xu hướng)

**Các số ở đây chỉ để xem xu hướng.** Yosys ánh xạ sang cổng logic chung (`$_AND_`, `$_MUX_`, `$_DFFE_`...), không dùng thư viện GPDK45 và không có ràng buộc thời gian.
Số cell không đổi được ra diện tích µm². Đường dài nhất tính bằng số cell trên đường tổ hợp, không phải ns.
Số chính thức (diện tích, tần số, công suất) lấy từ Genus và Innovus ở trường.

## Cách chạy

```sh
make synth-core-yosys
```

Script: `syn/yosys/synth.tcl` (`synth -flatten`, rồi `stat` và `ltp -noff`). Kết quả ở `syn/run_yosys/<nhãn>/` (bị ignore).
Script Genus trong `syn/scripts/` không bị đụng tới.

## rv32_core (Yosys 0.33, 22/10/2026)

| Cấu hình | Cell | Flip-flop | Đường dài nhất (cell) | Điểm đầu → điểm cuối |
| --- | ---: | ---: | ---: | --- |
| ENABLE_M=0 | 11 017 | 1 469 | 58 | `u_csr.addr_i` → `ex_fetch_q` |
| ENABLE_M=1 | 19 595 | 1 673 | 58 | `u_csr.addr_i` → `ex_fetch_q` |

Nhận xét:

- Regfile làm bằng flip-flop (31 × 32 = 992 FF), chiếm khoảng 2/3 số flip-flop.
- RV32M thêm khoảng 8 600 cell (+78%) và 204 flip-flop, phần lớn là bộ nhân 32×32 (nhiều XOR/XNOR).
- Đường dài nhất không đi qua bộ nhân. Nó bắt đầu từ địa chỉ CSR của lệnh ở EX, qua kiểm tra CSR hợp lệ, quyết định trap, chuyển hướng PC, tới `ex_fetch_q`. Đây là chỗ nên xem đầu tiên nếu Genus báo vi phạm setup ở 50 MHz.
