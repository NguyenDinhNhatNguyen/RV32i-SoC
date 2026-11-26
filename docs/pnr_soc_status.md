# Theo dõi PnR `soc_top`

Danh sách việc PnR sau buổi trường 29–30/10, theo bản tổng hợp của Phát ngày 30/10. Cập nhật 26/11. Floorplan và số liệu chi tiết ở `docs/pd02_floorplan.md`, cách chạy ở `docs/flow_notes.md`.

## 1. Tình trạng từng mục

| # | Vấn đề | Trạng thái | Đã làm hoặc còn lại |
| --- | --- | --- | --- |
| 1 | GDS, SPEF và netlist sau PnR của `soc_top` bị đưa lên repo công khai (commit 29/10) | Xong 31/10 | Đã xoá khỏi repo và khỏi lịch sử Git. `.gitignore` chặn các file này ở mọi thư mục kể cả `appendix/`. Xem mục 2 |
| 2 | Netlist `soc_top` đã đổi sau lần PnR 29/10 (bản giữ flop cho LEC, sắp có bản buffer mạng reset) | Xong 12/11 | Phát chạy lại `make synth-soc` ngày 31/10 và 12/11 (commit `eced27a`, có DMA, SPI, PWM, I2C): giữ flop, mạng reset có buffer, 0 `CLKBUFX2` (`docs/sta_results.md` mục 1). `make pnr-soc` đã chạy trên netlist 12/11, kết quả ở mục 4 |
| 3 | `run_all.tcl` chưa gọi `soc_floorplan.tcl`, macro do Innovus tự đặt | Xong 31/10 | `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl` |
| 4 | 1220 cell `CLKBUFX2` trong netlist PnR | Xong 31/10 | `CLKBUFX2` bị cấm ngay sau `init_design`, trước mọi bước tối ưu. 11 cell còn lại từ Genus đã hết từ 31/10, vì `CLKBUFX2` có trong `DONT_USE_CELLS` của `config.tcl` |
| 5 | `run_all.tcl` bị đổi cứng sang `soc_top`, `make pnr-accel` hỏng | Xong 31/10 | Chọn khối bằng biến `TOP`. `make pnr-accel` dùng `TOP=accel_wrapper` như cũ |
| 6 | Hold trước CTS: 1081 đường vi phạm, xấu nhất −0,147 ns ở chân CEN của macro IMEM. Removal trước layout chỉ dư 6 ps (Tempus 31/10) | Xong 13/11 | `run_all.tcl` sửa hold sau CTS và sau route, với biên `holdTargetSlack 0.020` (04/11). Chạy 12/11: hold +0,020 ns (sau CTS) và +0,019 ns (sau route), removal +0,029 ns (Tempus). Riêng `slack_summary.txt` ghi `n/a` cho hold và removal, vì Innovus chỉ báo hai loại này ở chế độ hold (lỗi TCLCMD-1045). Đã sửa `slack_reports` trong `run_all.tcl` (chuyển sang `setAnalysisMode -checkType hold` khi đo hold và removal). Kiểm trên `DBS/route.enc` ngày 12/11: setup −0,027, hold +0,019, recovery +17,869, removal +0,026 ns. Chạy lại `make pnr-soc` ngày 13/11 (commit `7715481`): `slack_summary.txt` ghi đủ hold +0,020 và removal +0,023 ns sau CTS, hold +0,019 và removal +0,028 ns sau route |
| 7 | Chưa có report timing, DRC của `soc_top` trong repo. Ảnh layout có 5 dấu X trắng | Xong 12/11 | Report đã ở `appendix/pnr_soc/` (commit `7691865`). Ảnh 12/11 có 12 dấu X thẳng hàng ở mép trên vành macro IMEM. Đó là 12 đoạn dây VDD Metal7 dài 0 (xem mục 4), không phải lỗi DRC |
| 8 | Diện tích logic thật 53 408 µm², lõi tính theo số cũ | Xong 31/10 | Lõi đúng là 394 × 395 µm ở mật độ 70%, nới thành 397 × 400 µm ngày 07/11 khi có SPI, PWM, rồi 402 × 404 µm cùng ngày khi bật DMA, 405 × 405 µm ngày 10/11 khi ghép I2C (4 chân mới). Lõi 524 × 523 µm của lần 29/10 tính sai (nhập tổng có cả macro vào `--std-area`) |
| 9 | `appendix/macro_check/sram_2k_macro_20261030.txt` còn trên server | Xong 12/11 | Đã commit trong `7691865`. Hướng macro không còn phụ thuộc file này: `soc_floorplan.tcl` tự đọc cạnh có chân tín hiệu từ LEF (31/10). Log Innovus in lớp chân VDD/VSS để kiểm lớp ring |

