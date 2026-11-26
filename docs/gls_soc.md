# GLS soc_top (VER-07)

Chủ: Hiếu. Mô phỏng mức cổng netlist `soc_top` của Genus bằng `tb_soc` và các chương trình của `make fw-soc` (cấu hình M1W1). Mục tiêu là kiểm netlist chạy đúng chức năng như RTL, trước khi chạy với SDF ở VER-08.

**Trạng thái (19/11):** PASS. Netlist Genus chính thức (STA-04) chạy trên server bằng Xcelium, 71/71 test PASS, zero delay (mục 5). GLS có SDF để dành cho VER-08.

## 1. Cách tb_soc chạy ở mức cổng

Bật bằng define `GLS` (`tb/soc/tb_soc.v`). Chế độ RTL không đổi.

- Top là `soc_top` của netlist, không truyền parameter. Netlist chính thức có `ENABLE_M=1`, `ENABLE_WFI_SLEEP=1`, `ENABLE_DMA=1`, nên chỉ chạy các chương trình của cấu hình M1W1.
- Netlist giữ 8 macro `sram_2k_macro` (4 IMEM, 4 DMEM). `scripts/gls_paths.py` đọc netlist, tìm đường dẫn của từng macro và ghi `gls_paths.vh`. Tên sau Genus có thể là tên escape hoặc phẳng. Script xử lý cả hai.
- Chương trình được nạp thẳng vào mảng word của từng macro sau thời điểm 0. Bank chọn theo bit [11:10] của địa chỉ word, như RTL.
- tb không đọc được tín hiệu bên trong lõi. Kết quả lấy từ lệnh ghi vào `tohost` ở chân của macro chứa địa chỉ đó (`CEN`, `WEN`, `A`, `D`). Ghi 1 là PASS. Giá trị khác là FAIL kèm số test.
- Chương trình fw-soc đặt `tohost` trong DMEM. riscv-tests đặt `tohost` trong IMEM (ví dụ `0x6c0`). tb chọn macro IMEM hay DMEM theo địa chỉ `tohost`.
- Mỗi chu kỳ tb kiểm `uart_tx` không là X, và dừng khi quá `+timeout`.
- Bộ giải mã UART, thống kê DMA và phép kiểm reset của chế độ RTL bị tắt.
- Clock mặc định 10 ns như RTL. `GLS_HALF` đổi nửa chu kỳ. `GLS_SDF` gọi `$sdf_annotate` (để dành cho VER-08).

## 2. Ở nhà: chuẩn bị file hex

Server không có đủ toolchain để dịch firmware, nên tạo file hex ở nhà rồi chép lên.

```bash
scripts/eda.sh run "make fw-soc fw-soc-c"
scripts/eda.sh run "make gls-soc-pack"
```

`gls-soc-pack` gói 213 file (71 chương trình, mỗi chương trình có `.imem.hex`, `.dmem.hex`, `.tohost`) vào `tb/soc/out/gls_images.tgz`. Chép lên server (lệnh này chạy ở máy nhà):

```bash
scp tb/soc/out/gls_images.tgz s23521043@192.168.26.26:~/RV32i-SoC-main/
```

Kiểm thử flow ở nhà, không cần server (tùy chọn, Icarus trên netlist Yosys, chậm):

```bash
scripts/eda.sh run "make gls-soc-home"                    # soc và rv32ui-p-add
scripts/eda.sh run "make gls-soc-home T=soc_fw_rv32im"    # firmware C, khoảng 20 phút
```

## 3. Trên server: chạy GLS

Chạy trong bản clone `~/RV32i-SoC-main` (nhánh main). Lúc viết, `~/RV32i-SoC` còn ở nhánh của Phúc. Từ 14/11 `~/RV32i-SoC` đã về `main`, nên chạy ở đó cũng được (đổi `cd` cho đúng thư mục).

```bash
cd ~/RV32i-SoC-main
git pull
tar xzf gls_images.tgz
ls -la syn/out_soc/soc_top_netlist.v
make gls-soc T="soc rv32ui-p-add"     # chạy thử 2 test
make gls-soc                           # đủ 71 test
```

- Netlist mặc định là `syn/out_soc/soc_top_netlist.v` (STA-04, RTL `e60437a`, Genus 9 ns). Nếu netlist ở chỗ khác thì thêm `NETLIST=<đường dẫn>`.
- Thư viện cell mặc định là `~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v` (đổi bằng `GLS_LIB=...`).
- Với xrun, model macro mặc định là model thật `~/PDK_GPDK45/lib/sram_2k_macro.v`. Script tự tìm tên mảng word trong model và in ra dòng `word array "..."`. Nếu script báo không tìm được thì xem model và đặt `MACRO_MEM=<tên mảng>`.
- Nếu model thật lưu dữ liệu khác kiểu một word 32 bit cho mỗi địa chỉ, chạy bằng model ở nhà để kiểm chức năng: `MACRO_V=tb/models/sram_2k_macro.v make gls-soc`. Hai model cùng chân và cùng hành vi đọc ghi (`docs/bus_mem.md` mục 6).
- Zero delay là mặc định (`-nospecify -notimingchecks`). Có SDF thì thêm `SDF=<file> HALF=5`.

