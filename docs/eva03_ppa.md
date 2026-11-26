# Bảng PPA của SoC (EVA-03)

Chủ: Nhân. Gom số power, performance, area chính thức của `soc_top` và `rv32_core` vào một chỗ, quy diện tích về GE và kiểm lại EPI. Số lấy từ report đã chép về `appendix/` và từ các tài liệu kết quả, không chạy lại tool. Ngày 26/11.

Số nào đổi khi có layout cuối (PD-08) và công suất sau layout (PWR-02) thì ghi ở mục 7. EVA-04 đã cập nhật các số đó ngày 26/11.

## 1. Bảng PPA chính

Chu kỳ chốt 10 ns (100 MHz). Tổng hợp và PnR ở 9 ns để layout còn biên (`docs/sta_results.md` mục 5).

| Nhóm | Chỉ số | Giá trị | Điều kiện đo | Nguồn |
| --- | --- | --- | --- | --- |
| Timing | Tần số signoff | **100 MHz** | Tempus trên layout cuối `route_trim` (STA-06), 4 view, setup +0,977 ns, hold +0,020 ns, recovery +7,434 ns, removal +0,023 ns | `sta_results.md` mục 6 |
| Timing | F_max sau tổng hợp | **khoảng 200 MHz** | Genus quét chu kỳ, 5 ns đạt, 4,5 ns thiếu 0,208 ns | `sta_results.md` mục 4 |
| Timing | F_max sau layout | **khoảng 110,8 MHz** | Tempus trên SPEF sau route, chu kỳ nhỏ nhất 9,023 ns, corner slow, RC typical | `sta_results.md` mục 6 |
| Area | Cell chuẩn sau tổng hợp | 60 187 µm² = **58,66 kGE** | Genus 9 ns, netlist `e60437a`, 4068 flop, 136 ICG | `appendix/synth_soc_e60437a/` |
| Area | Cell chuẩn sau layout | 71 800 µm² = **69,98 kGE** | Innovus `_p9`, không tính filler. Layout cuối `route_trim` không đổi (mục 2) | `appendix/pnr_soc_p9/summary/` |
| Area | Macro SRAM | 64 000 µm² | 8 macro `sram_2k_macro` (IMEM 16 KB, DMEM 16 KB) | `gates.rpt`, summary Innovus |
| Area | Lõi chip, mật độ | 420 × 420,7 µm, **63,7%** ngoài macro | Innovus `_p9`, macro chiếm 36,2% lõi | `pnr_soc_status.md` mục 6 |
| Area | Riêng `rv32_core` | 30 226 µm² = **29,46 kGE** | Genus 20 ns, 28/10, IM, BTB 8 entry | `appendix/core_signoff/synthesis/` |
| Power | Công suất theo testcase, trước layout | 0,306 đến 0,478 mW | Genus, SAIF từ GLS, slow, 10 ns (PWR-01) | `power_soc.md` mục 5 |
| Power | Công suất theo testcase, sau layout | **0,580 đến 0,965 mW** | Innovus, SAIF của PWR-01, SPEF `route_eco`, slow, 10 ns (PWR-02) | `power_soc.md` mục 9 |
| Power | Công suất CoreMark | 0,456 mW trước layout, **0,907 mW** sau layout | Như trên, `coremark_rv32im` | `power_soc.md` mục 5 và 9 |
| Power | Static power (leakage) sau layout | **0,0179 đến 0,0211 mW** | Như PWR-02, chiếm khoảng 2 đến 3% tổng | `appendix/power_soc_post/summary.md` |
| Power | EPI | 4,53 đến 5,86 pJ/lệnh trước layout, **8,69 đến 11,59 pJ/lệnh** sau layout, CoreMark 5,14 và 10,23 | EPI = P × CPI / f | Mục 4 |
| Perf | CPI (vùng đo), IPC = 1/CPI | CPI 1,094 (CoreMark), 1,206 (Dhrystone). IPC 0,914 và 0,829 | RTL `soc_top`, rv32im, M1W1 | `bench_soc.md` |
| Perf | DMIPS/MHz | **0,882** | Như trên | `bench_soc.md` |
| Perf | CoreMark/MHz | **3,210** | Như trên, 3 vòng | `bench_soc.md` |
| Perf | Ở 100 MHz | 88,2 DMIPS, 321 CoreMark | Nhân hai số trên với 100 | Tính |
| Clock gating | So với CG=0 | Cell chuẩn **−9,3%**, công suất **−60,4%** | Genus 9 ns, activity mặc định | `sta_results.md` mục 5 |

