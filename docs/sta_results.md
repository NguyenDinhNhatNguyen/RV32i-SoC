# Kết quả STA của SoC

Bảng tóm tắt các lần chạy STA của `soc_top` (STA-01 đến STA-06). Chỉ ghi con số và đường dẫn tới report gốc trong `appendix/`. Giải thích SDC ở `docs/soc_top.md` mục 4.7.

Số liệu ở trường (GPDK45, Genus, Tempus) là số chính thức cho report. Số liệu ở nhà (Nangate45, Yosys, OpenSTA) chỉ để xem xu hướng.

## Cách ghi

- Slack tính bằng ns. WNS là slack xấu nhất, TNS là tổng các slack âm.
- Setup và hold là nhóm `clk`. Recovery và removal là nhóm đường reset bất đồng bộ.
- Diện tích là cell chuẩn, chưa tính 8 macro SRAM (64 000 µm²), trừ khi ghi rõ.
- Mỗi lần chạy có giữ report một dòng, thêm ở cuối bảng.

## 1. Ở trường (chính thức)

Chung cho mọi dòng: Genus 21.10, Tempus 23.14, cell chuẩn corner slow 0,9 V 125 °C cho setup và recovery, fast cho hold và removal. `sram_2k_macro.lib` chỉ có corner typical nên đường qua macro hơi lạc quan. Chu kỳ 20 ns, BTB 8 entry. Các dòng 29/10 đến 31/10 có `ENABLE_DMA = 0`, chưa có SPI, PWM, I2C. Dòng 12/11 theo mặc định hiện tại của `soc_top`: DMA, SPI, PWM, I2C đều bật. Unconstrained bằng 0 ở mọi lần.

| Ngày | Netlist | Flop / ICG | Setup | Hold WNS (số đường) | Recovery | Removal | Diện tích | Report gốc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29/10 | Genus đầu tiên | 3574 / 112 | +2,179 | Chưa kiểm | Chưa kiểm | Chưa kiểm | 52 757 | `appendix/synth_soc/` |
| 30/10 | Giữ flop cho LEC | 3663 / 115 | +2,071 | -0,147 (1080) | -25,261 | +7,022 | 53 408 | `appendix/synth_soc_keepflop/`, `appendix/sta_soc/` |
| 31/10 | Mạng reset có buffer, cấm `CLKBUFX2`, giao cho PnR | 3663 / 115 | +2,392 | -0,147 (1081) | +18,292 | +0,006 | 53 889 | `appendix/synth_soc_reset/`, `appendix/sta_soc_reset/` |
| 12/11 | Có DMA, SPI, PWM, I2C (commit `eced27a`), giao cho PnR | 4079 / 137 | +0,529 | -0,143 (1241) | +18,281 | +0,028 | 58 843 | `appendix/synth_soc_i2c/`, `appendix/sta_soc_i2c/` |

Setup ở dòng 29/10 là số của Genus, các dòng sau là số của Tempus. Genus và Tempus chênh dưới 0,04 ns.