Đạt khi dòng cuối là `gls-soc: 71 passed, 0 failed`. Log từng test, `elab.log`, `gls_paths.vh` và `summary.txt` ở `syn/out_soc/gls/`.

Lưu kết quả cho repo (chỉ file text do nhóm tạo, không có dữ liệu thư viện):

```bash
mkdir -p appendix/gls_soc
cp syn/out_soc/gls/summary.txt syn/out_soc/gls/gls_paths.log appendix/gls_soc/
```

Rồi chép `appendix/gls_soc/` về máy nhà bằng scp và commit.

## 4. Các biến của scripts/gls_soc.sh

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `SIM` | `xrun` | `xrun` hoặc `iverilog` |
| `NETLIST` | `syn/out_soc/soc_top_netlist.v` | Netlist `soc_top` |
| `GLS_LIB` | `~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v` | Model Verilog của cell |
| `MACRO_V` | model thật nếu có (xrun), không thì `tb/models/sram_2k_macro.v` | Model `sram_2k_macro` |
| `MACRO_MEM` | tự tìm | Tên mảng word trong `MACRO_V` |
| `SDF` | rỗng (zero delay) | File SDF cho VER-08, bật timing check |
| `SDF_MTM` | `MAXIMUM` | Giá trị nào trong bộ ba min:typ:max của SDF |
| `HALF` | 5 | Nửa chu kỳ clock (ns) |
| `T` | cả 71 test | Danh sách tên test |
| `OUT` | `syn/out_soc/gls` | Thư mục chạy |

`bash scripts/gls_soc.sh --list` in danh sách file hex cần có.

## 5. Kết quả

### 5.1 Server, netlist Genus (19/11)

- Netlist: `soc_top_netlist.v` của STA-04 (RTL `e60437a`, Genus 9 ns, 4068 flop, 136 ICG), ngày 14/11.
- Xcelium 24.03, `slow_vdd1v0_basiccells.v`, model macro thật `sram_2k_macro.v` (mảng word tên `mem`).
- Zero delay, clock 10 ns. Repo ở `a561331`.

| Test | Kết quả |
|------|---------|
| `soc` | PASS, 2458 chu kỳ |
| `rv32ui-p-add` | PASS, 590 chu kỳ |
| Cả 71 test (fw-soc M1W1, fw-soc-c, riscv-tests rv32ui, rv32mi, rv32um) | **71 PASS, 0 FAIL** |

Số chu kỳ trùng với lần chạy ở nhà trên netlist Yosys. Genus làm phẳng phân cấp phía trên macro thành một tên escape (`\u_imem_u_sram_u_arr_g_multi.g_bank[0].u_mac`). `gls_paths.py` vẫn tìm đúng 8 macro. Log ở `appendix/gls_soc/`.

Lỗi gặp trên server: `python3` báo `undefined symbol: _Py_LegacyLocaleDetected` vì `LD_LIBRARY_PATH` của tool trỏ tới libpython khác. `gls_soc.sh` tự thử lại với `env -u LD_LIBRARY_PATH python3`.

### 5.2 Ở nhà, netlist Yosys (17/11)

Netlist Yosys của `soc_top` (`syn/yosys/gls_home.tcl`, cổng generic, giữ phân cấp, macro là black box), mô phỏng bằng Icarus với `simcells.v` và model macro ở nhà. Zero delay, clock 10 ns.

| Test | GLS | RTL (fw-soc, fw-soc-c) |
|------|-----|-----|
| `soc` | PASS, 2458 chu kỳ | PASS, 2459 chu kỳ |
| `soc_fw_rv32im` | PASS, 247980 chu kỳ | PASS, 247981 chu kỳ |
| `rv32ui-p-add` | PASS, 590 chu kỳ | PASS |
| `rv32um-p-div` | PASS, 488 chu kỳ | PASS |
| `rv32ui-p-add` bị sửa (mã PASS đổi thành 7) | FAIL, `tohost = 0x00000007 (test 3)` | |
| Cả 71 test | 71 PASS, 0 FAIL (20 phút) | 71 PASS (fw-soc M1W1 và fw-soc-c) |

Số chu kỳ lệch 1 vì ở GLS tb bắt lệnh ghi `tohost` ở cạnh xuống tại chân macro, sớm hơn RTL một chu kỳ.

