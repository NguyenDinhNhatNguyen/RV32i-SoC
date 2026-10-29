# Flow Cadence ở trường

Cách chạy flow Genus → Conformal → GLS → Innovus trên server trường, tiêu chí nghiệm thu theo Lab 01-05 và các lỗi đã gặp. Tài liệu Lab gốc để trong Drive nhóm, không đưa lên repo công khai.

Trường không mở VPN nên Cadence chỉ chạy khi ngồi ở trường. Ở nhà chỉ làm RTL, mô phỏng và flow mã nguồn mở (`docs/setup_home.md`). Dồn việc Cadence vào các buổi lên trường và chuẩn bị script sẵn ở nhà.

## 1. Server và PDK

Kết quả HT-01 (21/10) nằm ở `appendix/server_check/`. Chạy lại khi cần bằng `make check-server`.

| Mục | Giá trị |
| --- | --- |
| Tool | Genus 21.1, Innovus 21.1, Conformal_Asic 24.1 (không có license Conformal_Ultra), Xcelium, Tempus và Voltus 23.1 |
| PDK | `~/PDK_GPDK45` (bản Lab trong home mỗi người) |
| Thư viện | `lib/slow_vdd1v0_basicCells.lib` (setup), `lib/fast_vdd1v0_basicCells.lib` (hold), `lef/gsclib045_tech.lef`, `lef/gsclib045_macro.lef` |
| Site và nguồn | `CoreSite`, net `VDD` và `VSS` |
| SRAM macro | `sram_2k_macro`, có LEF, `.lib`, model `.v`. Không có GDS và CDL, thầy xác nhận không cần (22/10). Chi tiết ở `docs/macro_notes.md` |
| GitHub | Server ra được GitHub, dùng `git pull` trực tiếp |

`pnr/scripts/config.tcl` tự dùng `~/PDK_GPDK45`. Chỉ cần `export PDK_DIR=...` khi PDK nằm chỗ khác.

## 2. Chạy cả flow accelerator

```bash
cd ~/rv32i-soc && git pull
( make synth-accel && make lec-accel && make gls-accel && make pnr-accel ) > full_run.txt 2>&1 &
grep -E 'Genus done|Compare Results|PASS|Innovus done|ERROR' full_run.txt   # xem tiến độ
```

Từng bước riêng:

| Lệnh | Làm gì | Kết quả |
| --- | --- | --- |
| `make synth-accel` | Genus, có clock gating | `syn/out_accel/` (netlist, SDC, `reports/`) |
| `CG=0 make synth-accel` | Genus không clock gating, để so công suất | Đổi tên `syn/out_accel` thành `syn/out_accel_cg0` trước khi chạy bản CG=1 |
| `make lec-accel` | Conformal theo `lec/accel_rtl2gate.do` | `syn/out_accel/lec.txt` |
| `make gls-accel` | Xcelium chạy `tb_accel_wrapper.v` trên netlist, không SDF | `syn/out_accel/gls/xrun.log` |
| `make pnr-accel` | Innovus theo `pnr/scripts/run_all.tcl` | `pnr/out_accel/`, database `DBS/*.enc` trong `pnr/run_accel/` |

Tổng hợp thử từng khối của SoC (STA-02), mỗi khối một lần chạy Genus riêng:

```bash
make synth-blocks > synth_blocks.txt 2>&1 &      # cả 10 khối, khối lỗi không làm dừng các khối sau
make synth-block B=sys_bus                       # một khối
make synth-block B=sram_wrap1                    # sram_wrap với 1 macro, để luyện flow macro
```