Ghi chú:
- Đường găng setup: từ CLK của macro IMEM qua bộ cộng ALU (so sánh nhánh) tới `u_core.if_pc_q_reg[31]`, đúng như dự đoán ở `docs/spec/core.md` mục 4.5.
- Mạng reset: Genus mặc định coi chân set/reset bất đồng bộ là ideal (`ideal_seq_async_pins`), nên ở lần 29/10 và 30/10 flop `u_rst_sync_q_reg` lái thẳng khoảng 3500 chân, recovery âm khoảng 25 ns. Từ 31/10, `soc.sdc` có `set_max_transition 0.5`, `set_max_fanout 32` và `synth_soc.tcl` đặt `ideal_seq_async_pins false`. Flop chỉ còn lái 7 cell đảo đầu cây buffer.
- Removal 31/10 chỉ dư 6 ps (chân `RN` của `u_imem.rom_sel_q_reg`). 12/11 dư 28 ps (chân `RN` của một flop tag trong BTB). Sau route thử 12/11 (PD-04, Tempus) dư 29 ps, xem `docs/pnr_soc_status.md` mục 4. Layout thử u70 ngày 14/11 dư 33 ps (mục 6). Kiểm lại trên layout chính thức (STA-05).
- 12/11: setup còn +0,529 ns (31/10 là +2,392), cùng đường găng IMEM → ALU → `if_pc_q_reg[31]`. Ở 20 ns Genus chỉ tối ưu tới khi đạt, nên số này không cho biết F_max. F_max phải quét lại (mục 4) sau RTL freeze. Sau route thử 12/11 ở 20 ns, setup chỉ còn +0,007 ns (Tempus) và −0,027 ns (Innovus), nên STA-04 tổng hợp ở chu kỳ chặt hơn để layout còn biên.
- 12/11: 3881/4079 flop (95,2%) qua clock gating. Genus báo 0 vi phạm max_transition, max_capacitance, max_fanout, 0 assign, 0 `CLKBUFX2`.
- Hold vi phạm ở chân `CEN` của macro IMEM và các cặp flop nối thẳng, vì trước CTS clock còn lý tưởng. Innovus sửa bằng `optDesign -postCTS -hold`.
- Giữ flop (như `synth_core.tcl`, D-042) thêm 89 flop, diện tích +0,56%.
- Tempus báo 242 endpoint unconstrained, đều vô hại: chân `SE` của cell clock gating (nối cố định vì không có scan) và chân `RN` của 6 flop (2 flop `reset_sync` do false path `rst_n`, 4 flop hằng được giữ lại). Mỗi chân đếm 2 lần (view setup và hold). Ngày 12/11 là 298 = 274 chân `SE` (137 ICG) và 24 chân `RN` (12 flop), cùng hai loại trên.
- Genus lint chỉ báo false path từ `rst_n` "no effect", vì Genus không tính đường vào chân reset bất đồng bộ. Exception vẫn có tác dụng trong Tempus.

## 2. Ở nhà (chỉ xem xu hướng)

OpenSTA 3.1 với Nangate45 typical, netlist Yosys (`make sta-soc-nangate`), macro SRAM là hộp đen nên đường qua macro không được tính. Chu kỳ 20 ns.

| Ngày | Netlist | Setup | Hold | Recovery | Removal | Diện tích |
| --- | --- | --- | --- | --- | --- | --- |
| 26/10 | Kiểm `soc.sdc` (STA-01) | +14,994 | +0,004 | +4,909 | -2,561 | 51 955 |
| 29/10 | BTB 8 entry | +14,994 | +0,004 | +2,279 | -2,983 | 56 719 |
| 07/11 | Có SPI, PWM | +14,925 | +0,004 | +1,517 | -3,105 | 58 648 |
| 07/11 | Có SPI, PWM, DMA bật mặc định | +14,880 | +0,004 | +0,529 | -3,264 | 60 426 |
| 10/11 | Có SPI, PWM, DMA, I2C (4 chân mới) | +14,897 | +0,004 | +0,157 | -3,324 | 61 561 |

Removal âm vì Yosys không buffer mạng reset (cùng nguyên nhân như mục 1). Setup tốt vì đường găng qua macro không được tính.

## 3. Tổng hợp từng khối trên Genus (STA-02, ở trường)

Chạy bằng `make synth-blocks` (`syn/scripts/synth_block.tcl`), clock gating bật, chu kỳ 20 ns. Lõi `rv32_core` dùng flow riêng của Nhân (`make synth-core`, `docs/genus_core.md`). Diện tích của `imem_port`, `sram_wrap` gồm cả macro.