Phép thử âm: sửa lệnh `li gp,1` của `RVTEST_PASS` trong file hex thành `li gp,7`. tb phải in FAIL với `tohost = 0x00000007 (test 3)`. Phép thử này cho thấy tb không báo PASS khi chương trình ghi sai mã.

`gls_paths.py` đã thử trên netlist Yosys giữ phân cấp (tên `\g_multi.g_bank[0]` escape) và netlist phẳng (một tên escape cho mỗi macro).

## 6. Giới hạn

- Không kiểm tín hiệu nội bộ (thanh ghi, PC). Chỉ kiểm mã ghi vào `tohost`, X trên `uart_tx` và timeout.
- Chỉ cấu hình M1W1, đúng cấu hình của netlist.
- Zero delay chỉ kiểm chức năng. Timing kiểm bằng STA, và bằng GLS có SDF ở mục 8.
- Icarus với netlist cổng chậm (khoảng 20 phút cho 250 nghìn chu kỳ). Xcelium nhanh hơn nhiều.

## 7. File

| File | Nội dung |
|------|----------|
| `tb/soc/tb_soc.v` | Nhánh `` `ifdef GLS `` (nạp chương trình qua macro, bắt `tohost` ở chân DMEM) |
| `scripts/gls_soc.sh` | Dịch một lần, chạy từng test, in bảng PASS/FAIL (`make gls-soc`) |
| `scripts/gls_paths.py` | Tìm 8 macro trong netlist, ghi `gls_paths.vh` |
| `syn/yosys/gls_home.tcl` | Netlist Yosys để thử ở nhà (`make gls-soc-home`) |

## 8. GLS có SDF (VER-08)

Chạy netlist sau layout (sau ECO) với SDF của Innovus. Mục tiêu là kiểm netlist có delay thật vẫn chạy đúng ở 100 MHz và không có vi phạm timing trong mô phỏng.

**Trạng thái (26/11):** đã chạy trên server với 2 test (`soc`, `rv32ui-p-add`): cả hai PASS, số chu kỳ bằng RTL, 0 vi phạm timing sau khi reset nhả (mục 8.5). Còn chạy đủ 71 test.

### 8.1 Khác với zero delay

- Netlist là `pnr/out_soc_p9/soc_top_pnr.v`, không phải netlist Genus. Netlist sau layout có thêm buffer clock tree và cell sửa hold, nên phải đi đúng cặp với SDF của nó (`pnr/out_soc_p9/soc_top.sdf`, `write_sdf -view av_setup`, góc slow). Không dùng thư mục `pre_eco/`.
- Model cell phải có khối `specify`. Model trong PDK (`~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v`) không có khối nào, chỉ mô tả chức năng, nên SDF không gán được delay cell vào đó. `make gls-soc-sdf` vì vậy mặc định dùng model gsclib045 đi kèm Stratus (`GLS_TIMING_LIB` trong Makefile, cùng thư mục với Stratus 24.01). Model này có 978 khối `specify` và có đủ 222 loại cell của netlist PnR.
- Bật specify và timing check của model cell (không có `-nospecify -notimingchecks`). Test chỉ PASS khi chương trình ghi 1 vào `tohost` **và** có 0 vi phạm timing sau khi reset nhả.
- Vi phạm trước khi reset nhả không được tính. tb in dòng `GLS: reset released at <t> PS` khi reset nhả. Script chỉ đếm các `Timing violation` có `Time:` từ thời điểm đó trở đi. Trước đó netlist đang đi từ X về giá trị reset và mạch còn đang reset, nên một check ở đây không phải đường timing thật. Số vi phạm trước reset vẫn được ghi trong log (dòng `NOTE:`) và trên dòng PASS.
- tb bắt lệnh ghi `tohost` ở cạnh lên của clock tại port. Clock tới macro muộn hơn (qua clock tree), nên lúc đó chân macro vẫn giữ giá trị mà macro sắp chốt. Ở zero delay vẫn bắt ở cạnh xuống như trước. Vì vậy số chu kỳ có SDF bằng số của RTL, hơn zero delay 1 chu kỳ.
- `$sdf_annotate` dùng giá trị `MAXIMUM` của bộ ba (đổi bằng `SDF_MTM`) và ghi `sdf_annotate.log`. Script chép SDF vào thư mục chạy trước khi đọc, vì Xcelium ghi bản SDF đã dịch cạnh file nó đọc.
- Clock 10 ns (`HALF=5`), đúng tần số signoff. Có thể thử tần số cao hơn bằng `HALF`, ví dụ `HALF=4.5` cho 9 ns.

### 8.2 Trên server

PnR `_p9` chạy trong clone có `pnr/out_soc_p9/`. Tìm thư mục đó trước:

```bash
ls -la ~/RV32i-SoC/pnr/out_soc_p9/soc_top_pnr.v ~/RV32i-SoC/pnr/out_soc_p9/soc_top.sdf
```

Chạy trong `~/RV32i-SoC-main`, chỉ đọc file PnR:

```bash
cd ~/RV32i-SoC-main && git pull
P=~/RV32i-SoC/pnr/out_soc_p9
NETLIST=$P/soc_top_pnr.v SDF=$P/soc_top.sdf make gls-soc-sdf T="soc rv32ui-p-add"
nohup env NETLIST=$P/soc_top_pnr.v SDF=$P/soc_top.sdf make gls-soc-sdf > ~/gls_sdf_run.log 2>&1 &
```

Nếu model Stratus nằm chỗ khác, thêm `GLS_LIB=<đường dẫn model có specify>`.

Đạt khi dòng cuối là `gls-soc: 71 passed, 0 failed` và mỗi dòng PASS ghi `0 timing violations`. Log ở `syn/out_soc/gls_sdf/`. Kiểm thêm `syn/out_soc/gls_sdf/sdf_annotate.first.log` (hoặc `elab.log`): số cell được annotate và không có lỗi `SDFNEP`, `SDFINF` hàng loạt.

Lưu kết quả cho repo:

```bash
mkdir -p appendix/gls_soc_sdf
cp syn/out_soc/gls_sdf/summary.txt syn/out_soc/gls_sdf/gls_paths.log appendix/gls_soc_sdf/
grep -E '\*[WE],SDF|Annotat' syn/out_soc/gls_sdf/elab.log | sort | uniq -c > appendix/gls_soc_sdf/sdf_annotate_summary.txt
```

Không đưa file SDF, netlist hay log có dữ liệu thư viện lên repo.

### 8.3 Nếu gặp lỗi

- **Có timing violation:** script in 2 dòng đầu sau mỗi `Timing violation` (loại check, cell, thời điểm). Gửi phần đó để xem đó là đường thật (so với report Tempus của Phát) hay là input bất đồng bộ từ tb, như `rst_n` hoặc `uart_rx`, đã được false path trong `soc.sdc`.
- **Elaboration báo SDF không khớp netlist:** kiểm netlist và SDF cùng một lần xuất (cùng ngày trong `ls -la`).
- **Test timeout nhưng không có violation:** chạy riêng test đó với `HALF=10` (clock 20 ns). Nếu khi đó PASS thì đường đó không đạt 100 MHz trong mô phỏng, cần đối chiếu với STA.

### 8.4 Kiểm ở nhà (21/11)

Icarus với netlist Yosys và một SDF rỗng (model `simcells.v` không có specify, nên không có delay thật): `soc`, `rv32ui-p-add`, `dma` PASS. Phép thử này chỉ cho thấy tb dịch được với `GLS_SDF`, gọi được `$sdf_annotate`, và phần bắt `tohost` ở cạnh lên đúng (2459 chu kỳ, bằng RTL). Zero delay không đổi (`soc` 2458 chu kỳ).

### 8.5 Kết quả trên server (26/11)

Netlist và SDF của `pnr/out_soc_p9` (18/11, sau ECO, `av_setup`), góc slow, `MAXIMUM`, clock 10 ns.

| Bước | Kết quả |
|------|---------|
| Netlist PnR, zero delay (model PDK) | `soc` PASS, 2458 chu kỳ. Netlist sau layout đúng chức năng |
| SDF với model PDK | timeout. Model không có `specify`, nên delay cell không được gán, chỉ còn delay dây, và mạch chạy sai |
| SDF với model gsclib045 của Stratus | `soc` PASS 2459 chu kỳ, `rv32ui-p-add` PASS 591 chu kỳ. Số chu kỳ bằng RTL |

Vi phạm timing của lần chạy `soc`: 2 vi phạm hold, cả hai ở cạnh clock đầu tiên (5416 ps), khi reset đang giữ:

- `u_uart_bcnt_reg[12]`: D đổi ở 5362 ps, hold yêu cầu 46 ps.
- `u_uart_bcnt_reg[14]`: D đổi ở 5470 ps, hold yêu cầu 64 ps.

Reset nhả sau đó nhiều chu kỳ. Hai vi phạm này là lúc netlist đi từ X về giá trị reset, không phải đường thật, nên không tính (mục 8.1). Sau khi reset nhả không có vi phạm nào.

Cảnh báo `SDFNSB` khi elaborate: 500 dòng đều thuộc `sram_2k_macro`, rồi Xcelium dừng in ở giới hạn 1000 cảnh báo. SDF có các cung delay của macro mà model `sram_2k_macro.v` không khai báo trong `specify`, nên các cung đó không được gán. Các cell chuẩn không có cảnh báo này. Delay bên trong macro vì vậy chưa đầy đủ trong mô phỏng. Timing của macro vẫn được kiểm bằng STA (Tempus) với file `.lib` của macro.