| Mục | Nội dung |
| --- | --- |
| Khối | `sys_bus`, `apb_bridge`, `dma_apb`, `imem_port`, `sram_wrap`, `timer_apb`, `uart_apb`, `gpio_apb`, `irqc_apb`, `accel_apb`. Lõi `rv32_core` tổng hợp riêng bằng `make synth-core` của Nhân (`docs/genus_core.md`) |
| Tham số | Theo mặc định của `soc_top` (1 master trên bus, mỗi bộ nhớ 16 KB) |
| SDC | Mỗi khối một file sinh tự động: clock 20 ns trên cổng clock của khối, uncertainty và IO delay theo tỉ lệ Lab, false path từ cổng reset |
| SRAM macro | `imem_port`, `sram_wrap` đọc thêm `~/PDK_GPDK45/lib/sram_2k_macro.lib` |
| Cấm scan flop | `SDFF*` bị `dont_use`, `use_scan_seqs_for_non_dft = false`. Sau tổng hợp đếm `SDFF*` trong netlist, khác 0 là `ERROR` |
| Kết quả | `syn/out_blocks/<khối>/` (netlist, SDC, `reports/`, `summary.txt`), tổng hợp ở `syn/out_blocks/summary.txt`, log ở `syn/run_blocks/<khối>/genus.log` |

Tiêu chí giống mục 3 (0 unresolved, 0 latch, 0 unconstrained endpoint, slack >= 0 ở 20 ns), thêm 0 scan flop. Copy `syn/out_blocks/` vào `appendix/synth_blocks/` và ghi số vào `docs/sta_results.md` mục 3.

Tổng hợp cả `soc_top` với `syn/constraints/soc.sdc`, lấy netlist cho `pnr/scripts/soc_floorplan.tcl` (PD-02, PD-03):

```bash
make synth-soc > synth_soc.txt 2>&1 &
```

| Mục | Nội dung |
| --- | --- |
| Tham số | Mặc định của `soc_top`: `ENABLE_M = 1`, `ENABLE_WFI_SLEEP = 1`, `ENABLE_DMA = 0`, lõi có BTB 8 entry |
| SRAM macro | Đọc thêm `~/PDK_GPDK45/lib/sram_2k_macro.lib`. Netlist phải có đúng 8 macro, khác 8 là `ERROR` |
| Cấm scan flop | Như `synth-blocks` |
| Kết quả | `syn/out_soc/` (`soc_top_netlist.v`, `soc_top_synth.sdc`, `soc_top.sdf`, `reports/`, `summary.txt`), log ở `syn/run_soc/genus.log` |

Tiêu chí giống `synth-blocks`. Copy `syn/out_soc/` vào `appendix/synth_soc/` và ghi một dòng vào `docs/sta_results.md` mục 1. Genus chỉ kiểm setup ở corner slow. Hold và removal trên mạng reset kiểm bằng Tempus (STA-03).

STA-03: quét chu kỳ tìm F_max, rồi chạy Tempus trên netlist Genus:

```bash
make synth-soc-sweep > sweep_soc.txt 2>&1 &      # PERIODS="20 18 16 15 14" (mặc định)
make synth-soc PERIOD=15                         # một chu kỳ, ghi vào syn/out_soc/
make sta-soc                                     # Tempus trên syn/out_soc/
```

| Mục | Nội dung |
| --- | --- |
| Chu kỳ | `synth_soc.tcl` thay dòng `set SOC_PERIOD` của `soc.sdc` bằng `PERIOD`, input và output delay max đổi theo (24% và 20% chu kỳ). SDC thật của mỗi lần chạy là `soc_run.sdc` trong thư mục kết quả |
| Kết quả quét | `syn/out_soc_sweep/p<chu kỳ>/` và bảng `syn/out_soc_sweep/summary.md` (WNS, chu kỳ nhỏ nhất, F_max ước lượng, diện tích). F_max = 1 / (chu kỳ - WNS), chỉ là ước lượng từ đường xấu nhất |
| Tempus | `sta/scripts/sta_soc.tcl`, corner theo `pnr/scripts/mmmc.view`: slow cho setup và recovery, fast cho hold và removal. Report ở `sta/run_soc/pre/`, tóm tắt ở `summary.txt`. Chưa chạy lần nào trên server |
| Sau route (STA-05) | `make sta-soc SPEF=<file> NETLIST=<file>`: đọc SPEF và dùng clock thật, report ở `sta/run_soc/spef/` |

