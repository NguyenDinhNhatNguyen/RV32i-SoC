# SRAM macro qua từng bước flow

Thầy nhắc xem kỹ cách làm với macro. Tài liệu này gom những gì đã biết về `sram_2k_macro`, việc phải làm với macro ở từng tool, và những điểm còn phải kiểm tra hoặc hỏi thầy. Chủ: Nguyên (PD), Phát (RTL-08 wrapper SRAM, STA).

## 1. Đã biết (HT-01, 21/10)

| Thông số | Giá trị |
| --- | --- |
| Tên | `sram_2k_macro` |
| Tổ chức | 1024 word × 32 bit = 4 KB, 1 cổng đọc/ghi |
| Kích thước | 80 × 100 µm |
| Chân | `CLK`, `CEN` (tích cực thấp), `WEN` (tích cực thấp), `A[9:0]`, `D[31:0]`, `Q[31:0]` |
| Ghi theo byte | Không có |
| File trên server | `~/PDK_GPDK45/lef/sram_2k_macro.lef`, `lib/sram_2k_macro.lib`, `lib/sram_2k_macro.v` |
| Không có | GDS, file CDL/SPICE. Thầy xác nhận ngày 22/10 là không cần (mục 3.7) |
| Corner của `.lib` | Chỉ có 1 file, corner typical (1,0 V, 25 °C), không có bản fast hay slow (đọc trên server 29/10) |

## 2. Việc cần kiểm tra trên server

Chạy `bash scripts/macro_info.sh` và dán output vào chat. Script trả lời các câu sau:

| Câu hỏi | Vì sao quan trọng |
| --- | --- |
| Chân tín hiệu nằm ở lớp kim loại nào, ở cạnh nào | Quyết định hướng đặt macro (chân quay vào phía logic) và lớp dùng để đi dây tới chân |
| Chân VDD/VSS có không, ở lớp nào, dạng ring hay stripe | Quyết định cách nối nguồn: stripe chạy qua macro hay ring riêng quanh macro |
| OBS chặn những lớp nào | Lớp bị chặn thì không đi dây qua macro được. Nếu OBS phủ tới Metal4, chỉ Metal5 trở lên đi qua được |
| `SYMMETRY` cho phép xoay/lật kiểu nào | Giới hạn hướng đặt (R0, MX, MY, R180...) |
| `.lib` có mấy corner | Thiếu corner fast thì phân tích hold của đường đi qua macro không chính xác |
| `Q` làm gì khi đang ghi, khi `CEN=1` | Wrapper phải dựa vào hành vi này để biết khi nào `Q` hợp lệ |

## 3. Macro ở từng bước

### 3.1 RTL và mô phỏng (RTL-08)

- Wrapper SRAM chuyển giao diện bus (`docs/spec/core.md` mục 5.1) sang chân macro: đảo `CEN`, `WEN` (tích cực thấp), cắt địa chỉ word `A[9:0]`.
- Không có ghi theo byte: `SB`, `SH` phải đọc, sửa, ghi (spec SoC mục 7.3).
- Nhiều macro cho một vùng (ví dụ 16 KB = 4 macro): bit địa chỉ cao chọn macro, chỉ macro được chọn có `CEN=0`. Mux chọn `Q` phải dùng bit chọn **đã chốt ở chu kỳ trước**, vì `Q` ra ở chu kỳ sau.
- `tb/models/sram_1rw_model.v` hiện khác macro thật: sâu 4096, `ce`/`we` tích cực cao, có byte enable. Cần thêm một model ở nhà có **đúng tên và chân** của `sram_2k_macro` để testbench chạy được cả ở nhà lẫn với model thật trên server.

### 3.2 Genus

- Đọc `.lib` của macro cùng thư viện cell: `read_libs {slow_vdd1v0_basiccells.lib sram_2k_macro.lib}`. Macro là hộp đen có timing, Genus không tổng hợp bên trong.
- `check_design -unresolved` phải 0. Nếu báo unresolved `sram_2k_macro` là quên đọc `.lib` của macro.
- Đường găng dự kiến đi từ `CLK→Q` của SRAM (`docs/spec/core.md` mục 4.5). Kiểm tra `report_timing` có path bắt đầu từ chân `Q` của macro.

### 3.3 LEC

- Macro là hộp đen ở cả golden và revised. Đọc `.lib` của macro (hoặc khai báo `add black box`) để Conformal không cố so bên trong.
- Kiểm tra chân của hộp đen được nối giống nhau ở hai phía.

### 3.4 GLS

- Chỉ chạy trên server: dịch netlist cùng `sram_2k_macro.v` thật và thư viện cell `.v`.

### 3.5 Innovus

- Thứ tự LEF: tech LEF, LEF cell, rồi LEF macro (biến `SRAM_LEF` trong `pnr/scripts/config.tcl`).
- Đặt macro **trước** placement và cố định: `placeInstance <inst> x y <hướng> -fixed`.
  - Sát biên core hoặc góc, chân quay vào giữa, nơi có logic.
  - Giữa hai macro chừa khe đủ rộng để đi dây, hoặc ghép sát hẳn. Khe hẹp gây nghẽn dây.
- Halo quanh macro để cell không đặt sát chân: `addHaloToBlock 5 5 5 5 <inst>` (`estimate_die.py` đã tính 5 µm).
- Hàng cell chuẩn bị cắt dưới macro (kiểm tra bằng `checkPlace` và xem floorplan).
- Nguồn: nối chân VDD/VSS của macro bằng `sroute -connect {blockPin}`. Nếu chân nguồn của macro ở lớp thấp hoặc là ring riêng, thêm ring quanh macro: `addRing -type block_rings`.
- Đi dây: dây tín hiệu chỉ qua macro ở các lớp không bị OBS.

### 3.6 STA

- Dùng `.lib` của macro cho cả setup và hold. Nếu chỉ có corner slow, view hold dùng tạm `.lib` slow cho macro và ghi rõ trong report.

### 3.7 Kiểm tra cuối và xuất file

- Thầy xác nhận ngày 22/10: đồ án không đi tới sản xuất, chỉ cần đủ flow PD như bình thường. Không cần GDS và CDL của macro.
- Kiểm tra cuối làm trong Innovus như PD-01: `verify_drc`, `verifyConnectivity`, `verifyProcessAntenna`, timing sau route. Macro được kiểm theo LEF (chân, OBS), không cần hình học bên trong.
- `streamOut` vẫn chạy được, GDS chỉ có phần do Innovus vẽ, vùng macro để trống. Ghi rõ điều này trong report.

## 4. Hỏi thầy

Đã trả lời (22/10): không cần GDS và CDL của macro, chỉ cần đủ flow PD.

Còn hỏi:

1. Macro chỉ có `.lib` corner typical (đã kiểm 29/10). Hold cho đường qua macro tính thế nào, có bản slow và fast không?
2. Tên "2k" là 2 KB hay 2K word? File `.v` cho thấy 1024 word × 32 bit = 4 KB.
3. Được dùng bao nhiêu macro trong một thiết kế (spec SoC mục 7.2 đề xuất 8 macro cho 32 KB)?

## 5. Thử trước trên một khối nhỏ

Giống PD-01 với accelerator: dựng wrapper SRAM với 1 macro, chạy Genus, LEC, Innovus trên server để luyện đủ các bước 3.2 đến 3.7 trước khi ghép cả SoC. Cần RTL-08 của Phát. Genus cho bản 1 macro: `make synth-block B=sram_wrap1` (kết quả ở `syn/out_blocks/sram_wrap1/`).