| Ngày | Khối | Diện tích (µm²) | Flop | ICG | Setup WNS (ns) | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- |
| 29/10 | `sys_bus` | 585,2 | 3 | 0 | +9,562 | |
| 29/10 | `apb_bridge` | 1 435,0 | 94 | 4 | +13,713 | |
| 29/10 | `dma_apb` | 2 318,8 | 191 | 7 | +9,524 | Bật mặc định trong `soc_top` từ 07/11 |
| 29/10 | `imem_port` | 33 649,8 | 38 | 1 | +10,044 | 4 macro, logic 1 649,8 |
| 29/10 | `sram_wrap` | 32 725,5 | 5 | 0 | +10,556 | 4 macro, logic 725,5 |
| 29/10 | `timer_apb` | 2 110,1 | 130 | 3 | +9,728 | |
| 29/10 | `uart_apb` | 2 165,9 | 223 | 28 | +9,321 | |
| 29/10 | `gpio_apb` | 1 293,1 | 128 | 2 | +9,968 | |
| 29/10 | `irqc_apb` | 105,0 | 6 | 1 | +10,125 | |
| 29/10 | `accel_apb` | 15 283,3 | 792 | 14 | +9,209 | |
| 29/10 | `sram_wrap1` | 8 298,6 | 3 | 0 | +10,556 | 1 macro, để luyện flow macro |
| 12/11 | `spi_apb` | 682,6 | 58 | 5 | +9,624 | RTL-13 |
| 12/11 | `pwm_apb` | 1 377,6 | 98 | 2 | +9,827 | RTL-13 |
| 12/11 | `i2c_apb` | 882,7 | 69 | 7 | +9,890 | RTL-14, sau khi đưa `localparam` ra ngoài `generate` |

Mọi khối đạt tiêu chí: 0 scan flop, 0 latch, 0 unconstrained, setup ≥ 0. Ba khối 12/11 có report trong `appendix/synth_blocks/<khối>/`. Chạy lại 30/10 sau khi thêm driving cell cho cổng reset: số liệu không đổi, lint sạch. Report trong `appendix/synth_blocks/` là của lần này (trừ `sram_wrap1`).

## 4. Quét chu kỳ trên Genus (STA-03, ở trường)

`make synth-soc-sweep`. Đây là setup sau tổng hợp: chưa có delay dây, skew clock, macro dùng `.lib` typical. Report ở `appendix/synth_soc_sweep/p<chu kỳ>/`.

| Chu kỳ (ns) | Tần số (MHz) | WNS | Diện tích gồm macro (µm²) | Đường găng |
| --- | --- | --- | --- | --- |
| 20 | 50 | +2,179 ns | 116 757 | IMEM → ALU → `if_pc_q` |
| 18 | 56 | +0,632 ns | 116 738 | |
| 16 | 63 | +0,273 ns | 116 758 | |
| 14 | 71 | +0,027 ns | 116 877 | |
| 13 | 77 | +3,5 ps | 117 044 | |
| 12 | 83 | +1,9 ps | 117 164 | |
| 11 | 91 | +0,5 ps | 117 317 | |
| 10 | 100 | +6,3 ps | 117 293 | |
| 8 | 125 | +0,2 ps | 118 560 | IMEM → bộ nhân `u_muldiv` |
| 6 | 167 | +0,3 ps | 119 789 | IMEM → `if_pc_q` |
| 5 | 200 | 0 (0 đường vi phạm) | 124 406 | DMEM → `if_pc_q` |
| 4 | 250 | -0,693 ns | 130 738 | IMEM → `if_pc_q` |

Từ 20 tới 6 ns là netlist 29–30/10 (trước khi giữ flop). 5 và 4 ns là netlist cuối 31/10.

Kết luận:
- **F_max sau tổng hợp khoảng 200 MHz.** Đường găng luôn nằm trong lõi, từ macro qua so sánh nhánh tới `if_pc_q`.
- Diện tích tăng chậm tới 10 ns (+0,46%), rồi tăng nhanh: +5,5% ở 5 ns, +10,9% ở 4 ns. Tần số chốt ở STA-04 nên để dư nhiều so với 200 MHz.
- Quét lại trên RTL đầy đủ (đã hoàn thành 14/11), xem bảng dưới. Tempus ở chu kỳ chọn: mục 5.