## 2. File bản quyền trong repo (31/10)

Nhóm thống nhất giữ repo công khai, sửa `.gitignore` và xoá file dựng từ PDK:

- Xoá `pnr/out_soc/soc_top.gds`, `soc_top.spef`, `soc_top_pnr.v` khỏi repo, rồi xoá khỏi lịch sử bằng `git filter-repo` (chỉ viết lại các commit từ 29/10 chiều trở đi) và force push `main`, `feat/nhan-core-signoff`.
- Commit trước 16:04 ngày 29/10 giữ nguyên mã. 19 commit sau đó đổi mã nhưng giữ nguyên nội dung, tác giả, ngày và message. Commit chỉ chứa 3 file kia (`576960e`) không còn.
- Repo trên GitHub từ khoảng 16 MB còn 2 MB.

Ai còn bản clone cũ (máy nhà hoặc server) chạy một lần:

```sh
git fetch origin
git reset --hard origin/main
```

Không push từ bản clone cũ chưa reset, vì như vậy GDS sẽ quay lại GitHub.

`.gitignore` giờ chặn ở mọi thư mục: thư viện (`.lib`, `.lef`, `.gds`, `.cdl`...), SPEF, SDF, `*_netlist.v`, `*_pnr.v`, `*_pnr_pg.v`, database Innovus. Mấy dòng này nằm cuối file nên `!appendix/**` không mở lại được. Không dùng `git add -f` cho output của flow.

## 3. Việc cho buổi lên trường 12/11 (đã hoàn thành 13/11)

Synth, PnR, lưu report và đường dẫn cho Tempus đều đã làm. Kết quả ở mục 4 và 5. Đường dẫn Tempus sau layout ở `docs/flow_notes.md` (dòng STA-05).

## 4. Kết quả chạy 12/11 (PD-04)

Netlist `eced27a` (DMA, SPI, PWM, I2C), clock 20 ns, Innovus 21.19, Tempus 23.14.

| Mục | Kết quả |
| --- | --- |
| Macro | 8 macro đúng chỗ: DMEM hàng dưới (R0), IMEM hàng trên (MX) |
| Cell chuẩn | 68 227 µm², mật độ 68,1% ngoài macro. Tăng khoảng 16% so với 58 843 µm² sau tổng hợp (CTS và sửa hold) |
| Hold | +0,020 ns sau CTS, +0,019 ns sau route, 0 đường vi phạm |
| Setup | Innovus −0,024 ns (1 đường), Tempus +0,007 ns. Genus dừng tối ưu ở 20 ns nên không có biên, xem `docs/sta_results.md` mục 1 |
| Recovery, removal | Recovery +17,92 ns, removal +0,029 ns (Tempus) |
| CTS | 0 vi phạm transition, skew 0,115 ns (mục tiêu 0,080 ns) |
| DRC, antenna, PDN | Sạch |
| Connectivity | 12 cảnh báo IMPVFC-94: dây VDD Metal7 dài 0 ở đầu dải VDD của vành macro, mép trên. Lần 29/10 không có. Sửa ở PD-08 nếu còn (bản `_p9` ở mục 6). IR drop VDD chạy 20/11, sụt khoảng 1 đến 2 mV (`docs/ir_drop.md`) |
| Fanout | 190 net vượt `set_max_fanout 32`: 27 net clock và 163 net khác (khoảng 61 net cây reset, 102 net dữ liệu). Giữ ràng buộc này vì Genus cần nó để buffer mạng reset (`docs/sta_results.md` mục 1). Max_cap 0, max_tran 3 net (xấu nhất −0,069 ns, ví dụ `n_5552`) cần sửa |
| Công suất | 1,261 mW, activity mặc định 0,2, chưa phải theo testcase |
| GDS | Có ghi file. Cảnh báo IMPOGDS-1176: 26 cell rỗng vì map thiếu luật, chưa rõ cell nào |

