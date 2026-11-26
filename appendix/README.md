# Phụ lục

Report và log chính thức copy từ server để đưa vào report. Mỗi bước một thư mục:

| Thư mục | Nội dung |
| --- | --- |
| `server_check/` | Kết quả kiểm tra server (HT-01) |
| `synth_accel/` | Genus cho accelerator, `cg0` không clock gating và `cg1` có clock gating, kèm LEC và GLS |
| `synth_blocks/` | Genus tổng hợp thử từng khối của SoC (STA-02), mỗi khối một thư mục và `summary.txt` |
| `synth_soc/` | Genus cho cả `soc_top` với `soc.sdc`, report và `summary.txt` (29/10) |
| `synth_soc_keepflop/` | Genus `soc_top` giữ mọi flop cho LEC (30/10), mạng reset chưa có buffer |
| `synth_soc_sweep/` | Quét chu kỳ Genus `soc_top` (STA-03), mỗi chu kỳ một thư mục `p<ns>` |
| `sta_soc/` | Tempus trước layout của `soc_top` (STA-03): setup, hold, recovery, removal, coverage |
| `synth_soc_reset/`, `sta_soc_reset/` | Genus và Tempus `soc_top` ngày 31/10, mạng reset có buffer |
| `synth_soc_i2c/`, `sta_soc_i2c/` | Genus và Tempus `soc_top` ngày 12/11, có DMA, SPI, PWM, I2C, netlist giao cho PnR |
| `synth_soc_sweep_1411/` | Quét chu kỳ Genus `soc_top` ngày 14/11 trên RTL đủ DMA, SPI, PWM, I2C (STA-03): 10, 9, 5, 4,5 ns và `summary.md`. `p10`, `p9` có thêm `post_syn_design_lint.rpt` |
| `synth_soc_cg0_p9/` | Genus `soc_top` không clock gating ở 9 ns (STA-04, 14/11), để so với `synth_soc_sweep_1411/p9` |
| `synth_soc_e60437a/`, `sta_soc_e60437a/` | Genus và Tempus của netlist chính thức STA-04 (14/11, RTL `e60437a`): Genus 9 ns, Tempus trước layout với SDC 10 ns (`sdc_10`, signoff) và 9 ns (`sdc_9`), kèm `soc_10ns.sdc` |
| `sta_soc_p9/` | Tempus trước layout ngày 14/11 (STA-04): netlist 9 ns với SDC 9 ns và 10 ns, netlist 10 ns với SDC 10 ns, gộp ở `summary.txt` |
| `sta_soc_u70/` | Tempus sau layout trên `pnr/out_soc_u70` (STA-05 chạy thử, 14/11), lõi 420 × 420,7 µm, 20 ns, kèm `tempus.log` |
| `core_signoff/` | Genus, LEC và GLS cho core `rv32_core` (D-042) |
| `pnr_accel/` | Innovus cho accelerator: timing từng bước, DRC, connectivity, antenna, công suất |
| `pnr_soc/` | Innovus cho `soc_top` (PD-04, 12/11 và 13/11), lõi 405 × 405,3 µm, `slack_summary.txt` và `pd_checks.rpt` |
| `pnr_soc_p9/` | Innovus `soc_top` trên netlist chính thức STA-04 (18/11, lõi 420 µm, SDC 9 ns), `eco/` là report sau ECO của Phát |
| `pnr_soc_p9/vssfix/`, `pnr_soc_p9/trim/` | PD-08 (26/11): kiểm connectivity, DRC, antenna sau khi sửa lưới `VSS`, skew cây clock cuối |
| `pnr_soc_p9/eco/scripts/`, `pnr_soc_p9/innovus_p9.log` | Script ECO 18/11 và log Innovus của lần chạy `_p9` (đã bỏ dòng license) |
| `pnr_soc_p9_412/`, `pnr_soc_p9_430/` | PD-07 (26/11): hai cỡ lõi khác trên netlist chính thức |
| `power_soc_post/` | PWR-02 (26/11): công suất sau layout của 8 testcase |
| `sta_soc_p9_trim/` | Tempus 4 view ở 10 ns trên layout cuối (26/11) |
| `sta_soc_p9_post/` | Tempus sau layout `_p9` (sau ECO, 18/11): `sdc_10` là signoff 100 MHz, `sdc_9` để đối chiếu, kèm `tempus.log` |
| `sta_soc_p9_sta05/` | STA-05 trên layout `_p9` (19/11): sau CTS và sau route với 4 view (`VIEWS=cross`), lần trước khi sửa SDC (`route_10_cross_before_fix`), F_max sau layout ở 9, 8,5, 8 ns, kèm `soc_10ns.sdc` mới |
| `synth_picorv32/` | Genus PicoRV32 (`ref/picorv32`, 3 cấu hình mặc định, I, IM) cùng flow với các khối, để so với `rv32_core` (EVA-02, 19/11) |
| `synth_blocks_e60437a/` | Genus từng khối `uart_apb`, `spi_apb`, `i2c_apb` trên RTL `e60437a` (14/11) |
| `pnr_soc_u75/`, `pnr_soc_u70/`, `pnr_soc_u65/` | Innovus `soc_top` ở ba cỡ lõi khác (PD-07, 13/11), có `drc_after_eco.rpt` khi ECO sửa DRC |
| `macro_check/` | Thông tin macro `sram_2k_macro` đọc từ LEF và `.lib` trên server (29/10, 30/10) |
| `lec_soc/` | Conformal LEC của `soc_top`: `run2/` (LEC-01, netlist 12/11), `run3/` và `run4_seqfb/` (LEC-02, netlist chính thức 14/11, 20/11), `run5_seqeff/` (LEC-02 với `SEQ_EFFORT=high`, 25/11), `g2g/` (LEC-03, netlist tổng hợp với netlist sau layout, 20/11). `apb_bridge/` là LEC riêng khối (14/11) |
| `lec_soc/g2g_lec05/` | LEC-05 (26/11): netlist tổng hợp với netlist layout cuối `route_trim`, 4078 Equivalent, `PASS` |
| `ir_drop_trim/` | LEC-06 (26/11): IR drop tĩnh VDD trên layout cuối `route_trim`, `act0.1/` và `act0.5/`, 0 vi phạm |
| `lint_hal/` | HAL lint của `soc_top` trên main `7008da2` (VER-03, 13/11): `summary.txt` và `xrun.log` |
| `ver05_regress/` | `make regress` và `make cov-soc` ngày 17/11 trên `3289802` (VER-05): bảng regression, coverage theo module, 74 lần chạy Verilator |
| `gls_soc/` | `make gls-soc` ngày 19/11 trên server (VER-07): netlist Genus STA-04, Xcelium, zero delay, 71/71 PASS, đường dẫn 8 macro |
| `gls_soc_sdf/` | `make gls-soc-sdf` ngày 26/11 trên server (VER-08): netlist và SDF sau ECO của `_p9`, 10 ns, 71/71 PASS, tóm tắt cảnh báo SDF khi elaborate |
| `gls_soc_sdf_minmax/` | `make gls-soc-sdf-minmax` ngày 26/11 trên server (VER-09): góc `max/` và `min/`, mỗi góc 71/71 PASS, `tempus_sdf.txt` là log ghi SDF hold |
| `power_soc_pre/` | Công suất Genus trước layout (PWR-01, 26/11): mỗi testcase một thư mục (`power.rpt`, `power_hier.rpt`, `activity.txt`), trường hợp `default` là toggle mặc định, bảng ở `summary.md` |
| `ver06_bench/` | Output `make bench-core` và `make bench-soc` ngày 12/11 (VER-06), chạy ở nhà trong Docker |

Chỉ đưa report dạng văn bản. Không đưa netlist, SPEF, SDF, database hay file nào của GPDK45.