## 2. Diện tích và GE

GE = diện tích cell chuẩn / diện tích NAND2X1. Trong `slow_vdd1v0`, NAND2X1 = **1,026 µm²**. Số này đọc được từ hai `gates.rpt`: `core_signoff` (400 cell, 410,400 µm²) và `synth_soc_e60437a` (1326 cell, 1 360,476 µm²). Innovus `area.rpt` cũng ghi `Gate area 1.0260 um^2`.

GE chỉ tính cell chuẩn. Macro SRAM không làm từ cổng logic nên không quy về GE, ghi riêng µm².

| Dòng | Cell chuẩn (µm²) | GE | kGE | Flop | ICG | Report |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `rv32_core`, Genus 20 ns | 30 226,4 | 29 460 | 29,46 | 2163 | 58 | `appendix/core_signoff/synthesis/` |
| `soc_top`, Genus 9 ns, CG=1 (chính thức) | 60 187,5 | 58 662 | 58,66 | 4068 | 136 | `appendix/synth_soc_e60437a/` |
| `soc_top`, Genus 9 ns, CG=0 (đối chiếu) | 66 336,9 | 64 656 | 64,66 | 4068 | 0 | `appendix/synth_soc_cg0_p9/` |
| `soc_top`, sau layout `_p9` | 71 800,2 | 69 981 | 69,98 | - | - | `appendix/pnr_soc_p9/` |

Ghi chú:
- Diện tích tổng của Genus (124 187,5 µm²) và Innovus `area.rpt` (135 800,2 µm²) đều gồm 64 000 µm² macro. Bảng trên đã trừ macro.
- Số sau layout lấy dòng `Total area of Standard cells(Subtracting Physical Cells)` trong summary Innovus, tức là không tính filler. Mật độ 63,7% là dòng `Pure Gate Density #4` (trừ macro và filler). Cùng số với 71 800 / (176 677 − 64 000).
- Layout cuối `route_trim` (PD-08) chỉ sửa lưới `VSS`, netlist không đổi (`pnr_soc_status.md` mục 8). Vì vậy diện tích cell, GE, mật độ và F_max sau layout giữ như `_p9`. Signoff 100 MHz đo lại trên layout cuối vẫn +0,977 ns (STA-06, `appendix/sta_soc_p9_trim/`).
- Sau layout cell chuẩn tăng 19,3% so với sau tổng hợp. Phần tăng là cây clock của CTS, buffer sửa hold và buffer của tối ưu sau route.
- Lõi `rv32_core` chiếm khoảng 50% cell chuẩn của SoC sau tổng hợp. Phần còn lại là accelerator, DMA, ngoại vi, bus.
- Số `rv32_core` khớp `docs/eva02_compare.md` (29,46 kGE). Hiệu năng trên diện tích của lõi: 3,210 / 29,46 = 0,109 CoreMark/MHz/kGE.
- Số `rv32_core` là lần tổng hợp riêng ở 20 ns ngày 28/10. Trong SoC, lõi được tổng hợp cùng netlist 9 ns nên có thể lớn hơn một chút. Repo không có report diện tích riêng của lõi trong netlist 9 ns.

## 3. Timing

