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
- Removal 31/10 chỉ dư 6 ps (chân `RN` của `u_imem.rom_sel_q_reg`). 12/11 dư 28 ps (chân `RN` của một flop tag trong BTB). Phải kiểm lại sau CTS và sau route (STA-05).
- 12/11: setup còn +0,529 ns (31/10 là +2,392), cùng đường găng IMEM → ALU → `if_pc_q_reg[31]`. Ở 20 ns Genus chỉ tối ưu tới khi đạt, nên số này không cho biết F_max. F_max phải quét lại (mục 4) sau RTL freeze.
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
- Còn lại: quét lại trên RTL đã freeze sau review 8/11 (có SPI, PWM, DMA và BTB 8 entry), chạy Tempus ở chu kỳ chọn.
