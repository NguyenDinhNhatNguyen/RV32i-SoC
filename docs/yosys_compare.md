# Tổng hợp thử bằng Yosys (chỉ xem xu hướng)

**Các số ở đây chỉ để xem xu hướng.** Yosys ánh xạ sang cổng logic chung (`$_AND_`, `$_MUX_`, `$_DFFE_`...), không dùng thư viện GPDK45 và không có ràng buộc thời gian.
Số cell không đổi được ra diện tích µm². Đường dài nhất tính bằng số cell trên đường tổ hợp, không phải ns.
Số chính thức (diện tích, tần số, công suất) lấy từ Genus và Innovus ở trường.

## Cách chạy

```sh
make synth-core-yosys       # chỉ rv32_core
make synth-compare-yosys    # rv32_core và PicoRV32
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
- Đường dài nhất không đi qua bộ nhân. Nó bắt đầu từ trường địa chỉ CSR của lệnh ở EX và kết thúc ở `ex_fetch_q <= ex_go & if_fire & ~ex_redirect & ~wb_redirect`, tức là đi qua phần giải mã lệnh và quyết định dừng hoặc chuyển hướng pipeline. Đây là chỗ nên xem đầu tiên nếu Genus báo vi phạm setup.

## So sánh sơ bộ với PicoRV32

PicoRV32 là submodule `ref/picorv32` (commit ef203c2, không sửa), top `picorv32`, cùng script Yosys.
Ba cấu hình:

- **mặc định**: RV32I, bộ đếm, shift 2 bước, không ngắt.
- **I**: thêm `BARREL_SHIFTER=1`, `ENABLE_IRQ=1`, gần tính năng rv32_core ENABLE_M=0 (shift 1 chu kỳ, có ngắt).
- **IM**: thêm `ENABLE_FAST_MUL=1`, `ENABLE_DIV=1`, gần rv32_core ENABLE_M=1. Đây cũng là cấu hình PicoRV32 dùng để công bố Dhrystone.

| Core | Cấu hình | Cell | Flip-flop | Đường dài nhất (cell) | CPI | DMIPS/MHz |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| rv32_core | ENABLE_M=0 | 11 017 | 1 469 | 58 | 1,16 (Dhrystone), 1,20 (CoreMark) | 0,839 |
| rv32_core | ENABLE_M=1 | 19 595 | 1 673 | 58 | 1,23 (Dhrystone), 1,16 (CoreMark) | 0,839 |
| PicoRV32 | mặc định | 8 038 | 1 597 | 23 | khoảng 4 | - |
| PicoRV32 | I | 10 252 | 1 866 | 24 | - | - |
| PicoRV32 | IM | 19 156 | 2 238 | 44 | 4,100 (Dhrystone) | 0,516 |

Nguồn số hiệu năng:

- rv32_core: đo bằng `make bench-core` (`docs/bench_core.md`), bộ nhớ không wait state.
- PicoRV32: lấy từ README của PicoRV32 (cấu hình IM, giao diện bộ nhớ look-ahead), **không đo lại** trong repo này. Không dùng look-ahead thì còn 0,305 DMIPS/MHz, CPI 5,232.

Nhận xét sơ bộ:

- Cùng mức tính năng (ENABLE_M=0 với PicoRV32 I), rv32_core có số cell tương đương (11,0k so với 10,3k), ít flip-flop hơn, nhưng DMIPS/MHz cao hơn khoảng 1,6 lần nhờ pipeline 3 tầng (CPI khoảng 1,2 so với khoảng 4).
- Đổi lại, đường tổ hợp dài nhất của rv32_core gấp khoảng 2,4 lần PicoRV32 (58 so với 24 cell). PicoRV32 thiết kế để đạt fmax cao, mỗi lệnh chia ra nhiều chu kỳ ngắn. Nếu fmax tỉ lệ nghịch với số tầng logic thì hiệu năng tuyệt đối của hai core gần nhau hơn, nhưng đề bài chỉ cần 50 MHz nên CPI thấp có lợi hơn.
- Có RV32M thì hai core gần bằng nhau về số cell. PicoRV32 IM có đường dài 44 cell qua bộ nhân nhanh, rv32_core vẫn 58 vì đường dài nhất không nằm ở bộ nhân.
- PicoRV32 có thêm thanh ghi x0 và 4 thanh ghi q của ngắt trong regfile nên nhiều flip-flop hơn.

Những điểm làm bảng này **chưa công bằng**:

- Hai core không cùng tính năng. rv32_core có CSR M-mode đầy đủ hơn (mtvec, mepc, mcause, mtval, mie, mip, bộ đếm 64 bit), PicoRV32 dùng cơ chế ngắt riêng, không có CSR trap chuẩn.
- Giao diện bộ nhớ khác nhau (rv32_core: cổng lệnh và cổng dữ liệu riêng, PicoRV32: một cổng chung).
- Số tầng logic không tính tải và loại cổng. Phải có Genus với GPDK45 và SDC mới so được tần số.
