# Đánh giá kết quả và hướng phát triển (EVA-05)

Chủ: Nhân. Đánh giá kết quả cuối của `soc_top`, đối chiếu với yêu cầu đề bài, so với thiết kế tương tự và nêu hướng phát triển. Số lấy từ các tài liệu kết quả đã có, không chạy lại tool. Mỗi số ghi rõ file và mục nguồn. Ngày 26/11.

## 1. Tóm tắt

- **Signoff 100 MHz** trên layout cuối `route_trim` (STA-06): Tempus 4 view, setup +0,977 ns, hold +0,020 ns, recovery +7,434 ns, removal +0,023 ns, 0 vi phạm (`sta_results.md` mục 6).
- **F_max** khoảng 200 MHz sau tổng hợp và khoảng 110,8 MHz sau layout (chu kỳ nhỏ nhất 9,023 ns). Hai số đo trên hai netlist khác nhau, không so trực tiếp (mục 6). Signoff 100 MHz dư khoảng 10% (`sta_results.md` mục 4 và 6).
- **Diện tích:** cell chuẩn 58,66 kGE sau tổng hợp, 69,98 kGE sau layout, cộng 64 000 µm² macro SRAM. Lõi chip 420 × 420,7 µm, mật độ 63,7% ngoài macro. Riêng `rv32_core` 29,46 kGE (`eva03_ppa.md` mục 1 và 2).
- **Công suất sau layout** theo 8 testcase: 0,580 đến 0,965 mW, EPI 8,69 đến 11,59 pJ/lệnh. CoreMark 0,907 mW và 10,23 pJ/lệnh (`power_soc.md` mục 9, `eva03_ppa.md` mục 4).
- **Hiệu năng:** CPI 1,094 với CoreMark, 3,210 CoreMark/MHz, 0,882 DMIPS/MHz. Ở 100 MHz là 321 CoreMark và 88,2 DMIPS (`bench_soc.md`, `eva03_ppa.md` mục 1).
- **Sign-off sạch:** LEC-05 0 Non-equivalent, GLS có SDF 71/71 PASS ở hai góc max và min, DRC 0, antenna 0, connectivity sạch, IR drop lớn nhất 1,69 mV so với ngưỡng 45 mV (mục 2).

## 2. Đối chiếu yêu cầu bắt buộc của đề bài

Danh sách yêu cầu theo `spec/requirements.md`.