### Quét lại 14/11 trên RTL đầy đủ

Netlist cùng RTL với dòng 12/11 ở mục 1 (DMA, SPI, PWM, I2C, BTB 8 entry). `make synth-soc-sweep PERIODS="10 9 5 4.5"`. Report ở `appendix/synth_soc_sweep_1411/`. Cả bốn chu kỳ có 0 lỗi trong log Genus, 0 vi phạm max_transition, max_capacitance, max_fanout.

| Chu kỳ (ns) | Tần số (MHz) | WNS | Flop / ICG | Cell chuẩn (µm²) | Gồm macro (µm²) | Đường găng |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 100 | +3,7 ps | 4079 / 137 | 59 624 | 123 624 | IMEM → `if_pc_q` |
| 9 | 111 | +0,7 ps | 4068 / 136 | 60 188 | 124 187 | `u_muldiv` → `wb_result_q` |
| 5 | 200 | 0 (0 đường vi phạm) | 4068 / 136 | 65 708 | 129 708 | IMEM → `if_pc_q` |
| 4,5 | 222 | -0,208 ns | 4068 / 136 | 70 722 | 134 722 | IMEM → chân `CEN` của macro IMEM |

Kết luận:
- **F_max sau tổng hợp vẫn khoảng 200 MHz** trên RTL đầy đủ, như lần 31/10.
- Cell chuẩn ở 9 ns tăng 0,95% so với 10 ns và 2,3% so với 58 843 µm² ở 20 ns (12/11).
- Từ 9 ns trở xuống Genus xóa thêm khoảng 10 flop có đầu vào hằng mà ở 10 ns còn giữ: số chân tuần tự nối hằng trong `post_syn_design_lint.rpt` giảm từ 12 xuống 2, số clock gating giảm 1. Chức năng không đổi, nhưng LEC trên netlist 9 ns phải chấp nhận các flop hằng đã bị xóa.

## 5. Chọn chu kỳ (STA-04, ở trường, chưa chốt)

Phương án đang xét: tổng hợp và PnR ở 9 ns, signoff Tempus ở 10 ns (100 MHz). Netlist tổng hợp ở chu kỳ chặt hơn để layout còn biên khi có delay dây và skew clock. Ngày 14/11 chạy Tempus trước layout (clock lý tưởng) trên netlist của mục 4. Report ở `appendix/sta_soc_p9/`.

| Netlist | SDC | Setup WNS (số đường vi phạm) | Hold WNS (số đường) | Recovery | Removal |
| --- | --- | --- | --- | --- | --- |
| 9 ns | 9 ns | -0,022 (31) | -0,141 (1201) | +7,677 | +0,020 |
| 9 ns | 10 ns | **+0,978 (0)** | -0,141 (1201) | +8,677 | +0,020 |
| 10 ns | 10 ns | -0,009 (1) | -0,143 (1222) | +8,712 | +0,011 |

Ghi chú:
- Netlist 9 ns đem kiểm ở 10 ns dư gần 1 ns setup. Netlist 10 ns ở 10 ns đã âm 9 ps ngay trước PnR. Đường găng vẫn là IMEM → `if_pc_q`.
- Tempus bi quan hơn Genus khoảng 0,02 ns ở cùng chu kỳ, cùng mức chênh như mục 1.
- Hold không xấu đi khi siết chu kỳ: 1201 đường (mốc 12/11 là 1241). Đây là hold trước CTS, Innovus sửa sau CTS. Nhóm clock gating có 1 đường hold -0,006 ns, cũng do clock lý tưởng.
- `check_timing`: no_drive 76 như 12/11. Unconstrained 278 = 272 chân `SE` (136 ICG) và 6 chân `RN`, ít hơn 298 của 12/11 vì netlist 9 ns có ít flop hằng hơn (mục 4).
- Độ rộng xung của macro: `sram_2k_macro.lib` có `min_pulse_width` 0,45 ns, coverage báo 0 vi phạm PulseWidth, nên macro không chặn 9 ns.
- Còn lại trước khi chốt: PnR thử ở 9 ns trên lõi 420 µm (PD-07) và Tempus sau layout ở 10 ns. Chu kỳ và cỡ lõi chốt cùng với PnR.

