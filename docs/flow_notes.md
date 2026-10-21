# Ghi chú flow Cadence theo các Lab (tóm tắt của nhóm)

Tóm tắt các quy ước và tiêu chí nghiệm thu từ Lab 01-05 để script đồ án làm giống Lab. Tài liệu Lab gốc để trong Drive nhóm, không đưa lên repo công khai.

## Cấu trúc thư mục Lab và PDK

- PDK nằm trong thư mục `PDK_GPDK45`: `lib/slow_vdd1v0_basiccells.lib` (corner setup, 1.0 V 125 C), `lef/gsclib045_tech.lef`, `lef/gsclib045_macro.lef`.
- Site cell chuẩn: `CoreSite`. Net nguồn: `VDD`, `VSS`.
- Repo dùng biến môi trường `PDK_DIR` trỏ tới thư mục này (xem `pnr/scripts/config.tcl`).

## Bước và tiêu chí nghiệm thu

| Bước | Lệnh chính (theo Lab) | Tiêu chí phải đạt | Script trong repo |
| --- | --- | --- | --- |
| Tổng hợp, kiểm tra trước | `check_design -unresolved`, `check_design -all`, `check_timing_intent -verbose` | 0 unresolved, 0 latch/loop/multi-driven, 0 unconstrained endpoint | `syn/scripts/synth_accel.tcl` |
| Tổng hợp | `syn_generic`, `syn_map`, `syn_opt` (effort medium), clock gating `lp_insert_clock_gating` (đặt trước elaborate), `lp_clock_gating_min_flops 4` (thuộc tính design) | WNS >= 0, 0 max_transition/max_capacitance | như trên |
| Tổng hợp, kiểm tra sau | `remove_assigns -all`, `check_design -all`, `write_hdl -mapped` | không còn assign, 0 floating input | như trên |
| LEC | `lec -nogui -dofile ...` | 0 non-equivalent | `syn/out_accel/rtl2gate.do` (Genus sinh ra) |
| Floorplan | `floorPlan -site CoreSite -r 1.0 <util> 15 15 15 15`, `editPin` | | `pnr/scripts/run_all.tcl` bước 2 |
| Power plan | `addRing` M7/M8, `addStripe` M8 dọc + M7 ngang, `sroute`, `verifyGeometry -type power` | 0 violation | bước 3 |
| Placement | `setPlaceMode`, `place_opt_design`, `checkPlace`, `checkCongestion`, `timeDesign -preCTS` | 0 unplaced/overlap/off-grid, overflow < 0.5%, WNS >= 0 | bước 4 |
| CTS | `setDontUse CLKBUFX2`, buffer/inverter X3-X16, `target_skew 0.080`, `target_max_trans 0.150`, OCV + CPPR, NDR 2W2S cho clk, `ccopt_design`, `optDesign -postCTS [-hold]` | skew <= 80 ps, latency < 0.8 ns, setup/hold WNS >= 0 | bước 5 |

Database lưu theo tên Lab: `DBS/floorplan.enc`, `DBS/placement.enc`, `DBS/cts.enc` (thêm `DBS/route.enc`).

## Thử thách PPA trong Lab dùng lại cho điểm cộng đồ án

| Lab | Quét tham số | Biến trong script |
| --- | --- | --- |
| 01 | Chu kỳ clock, có/không clock gating | sửa `create_clock -period` trong SDC và `CG=0 make synth-accel` |
| 02 | Core utilization 55 / 70 / 85% | `UTIL` trong `run_all.tcl` |
| 03 | Khoảng cách stripe 15 / 30 / 60 um | `STRIPE_P` |
| 04 | Density screen, cell padding | thêm `createDensityScreen`, `specifyCellPad` sau bước 4 |
| 05 | Target skew 20 / 80 / 150 ps, derate OCV, useful skew | `SKEW` và `set_timing_derate -early 0.90 -late 1.10 -cell_delay` |

Mỗi lần quét, lưu báo cáo vào `appendix/<bước>/<cấu hình>/` để làm bảng PPA trade-off trong report.

## Accelerator Lab 2 (đề Lab 01)

Systolic array 4x4, 16 PE. Mỗi PE có bộ nhân 8x8, bộ cộng tích luỹ 20 bit, 2 thanh ghi pipeline 8 bit truyền ngang/dọc. Top của Lab là `accelerator_top` (file `pe.v`, `accelerator_top.v`), chân `a_row*`, `b_col*`, `res_out*`, `busy`, `done`. Wrapper của đồ án (`rtl/accel/accel_wrapper.v`) đang dùng mô hình thay thế cùng cấu trúc. Khi ghép code Lab thì nối theo các chân này.
