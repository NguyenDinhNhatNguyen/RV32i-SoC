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
| | | | | | | | | | | | | Chưa chạy. Lần đầu ở STA-02 |

## 2. Ở nhà (chỉ xem xu hướng)

| Ngày | Bước | Tool, thư viện | Netlist | SDC, chu kỳ | Setup WNS / TNS | Hold WNS / TNS | Recovery WNS | Removal WNS / TNS | Unconstrained | Diện tích | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 26/10 | STA-01 | OpenSTA 3.1, Nangate45 typical | Yosys 0.70 (`syn/yosys/synth_nangate.tcl`), macro SRAM hộp đen, `ENABLE_DMA = 0` | `soc.sdc`, 20 ns | +14,994 / 0 | +0,004 / 0 | +4,909 | -2,561 / -7 465 | 0 | 51 955 | Xem dưới bảng |

Ghi chú lần chạy 26/10 (STA-01):
- Mục đích là kiểm `soc.sdc`: OpenSTA đọc không lỗi, `check_setup -verbose` không báo gì. Nhóm `clk` có 3127 endpoint, nhóm reset có 2917 endpoint.
- Removal âm ở cả 2917 chân reset là do netlist ở nhà, không phải do SDC. Một flop của `reset_sync` lái thẳng 2917 chân reset, Yosys không chèn buffer nên slew lên 11,75 ns và thời gian removal bị ngoại suy thành 14,9 ns. Genus và Innovus sẽ chèn buffer cho mạng này.
- Setup tốt vì đường qua macro SRAM chưa được tính (ở nhà macro không có `.lib`). Đây lại là các đường găng dự kiến (`docs/spec/core.md` mục 4.5), nên số setup ở nhà lạc quan hơn thật.
- Tổng hợp mất khoảng 11 phút. Lệnh làm tay, chưa có target Makefile (sẽ cân nhắc thêm ở STA-03).

## 3. Tổng hợp từng khối trên Genus (STA-02, ở trường)

Chạy bằng `make synth-blocks` (`syn/scripts/synth_block.tcl`), cách chạy ở `docs/flow_notes.md` mục 2. Mỗi khối một dòng, lấy số từ `syn/out_blocks/<khối>/reports/` và `summary.txt`. Diện tích của `imem_port`, `sram_wrap` gồm cả macro SRAM. Lõi `rv32_core` dùng flow riêng của Nhân (`make synth-core`, `docs/genus_core.md`), không ghi ở bảng này.

| Ngày | Khối | Clock gating | Diện tích (µm²) | Flop | Scan flop | ICG | Latch | Setup WNS (ns) | Unconstrained | Report gốc | Ghi chú |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | `sys_bus` | | | | | | | | | | |
| | `apb_bridge` | | | | | | | | | | |
| | `dma_apb` | | | | | | | | | | |
| | `imem_port` | | | | | | | | | | |
| | `sram_wrap` | | | | | | | | | | |
| | `timer_apb` | | | | | | | | | | |
| | `uart_apb` | | | | | | | | | | |
| | `gpio_apb` | | | | | | | | | | |
| | `irqc_apb` | | | | | | | | | | |
| | `accel_apb` | | | | | | | | | | |

Tiêu chí: Scan flop = 0, Latch = 0, Unconstrained = 0, Setup WNS >= 0 ở 20 ns.

Lần chạy đầu điền vào các dòng có sẵn. Các lần sau (ví dụ chạy lại sau khi sửa RTL) thêm dòng mới ở cuối bảng.