### Có và không có clock gating (14/11, 9 ns)

Cùng RTL, cùng chu kỳ 9 ns, chỉ khác `CG`. CG=1 là netlist p9 của mục 4, CG=0 chạy riêng vào `syn/out_soc_cg0_p9` (không đụng `syn/out_soc`). Report CG=0 ở `appendix/synth_soc_cg0_p9/`. Cả hai lần: 0 lỗi Genus, 0 DRV, 4068 flop, 0 scan flop, 0 latch.

| Chỉ số | CG=0 | CG=1 | Chênh lệch |
| --- | --- | --- | --- |
| WNS | +1,6 ps | +0,7 ps | Cả hai đạt |
| Cell chuẩn (µm²) | 66 337 | 60 188 | **−9,3%** |
| Logic (µm²) | 39 730 | 32 687 | −7 043 |
| Flop (µm²) | 25 022 | 25 355 | +333 |
| ICG | 0 | 136 (884 µm²) | |
| Flop được gate | 0 | 3880/4068 (95,4%) | |

Công suất Genus (mW), activity mặc định:

| Nhóm | CG=0 | CG=1 | Chênh lệch |
| --- | --- | --- | --- |
| Flop | 1,400 | 0,361 | −74% |
| Logic | 0,617 | 0,345 | −44% |
| Clock (ICG) | 0 | 0,065 | |
| Macro | 0,045 | 0,045 | Không đổi |
| **Tổng** | **2,062** | **0,817** | **−60,4%** |

Ghi chú:
- Diện tích giảm vì flop có enable không cần mux hồi tiếp nữa: 136 ICG thay cho khoảng 3 900 mux.
- Phần giảm lớn nhất là công suất internal của flop (1,361 xuống 0,347 mW), vì flop không nhận clock khi giữ giá trị. Leakage gần như không đổi (0,011 mW).
- Trước CTS chưa có cây clock thật, nên công suất mạng clock chưa tính ở cả hai bản. Sau CTS clock gating còn tiết kiệm thêm phần cây clock phía sau ICG.
- Số công suất chỉ để so CG=0 và CG=1. Công suất theo testcase là PWR-01.
- Nếu chu kỳ chốt khác 9 ns thì chạy lại phép so này ở chu kỳ đó.

## 6. Sau layout (STA-05, ở trường)

Tempus đọc netlist, SPEF của Innovus và SDC do Genus ghi (`syn/out_soc/soc_top_synth.sdc`). Corner RC typical, clock propagated.

| Ngày | Layout | Chu kỳ | Setup | Hold | Recovery | Removal | Report gốc |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 14/11 | `pnr/out_soc_u70`, lõi 420 × 420,7 µm (PD-07, netlist 12/11) | 20 ns | +0,190 | +0,014 | +17,817 | +0,033 | `appendix/sta_soc_u70/` |

Ghi chú:
- Đây là lần chạy thử, chưa phải layout chính thức. Số của Tempus lệch Innovus dưới 0,03 ns. Coverage: 0 vi phạm hold, unconstrained 298 như trước layout.
- Đường găng setup vẫn là IMEM → `if_pc_q_reg[31]`. Removal xấu nhất ở chân `RN` của `minstret_q_reg[38]` trong CSR.
- Tempus báo `SPEF-1152` ở net `i2c_scl_i`: net này trong SPEF thiếu kết nối so với netlist, Tempus nối phần thiếu bằng RC rất nhỏ. Chỉ ảnh hưởng đường vào I2C (đi qua bộ đồng bộ). Báo phía PnR kiểm lại pin của port này.
- Không chạy được trên `pnr/out_soc` (lõi 405 µm) vì `soc_top_pnr.v` đã bị xóa khi chạy lại ngày 13/11.
