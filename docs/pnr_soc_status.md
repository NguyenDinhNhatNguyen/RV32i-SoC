# Theo dõi PnR `soc_top`

Danh sách việc PnR sau buổi trường 29–30/10, theo bản tổng hợp của Phát ngày 30/10. Cập nhật 12/11. Floorplan và số liệu chi tiết ở `docs/pd02_floorplan.md`, cách chạy ở `docs/flow_notes.md`.

## 1. Tình trạng từng mục

| # | Vấn đề | Trạng thái | Đã làm hoặc còn lại |
| --- | --- | --- | --- |
| 1 | GDS, SPEF và netlist sau PnR của `soc_top` bị đưa lên repo công khai (commit 29/10) | Xong 31/10 | Đã xoá khỏi repo và khỏi lịch sử Git. `.gitignore` chặn các file này ở mọi thư mục kể cả `appendix/`. Xem mục 2 |
| 2 | Netlist `soc_top` đã đổi sau lần PnR 29/10 (bản giữ flop cho LEC, sắp có bản buffer mạng reset) | Xong 12/11 | Phát chạy lại `make synth-soc` ngày 31/10 và 12/11 (commit `eced27a`, có DMA, SPI, PWM, I2C): giữ flop, mạng reset có buffer, 0 `CLKBUFX2` (`docs/sta_results.md` mục 1). `make pnr-soc` đã chạy trên netlist 12/11, kết quả ở mục 4 |
| 3 | `run_all.tcl` chưa gọi `soc_floorplan.tcl`, macro do Innovus tự đặt | Xong 31/10 | `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl` |
| 4 | 1220 cell `CLKBUFX2` trong netlist PnR | Xong 31/10 | `CLKBUFX2` bị cấm ngay sau `init_design`, trước mọi bước tối ưu. 11 cell còn lại từ Genus đã hết từ 31/10, vì `CLKBUFX2` có trong `DONT_USE_CELLS` của `config.tcl` |
| 5 | `run_all.tcl` bị đổi cứng sang `soc_top`, `make pnr-accel` hỏng | Xong 31/10 | Chọn khối bằng biến `TOP`. `make pnr-accel` dùng `TOP=accel_wrapper` như cũ |
| 6 | Hold trước CTS: 1081 đường vi phạm, xấu nhất −0,147 ns ở chân CEN của macro IMEM. Removal trước layout chỉ dư 6 ps (Tempus 31/10) | Một phần 12/11 | `run_all.tcl` sửa hold sau CTS và sau route, với biên `holdTargetSlack 0.020` (04/11). Chạy 12/11: hold +0,020 ns (sau CTS) và +0,019 ns (sau route), removal +0,029 ns (Tempus). Riêng `slack_summary.txt` ghi `n/a` cho hold và removal, vì Innovus chỉ báo hai loại này ở chế độ hold (lỗi TCLCMD-1045). Đã sửa `slack_reports` trong `run_all.tcl` (chuyển sang `setAnalysisMode -checkType hold` khi đo hold và removal). Kiểm trên `DBS/route.enc` ngày 12/11: setup −0,027, hold +0,019, recovery +17,869, removal +0,026 ns. Lần `make pnr-soc` tới sẽ ghi các số này vào `slack_summary.txt` |
| 7 | Chưa có report timing, DRC của `soc_top` trong repo. Ảnh layout có 5 dấu X trắng | Xong 12/11 | Report đã ở `appendix/pnr_soc/` (commit `7691865`). Ảnh 12/11 có 12 dấu X thẳng hàng ở mép trên vành macro IMEM. Đó là 12 đoạn dây VDD Metal7 dài 0 (xem mục 4), không phải lỗi DRC |
| 8 | Diện tích logic thật 53 408 µm², lõi tính theo số cũ | Xong 31/10 | Lõi đúng là 394 × 395 µm ở mật độ 70%, nới thành 397 × 400 µm ngày 07/11 khi có SPI, PWM, rồi 402 × 404 µm cùng ngày khi bật DMA, 405 × 405 µm ngày 10/11 khi ghép I2C (4 chân mới). Lõi 524 × 523 µm của lần 29/10 tính sai (nhập tổng có cả macro vào `--std-area`) |
| 9 | `appendix/macro_check/sram_2k_macro_20261030.txt` còn trên server | Xong 12/11 | Đã commit trong `7691865`. Hướng macro không còn phụ thuộc file này: `soc_floorplan.tcl` tự đọc cạnh có chân tín hiệu từ LEF (31/10). Log Innovus in lớp chân VDD/VSS để kiểm lớp ring |
| 10 | Sheet trùng ID VER-09 | Xong | Đã đổi trước ngày 31/10, Sheet hiện chỉ còn một VER-09 |
| 11 | Ảnh layout ở `docs/images/`, hình khác ở `docs/figures/` | Xong 31/10 | Chuyển sang `docs/figures/soc_top_layout.png` |

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