Ở nhà xem xu hướng trước bằng `make sta-soc-nangate STA_PERIOD=<ns>` (Yosys, Nangate45, OpenSTA với `soc.sdc`, macro SRAM là hộp đen nên đường qua macro không được tính). Lần đầu tổng hợp khoảng 11 phút, các lần sau chỉ chạy lại OpenSTA. Số ở nhà ghi vào `docs/sta_results.md` mục 2, không đưa vào report.

Trước layout chưa có SPEF nên Tempus không tính delay dây, số lạc quan. Ghi mỗi chu kỳ một dòng vào `docs/sta_results.md` mục 1 và copy report vào `appendix/`.

Xem layout và chụp hình cho report:

```bash
cd pnr/run_accel && innovus
# Trong Innovus:
source DBS/cts.enc      # hoặc floorplan.enc, placement.enc, route.enc
```

Chụp floorplan và power grid, placement, cây clock (CCOpt Clock Tree Debugger), bảng timing.

## 3. Tiêu chí nghiệm thu

### Sau tổng hợp (`syn/out_accel/reports/`)

| Report | Đạt khi |
| --- | --- |
| `audit/pre_syn_unresolved.rpt`, `audit/pre_syn_design_lint.rpt` | 0 unresolved, 0 latch, 0 loop, 0 multi-driven |
| `audit/post_syn_design_lint.rpt` | 0 floating input, không còn assign |
| `audit/pre_syn_timing_intent.rpt` | 0 unconstrained endpoint |
| `synthesis/timing.rpt` | Slack >= 0 ở 20 ns |
| `synthesis/clock_gating.rpt` (bản CG=1) | Đa số flop được gate |
| `synthesis/power.rpt` | So hai bản CG=0 và CG=1 |
| `lec.txt` | 0 non-equivalent |
| `gls/xrun.log` | Dòng `PASS` giống mô phỏng RTL |

### Theo từng bước Lab

| Bước | Lệnh chính (theo Lab) | Tiêu chí | Script |
| --- | --- | --- | --- |
| Kiểm tra trước tổng hợp | `check_design -unresolved`, `check_design -all`, `check_timing_intent -verbose` | Như bảng trên | `syn/scripts/synth_accel.tcl` |
| Tổng hợp | `syn_generic`, `syn_map`, `syn_opt` (effort medium), `lp_insert_clock_gating` (trước elaborate), `lp_clock_gating_min_flops 4` | WNS >= 0, 0 max_transition, 0 max_capacitance | như trên |
| Kiểm tra sau tổng hợp | Thuộc tính `remove_assigns`, `check_design -all`, `write_hdl -mapped` | Không còn assign, 0 floating input | như trên |
| LEC | `lec -nogui -dofile ...` | 0 non-equivalent | `lec/accel_rtl2gate.do` |
| Floorplan | `floorPlan -site CoreSite -r 1.0 <util> 15 15 15 15`, `editPin` | | `pnr/scripts/run_all.tcl` bước 2 |
| Power plan | `addRing` M7/M8, `addStripe` M8 dọc và M7 ngang, `sroute`, `verifyGeometry` | 0 violation | bước 3 |
| Placement | `setPlaceMode`, `place_opt_design`, `checkPlace`, `checkCongestion`, `timeDesign -preCTS` | 0 unplaced, overlap, off-grid. Overflow < 0,5%. WNS >= 0 | bước 4 |
| CTS | `setDontUse CLKBUFX2`, buffer và inverter X3-X16, `target_skew 0.080`, `target_max_trans 0.150`, OCV và CPPR, NDR 2W2S cho clk, `ccopt_design`, `optDesign -postCTS [-hold]` | Skew <= 80 ps, latency < 0,8 ns, setup và hold WNS >= 0 | bước 5 |
| Route và signoff | `routeDesign`, `optDesign -postRoute`, `verify_drc`, `verifyConnectivity`, `verifyProcessAntenna` | 0 DRC, 0 lỗi kết nối, 0 antenna | bước 6 trở đi |

Database lưu theo tên Lab: `DBS/floorplan.enc`, `DBS/placement.enc`, `DBS/cts.enc`, `DBS/route.enc`.

## 4. Lưu kết quả vào repo

