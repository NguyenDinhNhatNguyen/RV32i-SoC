# Theo dõi PnR `soc_top`

Danh sách việc PnR sau buổi trường 29–30/10, theo bản tổng hợp của Phát ngày 30/10. Cập nhật 31/10. Floorplan và số liệu chi tiết ở `docs/pd02_floorplan.md`, cách chạy ở `docs/flow_notes.md`.

## 1. Tình trạng từng mục

| # | Vấn đề | Trạng thái | Đã làm hoặc còn lại |
| --- | --- | --- | --- |
| 1 | GDS, SPEF và netlist sau PnR của `soc_top` bị đưa lên repo công khai (commit 29/10) | Xong 31/10 | Đã xoá khỏi repo và khỏi lịch sử Git. `.gitignore` chặn các file này ở mọi thư mục kể cả `appendix/`. Xem mục 2 |
| 2 | Netlist `soc_top` đã đổi sau lần PnR 29/10 (bản giữ flop cho LEC, sắp có bản buffer mạng reset) | Chờ server | Phát đã chạy lại `make synth-soc` ngày 31/10: giữ flop, mạng reset có buffer, 0 `CLKBUFX2` (`docs/sta_results.md` mục 1). Còn `make pnr-soc` với netlist này |
| 3 | `run_all.tcl` chưa gọi `soc_floorplan.tcl`, macro do Innovus tự đặt | Xong 31/10 | `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl` |
| 4 | 1220 cell `CLKBUFX2` trong netlist PnR | Xong 31/10 | `CLKBUFX2` bị cấm ngay sau `init_design`, trước mọi bước tối ưu. 11 cell còn lại từ Genus đã hết từ 31/10, vì `CLKBUFX2` có trong `DONT_USE_CELLS` của `config.tcl` |
| 5 | `run_all.tcl` bị đổi cứng sang `soc_top`, `make pnr-accel` hỏng | Xong 31/10 | Chọn khối bằng biến `TOP`. `make pnr-accel` dùng `TOP=accel_wrapper` như cũ |
| 6 | Hold trước CTS: 1080 đường vi phạm, xấu nhất −0,147 ns ở chân CEN của macro IMEM | Chờ server | Trước CTS clock còn lý tưởng nên hold chưa có ý nghĩa. `run_all.tcl` đã có `optDesign -postCTS -hold` và `optDesign -postRoute -setup -hold`. Lần chạy tới kiểm `postcts_hold` và `postroute_hold` phải WNS ≥ 0 |
| 7 | Chưa có report timing, DRC của `soc_top` trong repo. Ảnh layout có 5 dấu X trắng | Chờ server | `make save-pnr-soc` chép report văn bản vào `appendix/pnr_soc/` (bỏ qua netlist, SPEF, GDS). Mở `DBS/route.enc`, xem Violation Browser để biết 5 dấu X là gì |
| 8 | Diện tích logic thật 53 408 µm², lõi tính theo số cũ | Xong 31/10 | Lõi đúng là 394 × 395 µm ở mật độ 70%. Lõi 524 × 523 µm của lần 29/10 tính sai (nhập tổng có cả macro vào `--std-area`) |
| 9 | `appendix/macro_check/sram_2k_macro_20261030.txt` còn trên server | Chờ server | Commit file này ở buổi tới. Hướng macro không còn phụ thuộc file này: `soc_floorplan.tcl` tự đọc cạnh có chân tín hiệu từ LEF (31/10). Log Innovus in lớp chân VDD/VSS để kiểm lớp ring |
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

1. Phát: `make synth-soc` (bản giữ flop, có buffer mạng reset, cấm `CLKBUFX2`). Đã xong 31/10, netlist ở `syn/out_soc/` trên server.
2. Nguyên: `make pnr-soc`. Cuối lệnh in `pnr/out_soc/reports/pd_checks.rpt`, kiểm:
   - `BUFX2 instances: 0` và `CLKBUFX2 instances: 0`.
   - 8 dòng `Macro ...`: 4 IMEM ở hàng trên, 4 DMEM ở hàng dưới, đúng hướng in trong log (`grep PD-02 pnr/run_soc/innovus.log`).
   - Mật độ cell chuẩn khoảng 70%.
   - Thêm: hold sau CTS và sau route WNS ≥ 0 (`postcts_hold`, `postroute_hold`), DRC, connectivity, antenna 0 lỗi.
3. `make save-pnr-soc` và `make save-pnr-accel` (report PD-01 lần 29/10), commit `appendix/pnr_soc`, `appendix/pnr_accel`, `appendix/macro_check/`. Không commit gì trong `pnr/out_soc/`.