| Yêu cầu | Kết quả | Bằng chứng |
| --- | --- | --- |
| Kiến trúc bắt buộc: core RV32I, SRAM hard macro, accelerator, interconnect, Timer, UART, GPIO | Đạt. Core RV32IM 3 tầng, 8 macro `sram_2k_macro` (IMEM 16 KB, DMEM 16 KB), accelerator 4 × 4 qua APB, Timer, UART, GPIO | `rtl/`, `eva03_ppa.md` mục 1. Testcase `soc` (UART, GPIO, timer, ngắt) PASS ở mức cổng (`power_soc.md` mục 2, `gls_soc.md` mục 5.1) |
| GPDK 45 nm, tần số tối thiểu 50 MHz | Đạt, signoff 100 MHz (gấp 2 lần yêu cầu) | `sta_results.md` mục 5 và 6 |
| Thiết kế RTL và kiểm tra chức năng | Đạt. `isa-core` 472/472, `fw-soc` 131/131, `fw-soc-c` 2/2 | `btb_eval.md` mục 7, `power_soc.md` mục 6 |
| Bộ ràng buộc thiết kế | Đạt. `soc.sdc`, unconstrained chỉ còn chân `SE` của ICG và chân `RN` của flop hằng, đều vô hại | `syn/constraints/`, `sta_results.md` mục 1 và 5 |
| Tổng hợp, tối ưu mức cổng, báo cáo | Đạt. Genus 9 ns, setup +0,7 ps, 4068 flop, 136 ICG, 0 DRV, 0 latch, 0 scan flop | `sta_results.md` mục 4 và 5, `appendix/synth_soc_e60437a/` |
| Kiểm tra mức cổng: timing | Đạt. Tempus trước layout ở 10 ns, setup +0,978 ns. Hold −0,141 ns do clock lý tưởng, Innovus sửa sau CTS | `sta_results.md` mục 5, `appendix/sta_soc_p9/` |
| Kiểm tra mức cổng: trùng khớp (LEC-02) | Đạt có ghi chú. 3965 Equivalent, 1 Non-equivalent (`clk_cnt_reg[15]` của SPI, đã chứng minh luôn bằng 0), 112 Abort ở bộ nhân và chia do thiếu license Conformal_Ultra | `lec_soc.md` mục 4, `appendix/lec_soc/run5_seqeff/` |
| Kiểm tra mức cổng: chức năng (VER-07) | Đạt. GLS zero delay 71/71 PASS | `gls_soc.md` mục 5.1 |
| Thiết kế vật lý, báo cáo | Đạt. Layout `_p9`, 420 × 420,7 µm, 71 800 µm² cell chuẩn, mật độ 63,7%, skew 0,112 ns sau CTS và 0,131 ns trên layout cuối (góc slow) | `pnr_soc_status.md` mục 6, `appendix/pnr_soc_p9/` |
| Sign-off timing (STA-06) | Đạt. 4 view, 10 ns: setup +0,977, hold +0,020, recovery +7,434, removal +0,023 ns | `sta_results.md` mục 6, `appendix/sta_soc_p9_trim/` |
| Sign-off trùng khớp (LEC-03, LEC-05) | Đạt. Netlist tổng hợp so với netlist sau ECO và netlist layout cuối: 4078 Equivalent, 0 Non-equivalent, 0 Abort, `PASS` | `lec_soc.md` mục 4, `appendix/lec_soc/g2g/`, `appendix/lec_soc/g2g_lec05/` |
| Sign-off chức năng (GLS có SDF, VER-08, VER-09) | Đạt. 71/71 PASS ở góc max (slow, `av_setup`) và góc min (fast, `av_hold`), số chu kỳ bằng RTL, 0 vi phạm sau khi reset nhả | `gls_soc.md` mục 8.5 và 9.4, `appendix/gls_soc_sdf/`, `appendix/gls_soc_sdf_minmax/` |
| Sign-off luật thiết kế và kết nối (PD-08) | Đạt. DRC 0, antenna 0, connectivity không có vấn đề sau khi sửa lưới `VSS`. Không có LVS (mục 7) | `pnr_soc_status.md` mục 8, `appendix/pnr_soc_p9/trim/` |
| Sign-off lỗi điện (IR drop, LEC-06) | Đạt. Sụt áp VDD lớn nhất 0,693 mV (hoạt độ 0,1) và 1,69 mV (hoạt độ 0,5), ngưỡng 45 mV, 0 vi phạm | `ir_drop.md` mục 7, `appendix/ir_drop_trim/` |
| Đánh giá kết quả, so sánh thiết kế tương tự | Đạt. Bảng PPA, so với PicoRV32, Ibex, SERV, tài liệu này | `eva03_ppa.md`, `eva02_compare.md` |
| Thiết kế CLEAN, đạt chức năng và tần số | Đạt theo các dòng sign-off ở trên | Các dòng trên |
| Report có mọi bước, script, report, log ở phụ lục | Report và log từng bước đã ở `appendix/`. Report PDF đang biên tập, hạn nộp 20/12/2026 | `appendix/`, `spec/requirements.md` |

## 3. Điểm cộng

