# So sánh với lõi RISC-V khác (EVA-02)

Chủ: Hiếu, cùng Phát. So `rv32_core` với ba lõi RV32 mã nguồn mở: PicoRV32, Ibex, SERV. PicoRV32 chạy qua cùng flow Genus của nhóm (Phát, 19/11). Ibex và SERV lấy số liệu đã công bố, quy về cùng đơn vị kGE.

**Trạng thái (25/11):** xong. Số liệu của bảng này dùng cho EVA-03 (bảng PPA) và EVA-05 (đánh giá, so sánh).

## 1. Cách quy đổi

- **kGE** = diện tích cell chuẩn / diện tích NAND2X1 / 1000. Trong GPDK45 (`slow_vdd1v0`), NAND2X1 = 1,026 µm² (410,4 µm² cho 400 cell trong `appendix/core_signoff/synthesis/gates.rpt`). Cùng cách tính với `scripts/ppa_table.py`.
- **Hiệu năng:** CoreMark/MHz và DMIPS/MHz, đều là số trên mỗi MHz nên không phụ thuộc tần số.
- **Hiệu năng trên diện tích:** CoreMark/MHz chia kGE (hoặc DMIPS/MHz chia kGE).
- Số của `rv32_core`: Genus 28/10 (`appendix/core_signoff/`), cấu hình IM, BTB 8 entry. CoreMark và Dhrystone trên `tb_core` (bộ nhớ không wait state, `docs/bench_soc.md` dòng 42) và trên `soc_top`.

## 2. Bảng so sánh

| Lõi | Cấu hình | ISA | Diện tích (kGE) | Nguồn diện tích | CoreMark/MHz | DMIPS/MHz | CPI |
|-----|----------|-----|----------------:|-----------------|-------------:|----------:|----:|
| **`rv32_core`** | 3 tầng, BTB 8 entry, nhân chia | RV32IM | **29,46** | Genus 21.1, GPDK45, 20 ns | **3,22** (tb_core), 3,21 (soc_top) | **0,93** (tb_core), 0,88 (soc_top) | 1,09 (CoreMark, soc_top) |
| PicoRV32 | mặc định | RV32I | 17,54 | Genus, cùng flow | - | - | khoảng 4 |
| PicoRV32 | I (barrel shifter, IRQ) | RV32I | 20,72 | Genus, cùng flow | - | - | khoảng 4 |
| PicoRV32 | IM (nhân nhanh, chia) | RV32IM | 28,78 | Genus, cùng flow | - | 0,516 | 4,1 (Dhrystone) |
| Ibex | micro | RV32EC | 16,85 (khoảng 15) | README Ibex: Yosys (ước lượng thương mại) | 0,904 | - | - |
| Ibex | small, nhân 3 chu kỳ | RV32IMC | 26,60 (khoảng 24) | như trên | 2,47 | - | - |
| Ibex | maxperf, nhân 1 chu kỳ, branch target ALU, tầng writeback | RV32IMC | 32,48 (khoảng 30) | như trên | 3,13 | - | - |
| Ibex | maxperf-pmp-bmfull, thêm B và 16 vùng PMP | RV32IMCB | 66,02 (khoảng 61) | như trên | 3,13 | - | - |
| SERV | tối giản, bit-serial | RV32I (M, C tuỳ chọn) | 2,1 | README SERV: "CMOS điển hình" | - | - | khoảng 32 đến 64 |

Ghi chú:
- PicoRV32: số DMIPS/MHz và CPI lấy từ README PicoRV32 (có `ENABLE_FAST_MUL`, `ENABLE_DIV`, `BARREL_SHIFTER`, dùng look-ahead interface). Không có look-ahead thì còn 0,305 DMIPS/MHz, CPI 5,232. README không có số CoreMark.
- Ibex: CoreMark/MHz đo trên Ibex Simple System. Diện tích Yosys dùng register file kiểu latch. Số trong ngoặc là ước lượng của lowRISC cho flow thương mại.
- SERV: README chỉ cho diện tích, không cho hiệu năng. CPI lấy từ các bài đo SERV: lệnh một pha khoảng 32 chu kỳ cộng thời gian fetch, lệnh hai pha khoảng 64 chu kỳ, lệnh store đo được khoảng 69 chu kỳ.