| Bước | Chu kỳ | Setup | Hold | Report |
| --- | --- | --- | --- | --- |
| Genus, netlist chính thức | 9 ns | +0,7 ps | Chưa kiểm (clock lý tưởng) | `appendix/synth_soc_e60437a/qor.rpt` |
| Tempus trước layout | 10 ns | +0,978 ns | −0,141 ns (trước CTS, Innovus sửa sau) | `appendix/sta_soc_p9/` |
| Innovus sau ECO | 9 ns | −0,047 ns | +0,020 ns | `appendix/pnr_soc_p9/eco/` |
| Tempus sau route, 4 view | 10 ns | +0,977 ns | +0,020 ns | `appendix/sta_soc_p9_sta05/route_10_cross/` |
| **Tempus layout cuối `route_trim`, 4 view (signoff, STA-06)** | **10 ns** | **+0,977 ns** | **+0,020 ns** | `appendix/sta_soc_p9_trim/` |

- F_max sau tổng hợp khoảng 200 MHz lấy từ lần quét chu kỳ, không lấy từ slack ở 9 ns. Genus chỉ tối ưu tới khi vừa đạt, nên 1 / (9 − 0,0007) ≈ 111 MHz không phải F_max.
- F_max sau layout khoảng 110,8 MHz là số Tempus. Innovus ở 9 ns cho −0,047 ns, tức khoảng 110,5 MHz, chênh dưới 0,03 ns như các lần trước.
- Signoff 100 MHz dư khoảng 10% so với F_max sau layout.

## 4. Công suất và EPI (PWR-01, PWR-02)

PWR-01: Genus đọc SAIF của GLS (netlist STA-04, zero delay), corner slow, clock 10 ns. Trước layout, chưa có cây clock thật và tải dây thật. PWR-02: Innovus, cùng SAIF, SPEF sau ECO của `route_eco`, góc slow, clock 10 ns (`docs/power_soc.md` mục 9). Instret lấy từ mô phỏng RTL, chu kỳ lấy từ GLS (`docs/power_soc.md` mục 2 và 5).

| Testcase | Chu kỳ (GLS) | Instret | CPI | IPC | P PWR-01 (mW) | Năng lượng PWR-01 (µJ) | EPI = E / instret (pJ) | EPI = P × CPI / f (pJ) | P sau layout (PWR-02, mW) | Leakage sau layout (mW) | Năng lượng sau layout (µJ) | EPI sau layout (pJ) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `soc` | 2 458 | 1 604 | 1,532 | 0,653 | 0,3060 | 0,0075 | 4,69 | 4,69 | 0,5800 | 0,0179 | 0,0143 | 8,89 |
| `dma` | 12 539 | 8 963 | 1,399 | 0,715 | 0,3826 | 0,0480 | 5,35 | 5,35 | 0,7541 | 0,0195 | 0,0946 | 10,55 |
| `i2c` | 1 503 | 1 066 | 1,410 | 0,709 | 0,3214 | 0,0048 | 4,53 | 4,53 | 0,6161 | 0,0185 | 0,0093 | 8,69 |
| `spi_pwm` | 2 606 | 1 934 | 1,347 | 0,742 | 0,3584 | 0,0093 | 4,83 | 4,83 | 0,6919 | 0,0186 | 0,0180 | 9,32 |
| `soc_fw_rv32im` | 247 980 | 217 079 | 1,142 | 0,875 | 0,4776 | 1,1844 | 5,46 | 5,46 | 0,9647 | 0,0189 | 2,3923 | 11,02 |
| `coremark_rv32im` | 1 040 707 | 922 375 | 1,128 | 0,886 | 0,4557 | 4,7425 | 5,14 | 5,14 | 0,9069 | 0,0202 | 9,4384 | 10,23 |
| `dhrystone_rv32im` | 378 275 | 305 018 | 1,240 | 0,806 | 0,4090 | 1,5471 | 5,07 | 5,07 | 0,8071 | 0,0211 | 3,0530 | 10,01 |
| `accel_bench_rv32im` | 162 595 | 117 726 | 1,381 | 0,724 | 0,4245 | 0,6902 | 5,86 | 5,86 | 0,8389 | 0,0198 | 1,3640 | 11,59 |