| Mục | Kết quả đo hoặc bằng chứng | Nguồn |
| --- | --- | --- |
| Tối ưu PPA (F_max, CPI, IPC, công suất theo testcase, EPI, area, GE, density) | Đủ các chỉ số, xem bảng "Đối chiếu với điểm cộng PPA của đề bài" | `eva03_ppa.md` mục 7 |
| Mở rộng lõi: RV32IM | CoreMark/MHz từ 1,260 (rv32i) lên 3,210 (rv32im) trên `soc_top`. riscv-tests rv32um PASS ở RTL và GLS | `bench_soc.md` (RTL chốt), `gls_soc.md` mục 5.1 |
| Mở rộng lõi: ngắt | Ngắt ngoài, timer, phần mềm, WFI ngủ (D-024, D-025, D-038). Bản accelerator irq nhận đúng 64 ngắt | `core_decisions.md`, `bench_soc.md` mục Speedup accelerator |
| Mở rộng lõi: dự đoán nhánh (BTB 8 entry) | CoreMark/MHz +7,7%, DMIPS/MHz +7,1% (rv32im, `soc_top`) | `btb_eval.md` mục 3 |
| Mở rộng lõi: bootloader UART | Nạp IMEM và DMEM, nhiều segment, CRC-32, ROM 143/256 word. `sim-boot` 7/7 PASS | `core_decisions.md` D-039, D-040 |
| Ngoại vi mở rộng: SPI, PWM, I2C | Genus: `spi_apb` 619,4 µm², `pwm_apb` 1 377,6 µm², `i2c_apb` 835,5 µm². Testcase `spi_pwm` và `i2c` PASS ở mức cổng, 0,6919 và 0,6161 mW sau layout | `sta_results.md` mục 3, `power_soc.md` mục 2 và 9 |
| DMA | `dma_apb` 2 318,8 µm². Testcase `dma` PASS ở mức cổng, 12 539 chu kỳ, 0,7541 mW sau layout | `sta_results.md` mục 3, `power_soc.md` mục 5 và 9 |
| Accelerator dùng ngắt | Nhân ma trận 16 × 16: bản irq nhanh hơn phần mềm 20,60 lần (rv32i) và 1,44 lần (rv32im). Lõi ngủ bằng WFI trong lúc chờ | `bench_soc.md` (RTL chốt) |

## 4. Các tối ưu đã làm và hiệu quả đo được

| Tối ưu | Trước | Sau | Mức cải thiện | Nguồn |
| --- | --- | --- | --- | --- |
| Clock gating, diện tích (Genus 9 ns) | CG=0: 66 337 µm² | CG=1: 60 188 µm² | −9,3% | `sta_results.md` mục 5 |
| Clock gating, công suất (Genus, activity mặc định) | 2,062 mW | 0,817 mW | −60,4% | `sta_results.md` mục 5 |
| BTB 8 entry, CoreMark rv32im trên `soc_top` | CPI 1,158, 2,755 CoreMark/MHz | CPI 1,076, 2,967 CoreMark/MHz | CPI −7,1% (tính), hiệu năng +7,7% | `btb_eval.md` mục 3 |
| BTB 8 entry, Dhrystone rv32im trên `soc_top` | CPI 1,286, 0,800 DMIPS/MHz | CPI 1,201, 0,857 DMIPS/MHz | CPI −6,6% (tính), hiệu năng +7,1% | `btb_eval.md` mục 3 |
| Chu kỳ tổng hợp 9 ns thay cho 10 ns (Tempus 10 ns, trước layout) | Netlist 10 ns: setup −0,009 ns | Netlist 9 ns: setup +0,978 ns, sau layout vẫn +0,977 ns | Có biên khoảng 1 ns, cell chuẩn chỉ tăng 0,95% | `sta_results.md` mục 4, 5 và 6 |
| Cỡ lõi (PD-07, 9 ns) | 412 × 413,8 µm: mật độ 67,1%, setup −0,062 ns | 420 × 420,7 µm: 63,7%, −0,043 ns. 430 × 429,2 µm: 59,5%, −0,039 ns | Setup chỉ tốt lên 23 ps từ 412 đến 430. Giữ 420 | `pnr_soc_status.md` mục 7 |
| Accelerator, nhân ma trận 16 × 16, rv32i | Phần mềm 505 265 chu kỳ | Poll 21 855 chu kỳ | 23,12 lần | `bench_soc.md` (RTL chốt) |
| Accelerator, nhân ma trận 16 × 16, rv32im | Phần mềm 35 218 chu kỳ | Poll 21 896 chu kỳ | 1,61 lần | `bench_soc.md` (RTL chốt) |

