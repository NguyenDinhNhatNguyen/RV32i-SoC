# Runbook: các task của Nguyên

Tài liệu này giải thích từng task Nguyên đang làm (nó là gì, vì sao cần, xong khi nào) và cách chạy từng bước, ở nhà và ở trường.

## 1. Các task hiện tại

### HT-02 Hỏi VPN (Xong)

Trường không mở VPN. Hệ quả: mọi bước Cadence (Genus, Conformal, Innovus) chỉ chạy được khi ngồi ở trường. Ở nhà chỉ làm RTL, mô phỏng và flow mã nguồn mở. Phải dồn việc Cadence vào các buổi lên trường và chuẩn bị script sẵn ở nhà.

### HT-01 Kiểm tra server (30%)

Mục tiêu: biết chắc server có gì trước khi cả nhóm viết script: phiên bản Genus/Innovus/Conformal, đường dẫn `PDK_GPDK45`, file `.lib` slow/fast, **SRAM hard macro** (tên, kích thước trong LEF, có `.lib` không), toolchain RISC-V, server có ra GitHub được không.
Xong khi: có file `appendix/server_check/server_check_<ngày>.txt` gửi cho Phát và điền đường dẫn `PDK_DIR` vào nhóm.
Rủi ro lớn nhất: không có SRAM macro trong GPDK45. Khi đó phải báo nhóm ngay để chuyển sang phương án dự phòng trong doc (memory compiler của trường, hoặc macro do nhóm tự làm).

### HT-04 Môi trường ở nhà (60%)

Mục tiêu: cả nhóm mô phỏng và tổng hợp thử được ở nhà mà không cần Cadence. Hướng dẫn trong `docs/setup_home.md` (WSL2 + Docker IIC-OSIC-TOOLS, hoặc cài Icarus/Verilator/Yosys rời).
Xong khi: một máy Windows khác (không phải máy Nguyên) chạy được `make sim-accel` ra PASS theo đúng hướng dẫn.

### RTL-05 Wrapper accelerator (70%)

Mục tiêu: biến accelerator của Lab 2 (mảng systolic 4x4, chỉ có chân dữ liệu) thành một ngoại vi mà CPU điều khiển được bằng lệnh `sw/lw`.
Đã có:

- `rtl/accel/accel_wrapper.v`: thanh ghi CTRL/STATUS/INFO, bộ đệm A, B, C, FSM IDLE -> CLR -> RUN, bộ sinh lệch pha (skew), ngắt `irq` khi xong.
- `rtl/accel/accel_apb.v`: lớp vỏ APB3 (chỉ truy cập word, `PSLVERR` khi truy cập địa chỉ không định nghĩa hoặc ghi vào C_BUF). Dùng nếu nhóm chấp nhận đề xuất "ngoại vi nối qua cầu APB3" trong doc.
- `rtl/accel/sa_core_model.v`: lõi giả cùng cấu trúc với Lab 2 để test trước.
- `fw/accel.h`: hàm C cho firmware.
- 2 testbench: `tb_accel_wrapper.v` (40 phép nhân ngẫu nhiên + biên), `tb_accel_apb.v` (10 phép nhân qua APB + 4 kiểm tra lỗi).

Còn lại (30%): thay lõi giả bằng `pe.v` + `accelerator_top.v` của Lab 2, chỉnh độ trễ `LAT`, chạy lại test. Chi tiết ở mục 3.

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

### PD-01 Chạy thử flow Cadence trên accelerator (30%)

Mục tiêu: chạy trọn Genus -> LEC -> Innovus trên một khối nhỏ (accelerator) trước khi có SoC, để khi SoC sẵn sàng chỉ việc đổi tên top. Script viết đúng cú pháp Lab 01-05 nên dễ đối chiếu.
Xong khi: tất cả tiêu chí trong `docs/flow_notes.md` đạt ở bước tới CTS (WNS >= 0, 0 violation geometry, skew <= 80 ps), báo cáo nằm trong `appendix/`.