## 3. Hiệu năng trên diện tích

| Lõi | CoreMark/MHz / kGE | DMIPS/MHz / kGE |
|-----|-------------------:|----------------:|
| **`rv32_core`** (IM) | **0,109** | **0,032** (tb_core), 0,030 (soc_top) |
| Ibex small (IMC) | 0,093 (Yosys), 0,103 (thương mại) | - |
| Ibex maxperf (IMC) | 0,096 (Yosys), 0,104 (thương mại) | - |
| Ibex micro (EC) | 0,054 | - |
| PicoRV32 IM | - | 0,018 |

## 4. Nhận xét

- **So với PicoRV32 (cùng flow, so trực tiếp được):** cùng RV32IM, diện tích gần bằng (29,46 so với 28,78 kGE, lớn hơn 2,4%). DMIPS/MHz cao hơn khoảng 1,7 lần (0,88 đến 0,93 so với 0,516) vì CPI khoảng 1,1 so với khoảng 4. Hiệu năng trên diện tích cao hơn khoảng 1,7 lần.
- **So với Ibex (số công bố, so gần đúng):** `rv32_core` có CoreMark/MHz (3,22) ngang Ibex maxperf (3,13) và cao hơn Ibex small (2,47). Diện tích 29,46 kGE nằm giữa small và maxperf. Hiệu năng trên diện tích ngang hoặc nhỉnh hơn Ibex một chút (0,109 so với 0,093 đến 0,104).
- **So với SERV:** SERV nhỏ hơn khoảng 14 lần (2,1 kGE) nhưng mỗi lệnh mất khoảng 32 đến 64 chu kỳ, nên chậm hơn khoảng 30 đến 60 lần ở cùng tần số. SERV hợp với điều khiển đơn giản, không hợp với tính toán.
- Phần lớn diện tích của `rv32_core` là flop: 2163 flop `DFFRHQX1` chiếm 13 254 µm² (44% lõi). Riêng register file có 992 flop, khoảng 6 kGE. Đổi register file sang latch như Ibex là hướng giảm diện tích lớn nhất (đề xuất cho EVA-05).

## 5. Giới hạn của phép so sánh

- Chỉ PicoRV32 chạy cùng flow, cùng thư viện. Số Ibex và SERV từ flow và thư viện khác, nên kGE chỉ so được gần đúng (sai khác có thể 10 đến 20%, như khoảng cách giữa số Yosys và số thương mại của Ibex).
- Ibex có lệnh nén C, `rv32_core` không có. Lệnh C làm code nhỏ hơn nhưng ảnh hưởng ít tới CoreMark/MHz.
- CoreMark phụ thuộc trình biên dịch và cờ. Nhóm dùng GCC 16 (`docs/bench_soc.md`), Ibex Simple System dùng toolchain của lowRISC.
- `rv32_core` dùng register file flop có reset, Ibex dùng latch. Diện tích Ibex vì vậy thấp hơn một phần do cách làm register file, không chỉ do kiến trúc.
- Công suất không so, vì các nguồn không công bố công suất cùng điều kiện. Công suất của `soc_top` theo testcase ở `docs/power_soc.md` (PWR-01).

## 6. Nguồn

- PicoRV32: `ref/picorv32` commit `ef203c2`, Genus ở `appendix/synth_picorv32/`, `docs/sta_results.md` mục 3. README: https://github.com/YosysHQ/picorv32
- Ibex README (bảng cấu hình): https://github.com/lowRISC/ibex
- SERV README (bảng tài nguyên): https://github.com/olofk/serv
- CPI của SERV: arXiv 2304.05837 (đo CPI từng lệnh trên bộ compliance test), arXiv 2509.08193 (32 chu kỳ cho lệnh một pha, khoảng 64 cho lệnh hai pha).
