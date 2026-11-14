# Theo dõi PnR `soc_top`

Danh sách việc PnR sau buổi trường 29–30/10, theo bản tổng hợp của Phát ngày 30/10. Cập nhật 13/11. Floorplan và số liệu chi tiết ở `docs/pd02_floorplan.md`, cách chạy ở `docs/flow_notes.md`.

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
| Connectivity | 12 cảnh báo IMPVFC-94: dây VDD Metal7 dài 0 ở đầu dải VDD của vành macro, mép trên. Lần 29/10 không có. Chờ Phúc chạy IR drop, sửa ở PD-08 nếu còn sau PD-05 |
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
