# Flow Cadence cho rv32_core

Chủ: Nhân. Tổng hợp, LEC và GLS cho lõi RV32I đứng riêng, để lấy số PPA chính thức của lõi (thay số Nangate45 ở `docs/timing_core.md`). Flow chung và tiêu chí nghiệm thu theo Lab ở `docs/flow_notes.md`. Flow `soc_top` dùng `soc.sdc` của Phát và không thuộc file này.

**Trạng thái:** script viết ở nhà, chưa chạy trên server. Đã kiểm ở nhà: cú pháp Tcl (chạy `synth_core.tcl` với lệnh Genus giả trong Tcl 8.6), `core.sdc` đọc được bằng OpenSTA trên netlist Yosys Nangate45, `tb_core -DGLS` PASS trên netlist Yosys bằng Icarus. Lần đầu ở trường cần xem kỹ log Genus và Conformal.

## 1. Cấu hình

| Mục | Giá trị |
| --- | --- |
| Top của netlist | `rv32_core_syn`, wrapper do `synth_core.tcl` sinh vào `syn/out_core/rv32_core_syn.v` |
| Tham số lõi | `ENABLE_M=1`, `ENABLE_WFI_SLEEP=1`, `ENABLE_BTB=1` (BTB 8 entry, D-041), `RESET_PC=0` |
| Clock | 20 ns (50 MHz), quét thêm 10, 8, 6, 5 ns |
| Thư viện | `slow_vdd1v0_basiccells.lib` theo `pnr/scripts/config.tcl`. Cấm `SDFF*` và `BUFX2` |
| Clock gating | `CG=1` mặc định, `lp_clock_gating_min_flops 4`. `CG=0` để so công suất |
| RTL | Verilog-2001 (`read_hdl -language v2001`), đã thử `iverilog -g2001` |

`RESET_PC=0` để netlist chạy được trên `tb_core` (IMEM ở địa chỉ 0). Trong `soc_top` lõi dùng `RESET_PC` là boot ROM. Khác biệt chỉ là giá trị reset của `if_pc_q`, không ảnh hưởng PPA.

### Ràng buộc `syn/constraints/core.sdc`

- Các cổng `if_*` nối tới IMEM macro qua `imem_port`, các cổng `d_*` nối tới DMEM macro và ngoại vi qua bus.
- Delay của macro không co theo chu kỳ nên là số tuyệt đối: `SRAM_CQ` 1,5 ns (CLK→Q), `SRAM_SU` 0,3 ns (setup), `BUS_D` 0,5 ns (decode và mux của bus).
- **Đây là số tạm.** Ở trường chạy `bash scripts/macro_info.sh`, đọc CLK→Q và setup của `sram_2k_macro` ở corner slow, sửa `SRAM_CQ` và `SRAM_SU` trước khi lấy số chính thức.
- Tín hiệu đến từ flop trong SoC (grant, ready, ngắt, `mtime_i`, `rst_n`) giữ tỉ lệ Lab 01: input 24%, output 20% chu kỳ.
- `rst_n` không phải false path. Trong `soc_top` nó ra từ flop của `reset_sync`, nên được kiểm recovery và removal như `soc.sdc`.

## 2. Các bước ở trường

Chạy theo thứ tự, từ thư mục repo. Mỗi bước in một dòng kết quả, kiểm theo bảng ở mục 3.

### Bước 0. Cập nhật repo

```bash
cd ~/rv32i-soc && git pull
git submodule update --init fw/riscv-tests    # để gls-core lấy danh sách test
```

### Bước 1. Tổng hợp ở 20 ns, có clock gating

```bash
make synth-core
```

Kết quả ở `syn/out_core/`: netlist `rv32_core_syn_netlist.v`, `rv32_core_syn_synth.sdc`, `rv32_core_syn.sdf`, report ở `reports/audit/` và `reports/synthesis/` (`qor`, `timing`, `timing_paths`, `area`, `power`, `gates`, `clock_gating`). Dòng cuối in `PERIOD=20 CG=1 ENABLE_BTB=1 WNS_PS=...`.

### Bước 2. LEC

```bash
make lec-core
```

Đạt khi 0 non-equivalent. Report ở `syn/out_core/reports/lec_verification.rpt`, log đầy đủ ở `syn/out_core/lec.txt`. Bộ nhân 32x32 có thể để lại điểm abort. Khi đó GLS ở bước 3 kiểm chức năng thay.

Nếu Conformal báo lỗi ở dòng `read design -golden` (tùy chọn `-incdir`), xem lỗi trong `lec.txt` rồi sửa dòng đó trong `lec/core_rtl2gate.do`.

### Bước 3. GLS

Server có thể không có riscv gcc. Khi đó tạo file hex ở nhà rồi chép lên:

```bash
# Ở nhà
make isa-core
tar czf isa_hex.tgz tb/core/out/isa/*.imem.hex tb/core/out/isa/*.dmem.hex tb/core/out/isa/*.tohost
# Ở trường, trong thư mục repo
tar xzf isa_hex.tgz
```

Chạy:

```bash
make gls-core              # có SDF thì dùng SDF (clock 20 ns), không có thì zero delay
SDF=0 make gls-core        # luôn zero delay (clock 10 ns như mô phỏng RTL)
T="rv32ui-p-add rv32um-p-mul" make gls-core   # vài test
```

