# Theo dõi PnR `soc_top`

Danh sách việc PnR sau buổi trường 29–30/10, theo bản tổng hợp của Phát ngày 30/10. Cập nhật 31/10. Floorplan và số liệu chi tiết ở `docs/pd02_floorplan.md`, cách chạy ở `docs/flow_notes.md`.

## 1. Tình trạng từng mục

| # | Vấn đề | Trạng thái | Đã làm hoặc còn lại |
| --- | --- | --- | --- |
| 1 | GDS, SPEF và netlist sau PnR của `soc_top` bị đưa lên repo công khai (commit 29/10) | Xong 31/10 | Nhóm chọn xoá file khỏi repo, không viết lại lịch sử. `.gitignore` chặn các file này ở mọi thư mục kể cả `appendix/`. Xem mục 2 |
| 2 | Netlist `soc_top` đã đổi sau lần PnR 29/10 (bản giữ flop cho LEC, sắp có bản buffer mạng reset) | Chờ server | Phát chạy lại `make synth-soc`, rồi `make pnr-soc` với netlist mới |
| 3 | `run_all.tcl` chưa gọi `soc_floorplan.tcl`, macro do Innovus tự đặt | Xong 31/10 | `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl` |
| 4 | 1220 cell `CLKBUFX2` trong netlist PnR | Xong 31/10 | `CLKBUFX2` bị cấm ngay sau `init_design`, trước mọi bước tối ưu. Còn 11 cell từ Genus: Phát thêm `CLKBUFX2` vào danh sách cấm của `synth_soc.tcl` thì hết hẳn |
| 5 | `run_all.tcl` bị đổi cứng sang `soc_top`, `make pnr-accel` hỏng | Xong 31/10 | Chọn khối bằng biến `TOP`. `make pnr-accel` dùng `TOP=accel_wrapper` như cũ |
| 6 | Hold trước CTS: 1080 đường vi phạm, xấu nhất −0,147 ns ở chân CEN của macro IMEM | Chờ server | Trước CTS clock còn lý tưởng nên hold chưa có ý nghĩa. `run_all.tcl` đã có `optDesign -postCTS -hold` và `optDesign -postRoute -setup -hold`. Lần chạy tới kiểm `postcts_hold` và `postroute_hold` phải WNS ≥ 0 |
| 7 | Chưa có report timing, DRC của `soc_top` trong repo. Ảnh layout có 5 dấu X trắng | Chờ server | Chép `pnr/out_soc/reports/` vào `appendix/pnr_soc/`. Mở `DBS/route.enc`, xem Violation Browser để biết 5 dấu X là gì |
| 8 | Diện tích logic thật 53 408 µm², lõi tính theo số cũ | Xong 31/10 | Lõi đúng là 394 × 395 µm ở mật độ 70%. Lõi 524 × 523 µm của lần 29/10 tính sai (nhập tổng có cả macro vào `--std-area`) |
| 9 | `appendix/macro_check/sram_2k_macro_20261030.txt` còn trên server | Chờ server | Commit file này ở buổi tới. Dùng nó để chọn lại hướng macro và lớp ring |
| 10 | Sheet trùng ID VER-09 | Xong | Đã đổi trước ngày 31/10, Sheet hiện chỉ còn một VER-09 |
| 11 | Ảnh layout ở `docs/images/`, hình khác ở `docs/figures/` | Xong 31/10 | Chuyển sang `docs/figures/soc_top_layout.png` |

## 2. File bản quyền trong repo (31/10)

Nhóm thống nhất giữ repo công khai, sửa `.gitignore` và xoá file dựng từ PDK:

- Đã xoá `pnr/out_soc/soc_top.gds`, `soc_top.spef`, `soc_top_pnr.v` khỏi repo. Lịch sử Git không viết lại, nên mã commit của mọi người giữ nguyên và chỉ cần `git pull` như bình thường.
- Hạn chế: 3 file vẫn còn trong lịch sử (commit 576960e ngày 29/10), ai mở commit đó trên GitHub vẫn tải được. Muốn xoá hẳn thì phải viết lại lịch sử (`git filter-repo`) và mọi người clone lại. Hoặc chuyển repo sang private.
- `.gitignore` giờ chặn ở mọi thư mục: thư viện (`.lib`, `.lef`, `.gds`, `.cdl`...), SPEF, SDF, `*_netlist.v`, `*_pnr.v`, `*_pnr_pg.v`, database Innovus. Mấy dòng này nằm cuối file nên `!appendix/**` không mở lại được. Không dùng `git add -f` cho output của flow.

## 3. Việc cho buổi lên trường tới

1. Phát: `make synth-soc` (bản giữ flop, có buffer mạng reset). Nên thêm `CLKBUFX2` vào danh sách cấm của Genus.
2. Nguyên: `make pnr-soc`, rồi kiểm:
   - Macro nằm đúng 2 hàng trên và dưới (chụp floorplan).
   - `grep -c CLKBUFX2 pnr/out_soc/soc_top_pnr.v` ra 0.
   - Hold sau CTS và sau route WNS ≥ 0, DRC, connectivity, antenna 0 lỗi.
3. Chép report vào `appendix/pnr_soc/`, commit `appendix/macro_check/`. Không commit gì trong `pnr/out_soc/`.