Chạy Tempus sau route phải dùng đường dẫn tuyệt đối, vì script chạy trong `sta/run_soc`:

```sh
make sta-soc SPEF=$PWD/pnr/out_soc/soc_top.spef NETLIST=$PWD/pnr/out_soc/soc_top_pnr.v SDC=$PWD/syn/out_soc/soc_top_synth.sdc
```

## 5. Chạy thử ba cỡ lõi (PD-07, 13/11)

Cùng netlist `eced27a`, clock 20 ns. Mỗi cỡ chạy bằng `make pnr-soc TAG=<tag> CORE_W=<w> CORE_H=<h>`, kết quả ở `pnr/out_soc<tag>/`, report ở `appendix/pnr_soc<tag>/`.

| Lõi (µm) | Thư mục | Cell chuẩn (µm²) | Mật độ ngoài macro | Setup sau route | Hold sau route | Removal sau route | DRC |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 405 × 405,3 | `pnr_soc` | 68 227 | 68,1% | −0,024 | +0,019 | +0,028 | 0 |
| 412 × 413,8 | `pnr_soc_u75` | 68 116 | 64,0% | +0,016 | +0,019 | +0,034 | 1, ECO sửa về 0 |
| 420 × 420,7 | `pnr_soc_u70` | 67 988 | 60,3% | +0,165 | +0,013 | +0,032 | 1, ECO sửa về 0 |
| 430 × 429,2 | `pnr_soc_u65` | 67 978 | 56,4% | +0,190 | +0,017 | +0,029 | 0 |

Số timing là của Innovus, tính bằng ns. Lõi lớn hơn thì setup tăng, nhảy mạnh nhất ở 420 µm. Hai lỗi DRC cùng loại Metal1 `ParallelRunLength`, cách sửa ở `docs/flow_notes.md` mục "DRC còn lại sau route". Cỡ lõi chính thức chốt cùng chu kỳ ở STA-04, vì setup sau route phụ thuộc cả hai. Nếu bản chính thức dùng `TAG`, lệnh Tempus sau route đổi `pnr/out_soc` thành `pnr/out_soc<tag>`.

Bốn dòng ở bảng trên là của netlist cũ `eced27a` ở 20 ns, giữ lại để đối chiếu.

## 6. Layout chính thức `_p9` (18/11)

Netlist chính thức STA-04 (RTL `e60437a`, Genus 9 ns, `docs/sta_results.md` mục 5), `make pnr-soc TAG=_p9 CORE_W=420.0 CORE_H=420.7`, SDC 9 ns do Genus ghi. Nguyên chạy PnR, Phát làm ECO. Report ở `appendix/pnr_soc_p9/` (bản của Nguyên) và `appendix/pnr_soc_p9/eco/` (sau ECO).