Kiểm lại:
- EPI = P × CPI / f với f = 100 MHz và CPI = chu kỳ / instret. Cả 8 testcase ra đúng EPI ở `docs/power_soc.md` mục 5. Hai cách tính trùng nhau vì P × (chu kỳ / instret) / f = (P × chu kỳ / f) / instret.
- Ví dụ CoreMark: 0,4557 mW × 1,128 / 100 MHz = 5,14 pJ/lệnh.
- `appendix/power_soc_pre/summary.md` ghi năng lượng CoreMark 4,7428 µJ, tính từ công suất chưa làm tròn. Từ 0,4557 mW ra 4,7425 µJ như `power_soc.md`. Chênh 0,01%, không ảnh hưởng EPI.
- CPI ở đây là của cả chương trình, kể cả khởi động và in kết quả. CPI ở mục 1 (1,094 cho CoreMark) chỉ tính vùng đo của benchmark, nên nhỏ hơn.
- Năng lượng mỗi chu kỳ của CoreMark: 0,4557 mW / 100 MHz = 4,56 pJ.
- IPC = 1 / CPI = instret / chu kỳ.
- Cột sau layout lấy từ `docs/power_soc.md` mục 9 và `appendix/power_soc_post/summary.md`. Kiểm lại EPI = P × CPI / f với công suất chưa làm tròn trong `summary.md`: cả 8 testcase ra đúng EPI và năng lượng của `power_soc.md` mục 9, không lệch. Ví dụ CoreMark: 0,9069 mW × 1,128 / 100 MHz = 10,23 pJ/lệnh.
- Công suất sau layout bằng 1,90 đến 2,02 lần trước layout, nên EPI cũng tăng cùng tỉ lệ (CPI không đổi). Leakage sau layout 0,0179 đến 0,0211 mW, gần bằng trước layout (0,0173 đến 0,0205 mW).

Số công suất tham khảo, không dùng cho bảng chính:

| Trường hợp | P (mW) | Lý do không dùng |
| --- | ---: | --- |
| Genus, activity mặc định, 10 ns | 0,736 | Toggle mặc định của tool, bi quan hơn SAIF 35 đến 58% |
| Genus, activity mặc định, 9 ns (STA-04) | 0,817 | Như trên, chu kỳ 9 ns |
| Innovus `_p9`, activity 0,2, 9 ns | 3,235 | Toggle 0,2 cho mọi flop và chân vào, cao hơn thực tế nhiều. Switching chiếm 54% |
| `rv32_core` riêng, Genus mặc định, 20 ns | 0,219 | Chỉ lõi, activity mặc định, khác chu kỳ |

## 5. Hiệu năng (EVA-01)

RTL `soc_top` ở commit `6f02f2b` (12/11), trước RTL freeze. GCC 16.1, `-O2`. Chu kỳ và số lệnh trong vùng đo (`mcycle`, `minstret`).

| Benchmark | Cấu hình | CPI | Hiệu năng / MHz | Ở 100 MHz |
| --- | --- | ---: | --- | --- |
| Dhrystone | rv32i, M0W1 | 1,143 | 0,881 DMIPS/MHz | 88,1 DMIPS |
| Dhrystone | rv32im, M1W1 | 1,206 | **0,882 DMIPS/MHz** | 88,2 DMIPS |
| CoreMark | rv32i, M0W1 | 1,105 | 1,260 CoreMark/MHz | 126 |
| CoreMark | rv32im, M1W1 | 1,094 | **3,210 CoreMark/MHz** | 321 |