Đạt khi dòng cuối là `gls-core: N passed, 0 failed`. Log từng test ở `syn/out_core/gls/`. Ở chế độ GLS, tb không đọc được tín hiệu trong lõi, nên chỉ kiểm bus, X trên bus và giá trị ghi vào tohost.

### Bước 4. Bản không clock gating để so công suất

```bash
mv syn/out_core syn/out_core_cg1
make synth-core CG=0
mv syn/out_core syn/out_core_cg0 && mv syn/out_core_cg1 syn/out_core
```

### Bước 5. Quét chu kỳ tìm F_max

```bash
make synth-core-sweep                       # PERIOD 20, 10, 8, 6, 5 ns, mất vài lần thời gian bước 1
PERIODS="7 6.5" make synth-core-sweep       # quét thêm quanh chỗ WNS đổi dấu
```

Mỗi lần chạy ở `syn/out_core_sweep/p<chu kỳ>/`. Bảng tóm tắt ở `syn/out_core_sweep/summary.md`: WNS, chu kỳ nhỏ nhất (chu kỳ − WNS), F_max ước lượng, cell area. F_max chính thức lấy ở chu kỳ nhỏ nhất còn WNS ≥ 0.

### Bước 6. Lưu report vào repo

Chỉ chép report, không chép netlist, SDF hay file thư viện:

```bash
mkdir -p appendix/synth_core/cg1 appendix/synth_core/cg0 appendix/synth_core/sweep
cp -r syn/out_core/reports/* appendix/synth_core/cg1/
cp -r syn/out_core_cg0/reports/* appendix/synth_core/cg0/
cp syn/out_core/lec.txt appendix/synth_core/cg1/
tail -n 60 syn/out_core/gls/*.log > appendix/synth_core/cg1/gls_tail.txt
for d in syn/out_core_sweep/p*; do mkdir -p appendix/synth_core/sweep/${d##*/}; cp -r $d/reports/synthesis appendix/synth_core/sweep/${d##*/}/; done
cp syn/out_core_sweep/summary.md appendix/synth_core/sweep/
git status --short          # không có .lib .lef .gds .v của thư viện, .sdf
git add appendix/synth_core && git commit -m "Add rv32_core Genus, LEC and GLS reports" && git push
```

## 3. Tiêu chí nghiệm thu

| File | Đạt khi |
| --- | --- |
| `reports/audit/pre_syn_unresolved.rpt`, `pre_syn_design_lint.rpt` | 0 unresolved, 0 latch, 0 loop, 0 multi-driven |
| `reports/audit/pre_syn_timing_intent.rpt` | 0 unconstrained endpoint |
| `reports/audit/post_syn_design_lint.rpt` | 0 floating input, không còn assign |
| `reports/synthesis/timing.rpt` | Slack ≥ 0 ở 20 ns |
| `reports/synthesis/clock_gating.rpt` | Đa số flop được gate (regfile, BTB, CSR có enable) |
| `lec.txt` | 0 non-equivalent |
| `gls/*.log` | Mỗi test một dòng `PASS`, 0 failed |

## 4. Điền số vào `ppa_table.py`

`scripts/ppa_table.py` đọc `qor.rpt`, `area.rpt`, `power.rpt`, `gates.rpt`, `clock_gating.rpt` trong thư mục `reports/synthesis`. Chạy sau bước 6:

```bash
python3 scripts/ppa_table.py \
  --genus cg0=appendix/synth_core/cg0/synthesis \
  --genus cg1=appendix/synth_core/cg1/synthesis \
  --lib ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.lib \
  --cpi 1.072 > appendix/synth_core/ppa_core.md
```

| Số trong bảng | Lấy từ |
| --- | --- |
| Chu kỳ, slack setup | `qor.rpt` (dòng `clk`) |
| Diện tích, số cell, số flop | `qor.rpt`, dự phòng `area.rpt` |
| GE | Diện tích chia diện tích NAND2X1 (từ `--lib` hoặc `gates.rpt`) |
| Công suất tổng và clock | `power.rpt` (dòng `Subtotal` và `clock`) |
| Số ICG | `clock_gating.rpt` |
| EPI | `--cpi`: CPI CoreMark của `tb_core` với ENABLE_M=1 và BTB 8 là 1,072 (`make bench-core`, `docs/bench_core.md`) |
| F_max | `syn/out_core_sweep/summary.md`, không lấy số ước lượng ở 20 ns |

Bảng ra dán vào mục số chính thức của `docs/report/core.md` (các ô [CHỜ GENUS]) và ghi lại trong `docs/timing_core.md`.

## 5. File

| File | Nội dung |
| --- | --- |
| `syn/scripts/synth_core.tcl` | Genus, tham số `CG`, `PERIOD`, `ENABLE_BTB`, `SYN_OUT` |
| `syn/scripts/sweep_core.sh` | Quét chu kỳ, gọi `synth_core.tcl` nhiều lần |
| `syn/constraints/core.sdc` | Ràng buộc của lõi đứng riêng |
| `lec/core_rtl2gate.do` | Conformal, mẫu `accel_rtl2gate.do` |
| `scripts/gls_core.sh` | Xcelium, `tb_core -DGLS`, rv32ui và rv32um |
| `tb/core/tb_core.v` | Nhánh `` `ifdef GLS `` (top `rv32_core_syn`, bỏ phép kiểm đọc `dut.*`), RTL không đổi |