### PD-02 Ước lượng die (20%)

Mục tiêu: chọn kích thước floorplan cho SoC: đủ chỗ cho 2 SRAM macro + cell chuẩn ở mật độ 70%, chừa 15 um cho power ring.
Cần đầu vào: kích thước SRAM (từ HT-01) và diện tích cell chuẩn SoC (Genus của Phát, M2). Trước đó có thể chạy với số tạm để biết cỡ.

### Các task tiếp theo (chưa tới hạn)

PD-03 đến PD-08 (floorplan SoC với macro, power plan, place, CTS, route, signoff DRC/LVS/STA) dùng lại `pnr/scripts/run_all.tcl`. PWR-02 (công suất sau layout) dùng SPEF + VCD từ mô phỏng firmware thật.

## 2. Chạy ở nhà

```bash
git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git
cd rv32i-soc
make sim-accel        # 40 phép nhân, phải in PASS
make sim-accel-apb    # qua giao diện APB3, phải in PASS
make wave-accel       # ghi tb/unit/out/accel.vcd
gtkwave tb/unit/out/accel.vcd tb/unit/accel.gtkw &
make lint-accel       # cần Verilator, 0 warning là tốt
```

Trong GTKWave nên kéo các tín hiệu: `dut.state`, `dut.busy`, `dut.done`, `dut.cnt`, `dut.a_feed`, `dut.b_feed`, `irq`. Hình FSM chuyển IDLE -> CLR -> RUN và dữ liệu lệch pha là ảnh tốt cho report.

Thử nhanh tổng hợp bằng Yosys (chỉ để xem số cell, không dùng trong report):

```bash
yosys -p "read_verilog rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v; synth -top accel_wrapper; stat"
```

## 3. Ghép lõi Lab 2 (hoàn thành RTL-05)

1. Copy `pe.v`, `accelerator_top.v` của Lab 2 vào `rtl/accel/lab2/` (code của nhóm, được phép đưa lên repo).
2. Đọc RTL Lab 2 và trả lời 4 câu hỏi, ghi vào `docs/nguyen_handoff.md`:
   - Số có dấu hay không dấu? -> tham số `SIGNED`.
   - Lõi tự lệch pha dữ liệu hay cần cấp sẵn đã lệch? Nếu tự lệch: bỏ bộ skew trong wrapper (đề xuất trong doc: "chỉ thêm bộ sinh lệch pha nếu RTL cần").
   - Có chân start/busy/done không? Nếu có: nối vào FSM thay cho bộ đếm `cnt`.
   - Kết quả ra song song hay xả tuần tự? Sau bao nhiêu chu kỳ? -> `LAT` và cách nạp C_BUF.
3. Thay instance `sa_core_model` trong `accel_wrapper.v` bằng `accelerator_top`, sửa `ACCEL_RTL` trong `Makefile`.
4. `make sim-accel && make sim-accel-apb` phải PASS. Nếu sai, mở sóng để xem kết quả lệch mấy chu kỳ.
5. Cập nhật sheet: RTL-05 = Xong, cột Bằng chứng = link commit.

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

LEC (giống Lab):

```bash
cd syn/out_accel && lec -nogui -dofile rtl2gate.do | tee lec.log   # phải 0 non-equivalent
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
| LEC non-equivalent sau clock gating | dofile tự viết không biết cell gating | dùng `rtl2gate.do` do Genus sinh (`write_do_lec`) cùng lần chạy với netlist, như Lab |
| Hold vi phạm sau CTS | chỉ chạy setup | `optDesign -postCTS -hold` với view fast |
| Skew lớn | dùng CLKBUFX2 | `setDontUse CLKBUFX2 true` trước `ccopt_design` |
| `PDK_DIR` không tìm thấy | chưa export | `echo $PDK_DIR`, sửa trong `pnr/scripts/config.tcl` |
| File fast lib khác tên | GPDK45 trường đặt tên khác | sửa `LIB_FAST` trong `config.tcl` theo kết quả HT-01 |