- Cấu hình chính của SoC là rv32im (`ENABLE_M=1`), cũng là cấu hình đo công suất.
- CoreMark chỉ chạy 3 vòng nên chưa phải điểm CoreMark chính thức (`docs/bench_soc.md`, Giới hạn đo).
- Accelerator 16 × 16 nhanh hơn phần mềm 1,61 lần (rv32im) và 23,12 lần (rv32i), bản poll.

## 6. Điều kiện đo

| Số | Tool | Corner | Chu kỳ | Activity | Ghi chú |
| --- | --- | --- | --- | --- | --- |
| Diện tích sau tổng hợp | Genus 21.10 | slow 0,9 V 125 °C | 9 ns | - | Wireload enclosed, chưa có dây |
| Diện tích, mật độ sau layout | Innovus 21.19 | - | 9 ns | - | Layout `_p9` sau ECO, không tính filler |
| F_max sau tổng hợp | Genus 21.10 | slow | Quét 20 đến 4 ns | - | Macro chỉ có `.lib` typical |
| Signoff, F_max sau layout | Tempus 23.14 | slow và fast, RC typical | 10 ns (quét 9 đến 8 ns) | - | 4 view, clock propagated |
| Công suất, EPI | Genus 21.1 | slow 1,0 V 125 °C | 10 ns | SAIF từ GLS zero delay | Trước layout, PDK không có `.lib` typical |
| Công suất, EPI sau layout | Innovus 21.19 | slow, RC typical | 10 ns | SAIF của PWR-01 | `route_eco`, SPEF sau ECO (PWR-02) |
| CPI, DMIPS, CoreMark | Icarus (RTL) | - | - | - | Số chu kỳ không đổi theo tần số, nhân với f để ra hiệu năng |
| Riêng `rv32_core` | Genus 21.10 | slow 0,9 V 125 °C | 20 ns | Mặc định | `core.sdc` có delay macro SRAM |

Header của report Genus ghi `PVT_0P9V_125C` còn `power_soc.md` ghi 1,0 V. Đây là cùng thư viện `slow_vdd1v0`, giữ đúng như tài liệu nguồn.

## 7. Đã cập nhật ở EVA-04 (26/11)

| Số | Trước EVA-04 | Sau EVA-04 (26/11) | Nguồn |
| --- | --- | --- | --- |
| Cell chuẩn sau layout, GE, mật độ | 71 800 µm², 69,98 kGE, 63,7% (`_p9`) | Không đổi trên layout cuối `route_trim`, vì PD-08 chỉ sửa `VSS` và netlist không đổi | `pnr_soc_status.md` mục 8 |
| Signoff 100 MHz, F_max sau layout | +0,977 ns, khoảng 110,8 MHz | STA-06 trên `route_trim`: setup +0,977, hold +0,020, recovery +7,434, removal +0,023 ns. F_max không đổi | `sta_results.md` mục 6, `appendix/sta_soc_p9_trim/` |
| Công suất, EPI theo testcase | 0,306 đến 0,478 mW, 4,53 đến 5,86 pJ (trước layout) | Sau layout 0,580 đến 0,965 mW, 8,69 đến 11,59 pJ (PWR-02) | Mục 4, `power_soc.md` mục 9 |
| Static power (leakage) | 0,0173 đến 0,0205 mW (trước layout) | 0,0179 đến 0,0211 mW (sau layout) | `appendix/power_soc_post/summary.md` |
| IPC | Chưa ghi | IPC = 1/CPI, thêm vào mục 1 và mục 4 | Mục 1, mục 4 |

Số không đổi ở EVA-04 (RTL đã freeze 15/11, netlist không đổi): diện tích và GE sau tổng hợp, F_max sau tổng hợp, CPI, DMIPS/MHz, CoreMark/MHz, số riêng của `rv32_core`, so sánh clock gating.

