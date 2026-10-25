# Runbook: các task của Nguyên

Tài liệu này giải thích từng task Nguyên đang làm (nó là gì, vì sao cần, xong khi nào) và cách chạy từng bước, ở nhà và ở trường.

## 1. Các task hiện tại

### HT-02 Hỏi VPN (Xong)

Trường không mở VPN. Hệ quả: mọi bước Cadence (Genus, Conformal, Innovus) chỉ chạy được khi ngồi ở trường. Ở nhà chỉ làm RTL, mô phỏng và flow mã nguồn mở. Phải dồn việc Cadence vào các buổi lên trường và chuẩn bị script sẵn ở nhà.

### HT-01 Kiểm tra server (Xong 21/10)

Mục tiêu: biết chắc server có gì trước khi cả nhóm viết script: phiên bản Genus/Innovus/Conformal, đường dẫn `PDK_GPDK45`, file `.lib` slow/fast, **SRAM hard macro** (tên, kích thước trong LEF, có `.lib` không), toolchain RISC-V, server có ra GitHub được không.
Xong khi: có file `appendix/server_check/server_check_<ngày>.txt` gửi cho Phát và điền đường dẫn `PDK_DIR` vào nhóm.
Rủi ro lớn nhất: không có SRAM macro trong GPDK45. Khi đó phải báo nhóm ngay để chuyển sang phương án dự phòng trong doc (memory compiler của trường, hoặc macro do nhóm tự làm).

### HT-04 Môi trường ở nhà (Xong 25/10)

Mục tiêu: cả nhóm mô phỏng và tổng hợp thử được ở nhà mà không cần Cadence. Hướng dẫn trong `docs/setup_home.md` (WSL2 + Docker IIC-OSIC-TOOLS tag `2026.10` + VS Code). Lệnh `scripts/eda.sh` bật container, chạy test và mở sóng. Đã kiểm chứng trên máy Nguyên.
Xong khi: một máy Windows khác (không phải máy Nguyên) làm đúng theo hướng dẫn và chạy `scripts/eda.sh check` ra 2 dòng PASS. Đạt ngày 25/10: Hiếu cài và chạy được trên máy của mình.

### RTL-05 Wrapper accelerator (Xong 25/10)

Mục tiêu: biến accelerator của Lab 2 (mảng systolic 4x4, chỉ có chân dữ liệu) thành một ngoại vi mà CPU điều khiển được bằng lệnh `sw/lw`.
Đã có:

- `rtl/accel/accel_wrapper.v`: thanh ghi CTRL/STATUS/INFO, bộ đệm A, B, C, FSM IDLE -> CLR -> RUN, bộ sinh lệch pha (skew), ngắt `irq` khi xong.
- `rtl/accel/accel_apb.v`: lớp vỏ APB3 (chỉ truy cập word, `PSLVERR` khi truy cập địa chỉ không định nghĩa hoặc ghi vào C_BUF). Dùng nếu nhóm chấp nhận đề xuất "ngoại vi nối qua cầu APB3" trong doc.
- `rtl/accel/accelerator_top.v`, `rtl/accel/pe.v`: lõi Lab 2 (Hiếu đưa lên 22/10), thêm chân `en` cho PE để Genus gate clock.
- `fw/accel.h`: hàm C cho firmware.
- 2 testbench: `tb_accel_wrapper.v` (40 phép nhân ngẫu nhiên + biên), `tb_accel_apb.v` (10 phép nhân qua APB + 4 kiểm tra lỗi).

Đã ghép lõi Lab 2 ngày 25/10 (mục 3). Còn xác nhận tỉ lệ clock gating bằng Genus ở buổi lên trường tới, làm chung với PD-01.

Bản đồ thanh ghi (base `0x3000_0000`):

| Offset | Tên | Ý nghĩa |
| --- | --- | --- |
| 0x000 | CTRL | bit0 START (ghi 1 để chạy), bit1 IRQ_EN |
| 0x004 | STATUS | bit0 BUSY, bit1 DONE (ghi 1 để xoá) |
| 0x008 | INFO | {N, DW, AW, LAT}, firmware đọc để tự kiểm tra |
| 0x100-0x10C | A_BUF | 16 byte ma trận A, 4 byte mỗi word, theo hàng |
| 0x200-0x20C | B_BUF | 16 byte ma trận B |
| 0x300-0x33C | C_BUF | 16 kết quả, mỗi kết quả 1 word (20 bit, mở rộng dấu) |

Quy trình firmware: ghi A, B -> ghi CTRL = 1 (hoặc 3 nếu dùng ngắt) -> chờ DONE (hoặc ngắt) -> đọc C -> ghi STATUS = 2 để xoá DONE.