Ghi chú:
- Số BTB đo ngày 26/10 (GCC 13.2). Chi phí BTB khoảng 4 313 µm² (+15% core có RV32M, Nangate45, flow nhà) (`btb_eval.md` mục 4).
- CPI 1,076 của BTB đo bằng GCC 13.2 trước khi chốt RTL. Số chính thức 1,094 đo ngày 12/11 bằng GCC 16.1 trên RTL chốt (`bench_soc.md`). Hai lần đo khác trình biên dịch nên không so trực tiếp.
- Trong GPDK45 chưa đo riêng diện tích BTB. Ước lượng phần flop khoảng 480 flop × 5,472 đến 6,156 µm² ≈ 2 600 đến 3 000 µm² (tính).
- Phép so clock gating dùng activity mặc định và chưa có cây clock thật. Sau CTS clock gating còn tiết kiệm thêm phần cây clock phía sau ICG (`sta_results.md` mục 5).
- Với rv32im, khoảng 95% thời gian của mỗi khối accelerator là chuyển dữ liệu qua APB, nên speedup thấp (`bench_soc.md` mục Speedup accelerator).

## 5. So sánh với thiết kế tương tự

Rút gọn từ `eva02_compare.md` mục 2 và 3. Chỉ PicoRV32 chạy cùng flow Genus và cùng thư viện. Số Ibex và SERV là số công bố từ flow khác, nên chỉ so gần đúng.

| Lõi | ISA | kGE | CoreMark/MHz | DMIPS/MHz | CoreMark/MHz / kGE | Nguồn số |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| **`rv32_core`** | RV32IM | **29,46** | **3,22** | **0,93** | **0,109** | Genus cùng flow, đo trên `tb_core` |
| PicoRV32 IM | RV32IM | 28,78 | - | 0,516 | - | Genus cùng flow, DMIPS từ README |
| Ibex small | RV32IMC | 26,60 | 2,47 | - | 0,093 | Số công bố |
| Ibex maxperf | RV32IMC | 32,48 | 3,13 | - | 0,096 | Số công bố |
| SERV | RV32I | 2,1 | - | - | - | Số công bố, CPI khoảng 32 đến 64 |

Nhận xét:
- So với PicoRV32 IM (so trực tiếp được): diện tích lớn hơn 2,4% nhưng DMIPS/MHz cao hơn khoảng 1,7 lần, nhờ CPI khoảng 1,1 so với khoảng 4.
- So với Ibex: CoreMark/MHz ngang Ibex maxperf (3,22 so với 3,13), diện tích nằm giữa small và maxperf. Hiệu năng trên diện tích nhỉnh hơn một chút (0,109 so với 0,093 đến 0,104).
- SERV nhỏ hơn khoảng 14 lần nhưng chậm hơn khoảng 30 đến 60 lần ở cùng tần số. SERV hợp với điều khiển đơn giản, không hợp tính toán.
- Ibex dùng register file latch và có lệnh C, nên một phần chênh diện tích đến từ cách làm register file. Chi tiết và giới hạn ở `eva02_compare.md` mục 4 và 5.

## 6. Đánh giá chung