Giới hạn còn lại:
- Công suất cây clock chưa tách riêng. PWR-02 chỉ cho tổng theo leakage, internal, switching.
- PWR-02 chạy trên `route_eco`, không phải `route_trim`. SPEF của layout cuối chỉ đổi tổng điện dung ở 2 trên 27 329 net (nhiều nhất 0,049%), nên nhóm không chạy lại.
- Chỉ có góc slow (RC typical) cho công suất.

### Đối chiếu với điểm cộng PPA của đề bài

| Mục PPA | Chỉ số | Số đã có | Nguồn |
| --- | --- | --- | --- |
| Performance | F_max | Khoảng 200 MHz sau tổng hợp, khoảng 110,8 MHz sau layout, signoff 100 MHz | Mục 1 và 3, `sta_results.md` mục 4 và 6 |
| Performance | CPI, IPC | Vùng đo: CPI 1,094 và IPC 0,914 (CoreMark), CPI 1,206 và IPC 0,829 (Dhrystone). Cả chương trình: CPI 1,128 đến 1,532 | Mục 1, 4, 5, `bench_soc.md` |
| Power | Dynamic theo toggle rate 0,1 | Innovus trên `route_eco`: internal 0,962 mW, switching 1,001 mW (tổng 1,975 mW, leakage 0,011 mW) | `ir_drop.md` mục 5 (`power_act0.1.rpt`) |
| Power | Dynamic theo toggle rate 0,5 | Chưa có. Lần chạy IR ở hoạt độ 0,5 không ghi công suất vào repo | `appendix/ir_drop_trim/act0.5/` |
| Power | Theo 8 testcase | 0,306 đến 0,478 mW trước layout, 0,580 đến 0,965 mW sau layout | Mục 4, `power_soc.md` mục 5 và 9 |
| Power | Static (leakage) | 0,0179 đến 0,0211 mW sau layout | Mục 4, `appendix/power_soc_post/summary.md` |
| Power | EPI | 4,53 đến 5,86 pJ/lệnh trước layout, 8,69 đến 11,59 pJ/lệnh sau layout | Mục 4 |
| Area | Physical area | Lõi 420 × 420,7 µm, cell chuẩn 71 800 µm², macro 64 000 µm² | Mục 1 và 2, `appendix/pnr_soc_p9/summary/` |
| Area | GE | 58,66 kGE sau tổng hợp, 69,98 kGE sau layout | Mục 2 |
| Area | Density | 63,7% ngoài macro | Mục 2, `pnr_soc_status.md` mục 6 |

## 8. Chạy lại bảng

`scripts/ppa_table.py` đọc report trong `appendix/`, chạy ở nhà không cần tool EDA:

```sh
python3 scripts/ppa_table.py \
  --genus core=appendix/core_signoff/synthesis \
  --genus soc9=appendix/synth_soc_e60437a \
  --genus cg0=appendix/synth_soc_cg0_p9 \
  --innovus p9=appendix/pnr_soc_p9 \
  --saif appendix/power_soc_pre/summary.md \
  --instret soc=1604 --instret dma=8963 --instret i2c=1066 --instret spi_pwm=1934 \
  --instret soc_fw_rv32im=217079 --instret coremark_rv32im=922375 \
  --instret dhrystone_rv32im=305018 --instret accel_bench_rv32im=117726
```

Bảng thứ nhất là diện tích, GE, slack, công suất của tool theo từng lần chạy. Bảng thứ hai là công suất và EPI theo testcase (mục 4). Script tách diện tích macro ra khỏi cell chuẩn, lấy chu kỳ riêng của từng lần chạy, và lấy timing Innovus trong `eco/` nếu có.

Cột F_max của script là 1 / (chu kỳ − slack), chỉ là ước lượng. F_max chính thức lấy từ lần quét chu kỳ (mục 3). Cột công suất của script là activity mặc định của tool, không phải số SAIF.

Khi có PWR-02, chạy lại với `--innovus` trỏ tới report layout cuối và `--saif` trỏ tới bảng công suất sau layout.
