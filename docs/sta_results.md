# Kết quả STA của SoC

Bảng tóm tắt các lần chạy STA của `soc_top`, mỗi lần một dòng, để dễ so sánh và theo dõi việc đóng timing (STA-01 đến STA-06). Chỉ ghi con số và đường dẫn tới report gốc. Giải thích SDC ở `docs/soc_top.md` mục 4.7, report gốc của server ở `appendix/`.

Số liệu ở trường (GPDK45, Genus, Tempus) là số chính thức cho report. Số liệu ở nhà (Nangate45, Yosys, OpenSTA) chỉ để xem xu hướng, không đưa vào report.

## Cách ghi

- Slack tính bằng ns. WNS là slack xấu nhất, TNS là tổng các slack âm (0 khi không có vi phạm).
- Setup và hold là nhóm `clk` (đường từ flop, cổng vào tới flop, cổng ra). Recovery và removal là nhóm đường reset bất đồng bộ.
- Unconstrained là số endpoint thiếu ràng buộc. Tiêu chí của Lab là 0.
- Diện tích là cell chuẩn, chưa tính 8 macro SRAM, tính bằng µm².
- Thêm dòng mới ở cuối bảng, không sửa dòng cũ. Kết quả sai thì ghi thêm dòng mới và giải thích ở cột Ghi chú.

## 1. Ở trường (chính thức)

| Ngày | Bước | Tool, thư viện, corner | Netlist | SDC, chu kỳ | Setup WNS / TNS | Hold WNS / TNS | Recovery WNS | Removal WNS | Unconstrained | Diện tích | Report gốc | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29/10 | Genus `soc_top` (chạy sớm cho PD-02, PD-03) | Genus 21.10-p002_1, slow 0,9 V 125 °C, macro typical | `make synth-soc`, CG=1, `ENABLE_DMA = 0`, BTB 8 entry | `soc.sdc`, 20 ns | +2,179 / 0 | Chưa kiểm | Chưa kiểm | Chưa kiểm | 0 | 52 757 (116 757 gồm 8 macro) | `appendix/synth_soc/` | Xem dưới bảng |

Ghi chú lần chạy 29/10 (`soc_top`):
- Đạt: 8 macro, 0 scan flop, 0 latch, 3574 flop, 112 ICG, 0 unresolved, 0 assign sau tổng hợp. Không có vi phạm max transition và max capacitance, nên mạng reset từ `reset_sync` (fanout khoảng 2900) đã được chèn buffer.
- Đường găng: từ CLK của macro IMEM qua bộ cộng của ALU (so sánh nhánh) tới `u_core.if_pc_q_reg[31]`, dài 17,57 ns. Đúng đường dự đoán ở `docs/spec/core.md` mục 4.5 và `docs/timing_core.md`.
- `sram_2k_macro.lib` chỉ có corner typical (1,0 V, 25 °C), còn cell chuẩn ở corner slow (0,9 V, 125 °C). Đường qua macro vì vậy hơi lạc quan.
- Timing của macro theo `.lib` (không đổi theo slew): CLK→Q 1,20 ns (slew ra 0,10 ns), setup `CEN` và `WEN` 0,40 ns, `A` 0,35 ns, `D` 0,30 ns, hold mọi chân vào 0,20 ns, độ rộng xung CLK tối thiểu 0,45 ns, slew vào tối đa 0,25 ns.
- Lint timing chỉ báo 1 mục: false path từ `rst_n` "no effect", vì Genus không tính đường vào chân reset bất đồng bộ. Exception vẫn giữ cho Tempus và Innovus.
- Genus không kiểm hold, recovery và removal. Ba số này lấy bằng Tempus ở STA-03.

## 2. Ở nhà (chỉ xem xu hướng)

| Ngày | Bước | Tool, thư viện | Netlist | SDC, chu kỳ | Setup WNS / TNS | Hold WNS / TNS | Recovery WNS | Removal WNS / TNS | Unconstrained | Diện tích | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 26/10 | STA-01 | OpenSTA 3.1, Nangate45 typical | Yosys 0.70 (`syn/yosys/synth_nangate.tcl`), macro SRAM hộp đen, `ENABLE_DMA = 0` | `soc.sdc`, 20 ns | +14,994 / 0 | +0,004 / 0 | +4,909 | -2,561 / -7 465 | 0 | 51 955 | Xem dưới bảng |
| 29/10 | Chuẩn bị STA-03 (`make sta-soc-nangate`) | OpenSTA 3.1, Nangate45 typical | Yosys 0.70 (`syn/yosys/synth_nangate.tcl`), macro SRAM hộp đen, `ENABLE_DMA = 0`, BTB 8 entry | `soc.sdc`, 20 ns | +14,994 / 0 | +0,004 / 0 | +2,279 | -2,983 / -10 221 | 0 | 56 719 | Diện tích tăng 4 764 µm² so với 26/10 do BTB 8 entry (bật mặc định từ 27/10). Mạng reset chưa buffer nay lái 3428 chân nên recovery giảm, removal âm hơn, cùng nguyên nhân như 26/10. Đường setup xấu nhất là `gpio_i` → flop vì đường qua macro không được tính |