Điểm mạnh:
- Hiệu năng trên mỗi MHz cao cho lõi 3 tầng: CPI 1,094, 3,210 CoreMark/MHz, ngang Ibex maxperf và gấp khoảng 1,7 lần PicoRV32 IM về DMIPS/MHz (mục 5).
- Sign-off sạch ở mọi mục đề bài yêu cầu: 0 vi phạm timing ở 4 view, LEC-05 0 Non-equivalent, GLS có SDF 71/71 ở hai góc, DRC 0, antenna 0 (mục 2).
- Biên điện tốt: IR drop lớn nhất 1,69 mV, khoảng 4% ngưỡng 45 mV (tính từ `ir_drop.md` mục 7).
- Clock gating gate được 95,4% flop, giảm 9,3% diện tích và 60,4% công suất Genus (`sta_results.md` mục 5).
- Làm đủ các điểm cộng nhóm chọn: RV32IM, ngắt, BTB, SPI, PWM, I2C, DMA, accelerator dùng ngắt (mục 3).

Điểm yếu:
- F_max sau layout chỉ khoảng 110,8 MHz, dư khoảng 10% so với signoff 100 MHz. Đường găng là IMEM → so sánh nhánh → `if_pc_q` và IMEM → bộ nhân (`sta_results.md` mục 4 và 6). Số khoảng 200 MHz sau tổng hợp đo trên một netlist khác (tổng hợp riêng ở 5 ns, clock lý tưởng, chưa có dây, macro `.lib` typical), nên không dùng hai số này để tính mức suy giảm do layout (`eva03_ppa.md` mục 3).
- Lõi tốn diện tích ở flop: 2163 flop chiếm 44% diện tích lõi, riêng register file khoảng 6 kGE (`eva02_compare.md` mục 4). Phần lớn diện tích register file nằm ở 2 bộ mux đọc 32:1, không chỉ ở flop.
- Accelerator chỉ nhanh hơn phần mềm rv32im 1,61 lần, vì khoảng 95% thời gian là chuyển dữ liệu qua APB (`bench_soc.md` mục Speedup accelerator).
- Công suất sau layout bằng 1,90 đến 2,02 lần trước layout. Phần tăng chủ yếu ở logic tổ hợp (56 đến 75%), cây clock chiếm 24 đến 41%. Cây clock tốn khoảng 0,17 mW, 18 đến 28% tổng (`power_soc.md` mục 9.1). Skew cây clock góc slow 0,131 ns, vượt mục tiêu 0,080 ns (`pnr_soc_status.md` mục 8).
- Macro không có chân ghi byte, nên mỗi SB/SH tốn thêm 1 chu kỳ. Dhrystone chậm 4,9% vì lý do này (`bench_soc.md` mục Giải thích chênh lệch).

## 7. Giới hạn của phép đo

- **Công suất có góc slow 0,580 đến 0,965 mW và góc fast 0,879 đến 1,452 mW** (RC typical, `eva03_ppa.md`). Chưa có góc typical vì PDK không có thư viện typical cho cell chuẩn (`power_soc.md` mục 1 và 9).
- **PWR-02 chạy trên `route_eco`, không phải `route_trim`.** SPEF của layout cuối chỉ đổi tổng điện dung ở 2 trên 27 329 net (nhiều nhất 0,049%), nên nhóm không chạy lại (`pnr_soc_status.md` mục 8).
- **Công suất SRAM có thể thấp hơn thực tế.** Phần động của cả 8 macro chỉ 0,017 đến 0,021 mW, khoảng 0,2 pJ mỗi chu kỳ, dù IMEM được đọc gần như mỗi chu kỳ. Số này lấy từ `sram_2k_macro.lib` của môn, nhóm không kiểm được (`power_soc.md` mục 9.1).
- **Phân tách công suất theo nhóm giữa hai tool chỉ là ước lượng.** Genus chia `register`, `logic`, `clock`, `bbox`, Innovus chia `Sequential`, `Combinational`, `Clock`, `Macro`. Hai cách chia không trùng hẳn (`power_soc.md` mục 9.1).
- **IR drop chỉ phân tích VDD tĩnh.** VSS chỉ kiểm connectivity, sạch sau PD-08 (`ir_drop.md` mục 7). Pad là giả định (12 điểm trên vòng ring) (`ir_drop.md` mục 8).
- **Không làm EM**, vì đề bài yêu cầu sign-off "lỗi điện" và không ghi EM (`ir_drop.md` mục 7). Voltus có mục `CURRENT DENSITY ANALYSIS` nhưng không tính J/Jmax (`ir_drop.md` mục 8).
- **Không có LVS**, vì macro `sram_2k_macro` không có GDS và CDL. Thầy xác nhận không cần ngày 22/10 (`macro_notes.md` mục 3.7, `pnr_soc_status.md` mục 8).
- **Công suất động theo toggle rate:** Innovus trên `route_trim` cho 1,182 mW ở hoạt độ 0,1 và 2,567 mW ở hoạt độ 0,5 (`ir_drop.md` mục 7). Số cũ 1,975 mW ở hoạt độ 0,1 là của `route_eco`, không khớp dòng tải nên không dùng. Ngoài ra có 8 testcase theo SAIF thật trước và sau layout (`power_soc.md` mục 5 và 9). Số theo testcase phản ánh hoạt động thật của SoC, còn hoạt độ 0,5 chỉ là kịch bản xấu.
- GLS có SDF không kiểm recovery/removal của chân reset và không có timing ở macro. Hai phần này do STA kiểm (`gls_soc.md` mục 9.4).
- CoreMark chỉ chạy 3 vòng nên chưa phải điểm CoreMark chính thức (`bench_soc.md` mục Giới hạn đo).