| Mục | Kết quả |
| --- | --- |
| Lõi, cell chuẩn | 420 × 420,7 µm, 71 800 µm², mật độ 63,7% ngoài macro. 0 `BUFX2`, 0 `CLKBUFX2`, 8 macro |
| CTS | Skew 0,112 ns (mục tiêu 0,080 ns) |
| Timing Innovus trước ECO | Setup sau route -0,043 ns ở 9 ns, hold +0,020, recovery +6,355, removal +0,025 |
| DRC | 5 lỗi sau route, `fix_drc_boxes` sửa còn 1 (Metal1 `ParallelRunLength` giữa `FE_OFN1608_inc_u_core_u_csr_add_258_50_n_29` và `n_9957`), ECO sửa còn 0 |
| max_tran | 1 net (2 điểm, xấu nhất -0,025 ns, ví dụ `n_5414`) trước ECO, 0 sau ECO |
| Sau ECO (Innovus, 9 ns) | Setup -0,047, hold +0,020, max_cap 0, max_tran 0, antenna sạch |
| Connectivity | 19 thông báo, có từ trước ECO (bản của Nguyên và bản sau ECO giống nhau). 2 chỗ hở `VSS` (IMPVFC-200) ở góc vành nguồn, (8,5, 8,5) và (21,6, 327,5). 17 đoạn dây `VSS` Metal7 dài 0 (IMPVFC-94) ở mép vành macro, y = 328,26 và 418,26, cùng loại với 12 đoạn `VDD` của 12/11. Sửa ở PD-08 |
| Fanout | 134 net vượt `set_max_fanout 32`, như các lần trước |
| Công suất | 3,235 mW (Innovus, activity mặc định, 9 ns) |
| Signoff Tempus 10 ns | Setup +0,977, hold +0,020, recovery +7,434, removal +0,023 (`docs/sta_results.md` mục 6), chốt 100 MHz |

ECO (18/11, script `eco_p9.tcl` và `eco_out_p9.tcl` ở `appendix/pnr_soc_p9/eco/scripts/`):

1. Khôi phục `DBS/route_drcfix.enc`, gỡ filler, `optDesign -postRoute -drv` cho max_tran.
2. `editDelete -net n_9957` rồi `ecoRoute`. Innovus 21.19 không có `deleteRoute`, gõ lệnh này thì Innovus đoán thành `deleteRouteBlk` và báo lỗi.
3. Chèn lại filler, lưu `DBS/route_eco.enc`, kiểm DRC, connectivity, antenna, `timeDesign` setup và hold.
4. Xuất lại netlist, netlist PG, SPEF, SDF, GDS vào `pnr/out_soc_p9/` bằng đúng lệnh của `run_all.tcl`. Bản gốc của Nguyên chuyển vào `pnr/out_soc_p9/pre_eco/`.

LEC-03 (Phúc) và GLS có SDF (Hiếu) dùng file trong `pnr/out_soc_p9/`, không dùng `pre_eco/`.

## 7. PD-07: ba cỡ lõi trên netlist chính thức (26/11)

Cùng netlist STA-04, clock 9 ns. Số lấy từ flow tự chạy, trước mọi ECO tay. Report ở `appendix/pnr_soc_p9_412/`, `appendix/pnr_soc_p9/`, `appendix/pnr_soc_p9_430/`.

| Mục | `_p9_412` | `_p9` | `_p9_430` |
| --- | --- | --- | --- |
| Lõi (µm) | 412 × 413,8 | 420 × 420,7 | 430 × 429,2 |
| Diện tích lõi (µm²) | 170 494 (-3,5%) | 176 677 | 184 560 (+4,5%) |
| Cell chuẩn (µm²) | 71 441 | 71 800 | 71 714 |
| Mật độ ngoài macro | 67,1% | 63,7% | 59,5% |
| Setup sau route (ns) | -0,062 | -0,043 | -0,039 |
| Hold (ns) | +0,020 | +0,020 | +0,019 |
| Recovery (ns) | +6,891 | +6,355 | +6,712 |
| Removal (ns) | +0,023 | +0,025 | +0,085 |
| DRC trước và sau tự sửa | 2, còn 0 | 5, còn 1 | 7, còn 0 |
| Connectivity | Sạch | 2 chỗ hở, 17 dây thừa | Sạch |
| Antenna | Sạch | Sạch sau ECO | Sạch |