### PD-01 Chạy thử flow Cadence trên accelerator (90%)

Mục tiêu: chạy trọn Genus -> LEC -> Innovus trên một khối nhỏ (accelerator) trước khi có SoC, để khi SoC sẵn sàng chỉ việc đổi tên top. Script viết đúng cú pháp Lab 01-05 nên dễ đối chiếu.
Xong khi: tất cả tiêu chí trong `docs/flow_notes.md` đạt ở bước tới CTS (WNS >= 0, 0 violation geometry, skew <= 80 ps), báo cáo nằm trong `appendix/`.

### PD-02 Ước lượng die (70%)

Mục tiêu: chọn kích thước floorplan cho SoC: đủ chỗ cho 2 SRAM macro + cell chuẩn ở mật độ 70%, chừa 15 um cho power ring.
Cần đầu vào: kích thước SRAM (đã có: 80 x 100 um, từ HT-01) và diện tích cell chuẩn SoC (Genus của Phát, M2). Trước đó có thể chạy với số tạm để biết cỡ.
Cách làm với SRAM macro ở từng tool (Genus, LEC, Innovus, STA, DRC/LVS) và việc cần kiểm tra trên server: `docs/macro_notes.md`, chạy `bash scripts/macro_info.sh`.

### Các task tiếp theo (chưa tới hạn)

PD-03 đến PD-08 (floorplan SoC với macro, power plan, place, CTS, route, signoff DRC/LVS/STA) dùng lại `pnr/scripts/run_all.tcl`. PWR-02 (công suất sau layout) dùng SPEF + VCD từ mô phỏng firmware thật.

## 2. Chạy ở nhà

Cài môi trường theo `docs/setup_home.md`. Repo phải nằm ở `~/eda/designs/rv32i-soc` thì container mới thấy. Mọi lệnh dưới đây gõ trong cửa sổ Ubuntu (WSL), tool chạy trong container:

```bash
cd ~/eda/designs/rv32i-soc
scripts/eda.sh start                      # bật container (VNC: http://localhost:8080, mật khẩu abc123)
scripts/eda.sh check                      # lint + 2 bài mô phỏng, phải ra 2 dòng PASS và 0 %Warning
scripts/eda.sh run "make sim-accel"       # chạy riêng một target
scripts/eda.sh wave                       # ghi tb/unit/out/accel.vcd rồi mở GTKWave trên desktop VNC
scripts/eda.sh stop                       # tắt container khi xong việc
```

GTKWave mở với preset `tb/unit/accel.gtkw` đã chọn sẵn các tín hiệu: `dut.state`, `dut.busy`, `dut.done`, `dut.cnt`, `dut.a_feed`, `dut.b_feed`, `irq`. Hình FSM chuyển IDLE -> CLR -> RUN và dữ liệu lệch pha là ảnh tốt cho report. Muốn xem nhanh trong VS Code thì mở file `.vcd` bằng extension VaporView.

Thử nhanh tổng hợp bằng Yosys (chỉ để xem số cell, không dùng trong report):

```bash
scripts/eda.sh run 'yosys -p "read_verilog rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v; synth -top accel_wrapper; stat"'
```

## 3. Ghép lõi Lab 2 (RTL-05, xong 25/10)

Trả lời 4 câu hỏi khi đọc `accelerator_top.v` và `pe.v`:

| Câu hỏi | Lõi Lab 2 | Cách wrapper xử lý |
| --- | --- | --- |
| Có dấu hay không dấu | Có dấu, 8 bit, tích luỹ 20 bit | `SIGNED=1` |
| Lõi tự lệch pha dữ liệu không | Không, `a_row*`, `b_col*` vào thẳng biên mảng | Giữ bộ sinh skew của wrapper |
| Có start/busy/done không | Có. `busy` kéo dài 10 chu kỳ sau `start`, `valid_in = busy` | Pulse `start` cùng `clear` ở trạng thái CLR, `busy` trùng 10 chu kỳ RUN |
| Kết quả ra thế nào | Đọc một hàng qua `row_sel` one-hot, đủ sau 10 chu kỳ = 3N − 2 | `LAT = 10` giữ nguyên, `row_sel` lấy từ địa chỉ C_BUF |

Sửa lõi Lab 2 (đúng yêu cầu RTL-05 "enable cho a_out/b_out"):