## 8. Hướng phát triển

Lợi ích dưới đây là dự kiến, chưa đo.

| Hướng | Lợi ích dự kiến |
| --- | --- |
| Register file dùng latch hoặc SRAM | Tính từ `slow_vdd1v0_basiccells.lib` (đọc trên server 26/11): DFFRHQX1 (flop có reset, đang dùng) 6,156 µm², DFFHQX1 (không reset) 5,472 µm², TLATX1 (latch) 5,472 µm². Latch không nhỏ hơn flop không reset. Đổi 992 bit sang latch hoặc bỏ reset chỉ tiết kiệm khoảng 0,684 × 992 ≈ 679 µm², khoảng 0,66 kGE (2,2% lõi 30 226 µm², tính). Latch còn cần thêm thanh ghi đệm dữ liệu ghi và ICG nên lợi ít hơn. Cách rẻ nhất là bỏ reset của register file. Muốn giảm nhiều hơn cần register file SRAM 2 cổng đọc, PDK của môn không có. |
| Lệnh nén C | Dự kiến code nhỏ hơn, để trống thêm IMEM (CoreMark rv32i chỉ còn khoảng 1,1 KB, `bench_soc.md`). CoreMark/MHz dự kiến thay đổi ít. |
| Cache hoặc prefetch cho bộ nhớ có wait state | Dự kiến giữ CPI gần mức hiện tại (khoảng 1,1) khi dùng bộ nhớ chậm hơn SRAM trên chip. |
| Tối ưu cây clock và logic tổ hợp sau layout | Cây clock tốn khoảng 0,17 mW (18 đến 28% tổng) và logic tổ hợp chiếm phần lớn mức tăng sau layout (`power_soc.md` mục 9.1). Dự kiến giảm được phần tăng 1,90 đến 2,02 lần, đồng thời đưa skew về gần mục tiêu 0,080 ns. |
| Thêm góc fast và typical cho công suất | Đã có góc fast. Còn thiếu typical vì PDK không có .lib typical. |
| EM và phân tích VSS | Dự kiến hoàn thiện sign-off lỗi điện cho cả hai lưới nguồn. |
| Multi-Vt hoặc power gating | Dự kiến giảm leakage và công suất khi chờ. Leakage hiện chỉ khoảng 2 đến 3% tổng ở 100 MHz (`eva03_ppa.md` mục 1), nên lợi ích chủ yếu ở chế độ chờ. Khoảng 91% leakage là của macro SRAM (`power_soc.md` mục 9.1), nên multi-Vt cho cell chuẩn giúp ít, power gating SRAM giúp nhiều hơn. |