## 3. Việc cho buổi lên trường tới

1. Phát: `make synth-soc` (bản giữ flop, có buffer mạng reset, cấm `CLKBUFX2`). Chạy lại 12/11 trên commit `eced27a`, có DMA, SPI, PWM, I2C: std cell 58 843 µm² (nhỏ hơn 59 400 µm² dùng để tính lõi), setup +0,529 ns. Netlist ở `syn/out_soc/` trên server.
2. Nguyên: `make pnr-soc`. Cuối lệnh in `pnr/out_soc/reports/pd_checks.rpt`, kiểm:
   - `BUFX2 instances: 0` và `CLKBUFX2 instances: 0`.
   - 8 dòng `Macro ...`: 4 IMEM ở hàng trên, 4 DMEM ở hàng dưới, đúng hướng in trong log (`grep PD-02 pnr/run_soc/innovus.log`).
   - Mật độ cell chuẩn khoảng 70%.
   - `cat pnr/out_soc/reports/slack_summary.txt`: setup, hold, recovery, removal sau CTS và sau route đều ≥ 0. Removal là chỗ dễ âm nhất.
   - DRC, connectivity, antenna 0 lỗi.
3. `make save-pnr-soc` và `make save-pnr-accel` (report PD-01 lần 29/10), commit `appendix/pnr_soc`, `appendix/pnr_accel`, `appendix/macro_check/`. Không commit gì trong `pnr/out_soc/`.
4. Gửi Phát đường dẫn cho Tempus sau layout (STA-05). Server dùng chung một tài khoản nên Phát đọc thẳng, không cần copy:
   - Netlist sau route: `~/RV32i-SoC/pnr/out_soc/soc_top_pnr.v`
   - SPEF: `~/RV32i-SoC/pnr/out_soc/soc_top.spef` (corner `rc_typ`)
   - SDF cho GLS của Hiếu: `~/RV32i-SoC/pnr/out_soc/soc_top.sdf`

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
| Connectivity | 12 cảnh báo IMPVFC-94: dây VDD Metal7 dài 0 ở đầu dải VDD của vành macro, mép trên. Lần 29/10 không có. Chờ Phúc chạy IR drop, sửa ở PD-08 nếu còn sau PD-05 |
| Fanout | 190 net vượt `set_max_fanout 32`: 27 net clock và 163 net khác (khoảng 61 net cây reset, 102 net dữ liệu). Giữ ràng buộc này vì Genus cần nó để buffer mạng reset (`docs/sta_results.md` mục 1). Max_cap 0, max_tran 3 net (xấu nhất −0,069 ns, ví dụ `n_5552`) cần sửa |
| Công suất | 1,261 mW, activity mặc định 0,2, chưa phải theo testcase |
| GDS | Có ghi file. Cảnh báo IMPOGDS-1176: 26 cell rỗng vì map thiếu luật, chưa rõ cell nào |

Chạy Tempus sau route phải dùng đường dẫn tuyệt đối, vì script chạy trong `sta/run_soc`:

```sh
make sta-soc SPEF=$PWD/pnr/out_soc/soc_top.spef NETLIST=$PWD/pnr/out_soc/soc_top_pnr.v SDC=$PWD/syn/out_soc/soc_top_synth.sdc
```