- `pe.v` thêm chân `en`. Thanh ghi truyền và tích luỹ chỉ cập nhật khi `en=1`, `accelerator_top` nối `en = busy`. Yosys đếm 863/864 flop có enable.
- `clr_acc` xoá cả thanh ghi truyền, vì khi `en=0` chúng giữ giá trị của lần chạy trước.
- Thêm `` `timescale `` cho khớp các file khác (Verilator báo TIMESCALEMOD).

Kết quả 25/10: `scripts/eda.sh check` 2 PASS, lint 0 warning. Mức SoC: `lint-soc`, `lint-bus` PASS, `unit-bus` 7/7, `fw-soc` 126/126 (bài `soc` nhân ma trận trên accelerator qua APB, so với kết quả tính sẵn).

## 4. Chạy ở trường (Cadence)

Mỗi buổi trên server:

```bash
# 1. Lấy code (nếu server không ra internet: scp thư mục từ máy cá nhân)
git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git && cd rv32i-soc
#    hoặc: cd rv32i-soc && git pull

# 2. Môi trường Cadence: source giống hệt đầu buổi Lab (lệnh do trường cấp)
export PDK_DIR=<đường dẫn PDK_GPDK45 như trong Lab>

# 3. HT-01 (chỉ buổi đầu)
make check-server
cat appendix/server_check/server_check_*.txt

# 4. Tổng hợp: baseline không clock gating, rồi bản chính
CG=0 make synth-accel && mv syn/out_accel syn/out_accel_cg0
make synth-accel
```

Kiểm tra sau tổng hợp (trong `syn/out_accel/reports/`):

| Kiểm tra | Đạt khi |
| --- | --- |
| `audit/pre_syn_unresolved.rpt`, `audit/pre_syn_design_lint.rpt` | 0 unresolved, 0 latch, 0 loop, 0 multi-driven |
| `audit/post_syn_design_lint.rpt` | 0 floating input, không còn assign |
| `audit/pre_syn_timing_intent.rpt` | 0 unconstrained endpoint |
| `synthesis/timing.rpt` | slack >= 0 ở 20 ns |
| `synthesis/clock_gating.rpt` (chỉ bản CG=1) | đa số flop được gate |
| `synthesis/power.rpt` | so 2 bản CG=0 và CG=1 |

LEC theo mẫu `run_lec_cg.do` của Lab 1 (dofile Genus sinh ra cần license Conformal Ultra, server không có):

```bash
make lec-accel     # dùng lec/accel_rtl2gate.do, phải 0 non-equivalent
```

Place & Route:

```bash
cd ~/rv32i-soc && make pnr-accel
```

Xem kết quả và chụp hình cho report:

```bash
cd pnr/run_accel && innovus
# trong Innovus:
source DBS/cts.enc    # giống Lab, hoặc floorplan.enc / placement.enc
```

Chụp: floorplan + power grid, placement, cây clock (CCOpt Clock Tree Debugger), bảng timing. Đối chiếu bảng tiêu chí trong `docs/flow_notes.md`.

Lưu kết quả và đẩy lên:

```bash
mkdir -p appendix/synth_accel appendix/pnr_accel
cp -r syn/out_accel/reports/* appendix/synth_accel/
cp -r pnr/out_accel/reports/* appendix/pnr_accel/
git add appendix && git commit -m "Add accelerator synthesis and P&R reports" && git push
```

Không copy `.lib`, `.lef`, `.gds`, file SRAM macro hay bất kỳ file nào của GPDK45 ra khỏi server. `.gitignore` đã chặn các đuôi này nhưng vẫn kiểm tra `git status` trước khi commit.

## 5. Lỗi thường gặp (rút từ Lab)

| Triệu chứng | Nguyên nhân | Cách xử lý |
| --- | --- | --- |
| Innovus báo IMPSP-9099 | netlist có scan flop (SDFF*) | script Genus không chèn scan. Nếu vẫn gặp, kiểm tra netlist có cell SDFF và cấm chúng bằng `set_dont_use` |
| LEC non-equivalent sau clock gating | dofile tự viết không biết cell gating | xem `syn/out_accel/lec.txt`, so lại cell gating trong netlist với thư viện `.v`. Dofile Genus sinh cần license Ultra nên không dùng |
| Hold vi phạm sau CTS | chỉ chạy setup | `optDesign -postCTS -hold` với view fast |
| Skew lớn | dùng CLKBUFX2 | `setDontUse CLKBUFX2 true` trước `ccopt_design` |
| `PDK_DIR` không tìm thấy | chưa export | `echo $PDK_DIR`, sửa trong `pnr/scripts/config.tcl` |
| File fast lib khác tên | GPDK45 trường đặt tên khác | sửa `LIB_FAST` trong `config.tcl` theo kết quả HT-01 |