Mật độ giảm khi lõi lớn hơn, còn setup chỉ tốt lên 23 ps từ 412 đến 430. Nhóm giữ `_p9` làm bản chính thức vì bản này đã có ECO, signoff Tempus 100 MHz, LEC, GLS và công suất. Cỡ 420 được chọn theo bản thử 13/11 trên netlist cũ (mục 5). Trên netlist mới, hai cỡ còn lại cho DRC và connectivity sạch ngay từ flow.

## 8. PD-08: kiểm cuối và xuất GDS (26/11)

Làm trên `DBS/route_eco.enc` của `_p9`, bản cuối là `DBS/route_trim.enc`. `route_eco.enc` giữ nguyên. Hai bước: xoá đoạn nổi (`route_vssfix.enc`, report ở `appendix/pnr_soc_p9/vssfix/`), rồi cắt đầu thừa (report ở `appendix/pnr_soc_p9/trim/`).

| Mục | Kết quả |
| --- | --- |
| Chỗ hở `VSS` | Một đoạn stripe Metal7 nổi ở (21,625, 327,51) - (23,125, 329,01). Xoá bằng `editDelete`, sau đó không còn chỗ hở |
| Dây thừa `VSS` | Sau khi xoá đoạn nổi còn 15 IMPVFC-94 trên Metal7. `editTrim -nets VSS -layers Metal7` còn 1 trên Metal8, `editTrim -nets VSS -layers Metal8` hết |
| Kiểm cuối | Connectivity không có vấn đề, DRC 0, antenna 0 |
| Skew cây clock | Góc slow 0,131 ns (mục tiêu 0,080 ns, không đạt), góc fast 0,050 ns. Sau CTS là 0,112 ns. Report `appendix/pnr_soc_p9/trim/skew_final.rpt` |
| GDS | `pnr/out_soc_p9/soc_top_final.gds`, Metal1-Metal9, đã ghép `gsclib045.gds`. Chỉ thiếu `sram_2k_macro` (macro không cần GDS, thầy xác nhận 22/10) |

Các file GDS xuất trước 26/11 thiếu Metal7 trở lên vì dùng `streamOut.map` trong `PDK_DIR`, không dùng nữa. `config.tcl` đã trỏ sang map của PDK GPDK045 v6.0 (commit `09c7b46`).

Các lệnh sửa chỉ chạy trên net `VSS` (ghi lại ở `pnr/scripts/pd08_vss_fix.tcl`). Netlist xuất từ `route_trim.enc` giống bản sau ECO, chỉ khác header. Dây nguồn trong GDS từ 935 còn 933. STA đã chạy lại trên layout cuối (`docs/sta_results.md` mục 6). Nhóm không chạy lại SDF, LEC, GLS và công suất. IR drop (LEC-06) cần chạy trên `route_trim.enc`.

Skew của layout cuối vượt mục tiêu CTS 0,051 ns. Setup +0,977 ns và hold +0,020 ns ở Tempus 10 ns vẫn đạt (đo lại trên layout cuối), nên nhóm giữ nguyên cây clock.

Hình layout cuối (chụp 26/11 từ `route_trim.enc`):

| Hình | Nội dung |
| --- | --- |
| `figures/soc_top_layout.png` | Toàn chip |
| `figures/soc_top_floorplan.png` | Floorplan: 8 SRAM macro, vùng cell và lưới nguồn |
| `figures/soc_top_zoom.png` | Phóng to: cell chuẩn, dây tín hiệu, stripe `VDD`/`VSS` |
| `figures/soc_top_cts.png` | Cây clock, góc `dc_slow`, skew 0,131 ns |