Chỉ copy report, không copy netlist, SPEF, SDF hay database:

```bash
mkdir -p appendix/synth_accel appendix/pnr_accel
cp -r syn/out_accel/reports/* appendix/synth_accel/
cp -r pnr/out_accel/reports/* appendix/pnr_accel/
git status --short          # không có .lib .lef .gds .spef .sdf
git add appendix && git commit -m "Add accelerator synthesis and P&R reports" && git push
```

Không bao giờ copy `.lib`, `.lef`, `.gds`, file SRAM macro hay file nào của GPDK45 ra khỏi server.

## 5. Bài học buổi 21/10

- Genus đọc RTL ở chế độ Verilog-2001: không khai báo `localparam` trong `generate`.
- `lp_insert_clock_gating` phải đặt trước `elaborate`. Lệnh `remove_assigns` đã bỏ, dùng thuộc tính cùng tên.
- Dofile LEC do Genus sinh đòi Conformal_Ultra nên không chạy được. Dùng `lec/accel_rtl2gate.do` (mẫu `run_lec_cg.do` của Lab 1) với `set flatten model -gated_clock` và `set compare effort high`.
- Thư viện fast tên `fast_vdd1v0_basicCells.lib` (C hoa). File `qrc/gpdk045.tch` của Lab không đọc được.
- `BUFX2` của gsclib045 là cell cao gấp đôi, phải cấm ở cả Genus và Innovus.
- Innovus 21.1 đổi tên nhiều tuỳ chọn (`setPlaceMode -place_...`, `add_ndr`, `verifyGeometry` không có `-type`).
- Genus và Innovus không ghi đè log mà tạo `genus.log1`, `genus.log2`. `make` đã xoá log cũ trước mỗi lần chạy.

Kết quả 21/10 (lõi accelerator cũ): LEC PASS, GLS PASS, DRC, connectivity và antenna 0 lỗi, setup +7,68 ns, hold +0,005 ns. Skew 113 ps vẫn vượt 80 ps vì 4 flop điều khiển không qua clock gating. Lõi đã đổi sang Lab 2 nên phải chạy lại cả flow.

## 6. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
| --- | --- | --- |
| Innovus báo IMPSP-9099 | Netlist có scan flop (SDFF*) | Script Genus không chèn scan. Nếu vẫn gặp, cấm SDFF bằng `set_dont_use` |
| LEC non-equivalent sau clock gating | Dofile không biết cell gating | Xem `syn/out_accel/lec.txt`, so cell gating trong netlist với thư viện `.v` |
| Hold vi phạm sau CTS | Chỉ tối ưu setup | `optDesign -postCTS -hold` với view fast |
| Skew lớn | Dùng CLKBUFX2, hoặc flop không qua clock gating | `setDontUse CLKBUFX2 true` trước `ccopt_design`. Thử giảm `lp_clock_gating_min_flops` |
| Không tìm thấy PDK | PDK không ở `~/PDK_GPDK45` | `export PDK_DIR=<đường dẫn>` hoặc sửa `pnr/scripts/config.tcl` |
| Genus không ra netlist | Lỗi khi đọc RTL | Xem `syn/run_accel/genus.log`, tìm dòng `Error` |

## 7. Quét PPA theo thử thách của Lab

| Lab | Quét tham số | Biến trong script |
| --- | --- | --- |
| 01 | Chu kỳ clock, có hoặc không clock gating | `create_clock -period` trong SDC và `CG=0 make synth-accel` |
| 02 | Core utilization 55 / 70 / 85% | `UTIL` trong `run_all.tcl` |
| 03 | Khoảng cách stripe 15 / 30 / 60 µm | `STRIPE_P` |
| 04 | Density screen, cell padding | Thêm `createDensityScreen`, `specifyCellPad` sau bước 4 |
| 05 | Target skew 20 / 80 / 150 ps, derate OCV, useful skew | `SKEW` và `set_timing_derate -early 0.90 -late 1.10 -cell_delay` |

Mỗi lần quét, lưu report vào `appendix/<bước>/<cấu hình>/` để làm bảng PPA trong report.