Ghi chú lần chạy 26/10 (STA-01):
- Mục đích là kiểm `soc.sdc`: OpenSTA đọc không lỗi, `check_setup -verbose` không báo gì. Nhóm `clk` có 3127 endpoint, nhóm reset có 2917 endpoint.
- Removal âm ở cả 2917 chân reset là do netlist ở nhà, không phải do SDC. Một flop của `reset_sync` lái thẳng 2917 chân reset, Yosys không chèn buffer nên slew lên 11,75 ns và thời gian removal bị ngoại suy thành 14,9 ns. Genus và Innovus sẽ chèn buffer cho mạng này.
- Setup tốt vì đường qua macro SRAM chưa được tính (ở nhà macro không có `.lib`). Đây lại là các đường găng dự kiến (`docs/spec/core.md` mục 4.5), nên số setup ở nhà lạc quan hơn thật.
- Tổng hợp mất khoảng 11 phút. Lần này làm tay. Từ STA-03 chạy bằng `make sta-soc-nangate STA_PERIOD=<ns>` (`syn/yosys/sta_soc_nangate.tcl`).

## 3. Tổng hợp từng khối trên Genus (STA-02, ở trường)

Chạy bằng `make synth-blocks` (`syn/scripts/synth_block.tcl`), cách chạy ở `docs/flow_notes.md` mục 2. Mỗi khối một dòng, lấy số từ `syn/out_blocks/<khối>/reports/` và `summary.txt`. Diện tích của `imem_port`, `sram_wrap` gồm cả macro SRAM. Lõi `rv32_core` dùng flow riêng của Nhân (`make synth-core`, `docs/genus_core.md`), không ghi ở bảng này.

| Ngày | Khối | Clock gating | Diện tích (µm²) | Flop | Scan flop | ICG | Latch | Setup WNS (ns) | Unconstrained | Report gốc | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29/10 | `sys_bus` | Có | 585,2 | 3 | 0 | 0 | 0 | +9,562 | 0 | `appendix/synth_blocks/sys_bus/` |  |
| 29/10 | `apb_bridge` | Có | 1 435,0 | 94 | 0 | 4 | 0 | +13,713 | 0 | `appendix/synth_blocks/apb_bridge/` |  |
| 29/10 | `dma_apb` | Có | 2 318,8 | 191 | 0 | 7 | 0 | +9,524 | 0 | `appendix/synth_blocks/dma_apb/` | Trong `soc_top` đang tắt (`ENABLE_DMA = 0`) |
| 29/10 | `imem_port` | Có | 33 649,8 | 38 | 0 | 1 | 0 | +10,044 | 0 | `appendix/synth_blocks/imem_port/` | Gồm 4 macro (32 000), logic 1 649,8 |
| 29/10 | `sram_wrap` | Có | 32 725,5 | 5 | 0 | 0 | 0 | +10,556 | 0 | `appendix/synth_blocks/sram_wrap/` | Gồm 4 macro (32 000), logic 725,5 |
| 29/10 | `timer_apb` | Có | 2 110,1 | 130 | 0 | 3 | 0 | +9,728 | 0 | `appendix/synth_blocks/timer_apb/` |  |
| 29/10 | `uart_apb` | Có | 2 165,9 | 223 | 0 | 28 | 0 | +9,321 | 0 | `appendix/synth_blocks/uart_apb/` |  |
| 29/10 | `gpio_apb` | Có | 1 293,1 | 128 | 0 | 2 | 0 | +9,968 | 0 | `appendix/synth_blocks/gpio_apb/` |  |
| 29/10 | `irqc_apb` | Có | 105,0 | 6 | 0 | 1 | 0 | +10,125 | 0 | `appendix/synth_blocks/irqc_apb/` |  |
| 29/10 | `accel_apb` | Có | 15 283,3 | 792 | 0 | 14 | 0 | +9,209 | 0 | `appendix/synth_blocks/accel_apb/` |  |

| 29/10 | `sram_wrap1` | Có | 8 298,6 | 3 | 0 | 0 | 0 | +10,556 | 0 | `appendix/synth_blocks/sram_wrap1/` | `sram_wrap` với 1 macro (`BANK_W = 0`), để luyện flow macro. Logic 298,6 |

Tiêu chí: Scan flop = 0, Latch = 0, Unconstrained = 0, Setup WNS >= 0 ở 20 ns.

Ghi chú lần chạy 29/10 (STA-02): cả 10 khối đạt tiêu chí. Lint timing của mỗi khối báo 2 mục không ảnh hưởng timing: false path từ cổng reset "no effect" (như `soc_top`), và cổng reset thiếu driving cell (SDC sinh ra chỉ gán cho các cổng vào khác). Mục thứ hai đã sửa trong `synth_block.tcl` sau lần chạy này.

Lần chạy đầu điền vào các dòng có sẵn. Các lần sau (ví dụ chạy lại sau khi sửa RTL) thêm dòng mới ở cuối bảng.
