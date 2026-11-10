# PD-02: ước lượng die, đặt macro, pin plan, power plan

Ước lượng ngày 25/10 ở nhà, cập nhật 31/10 theo số Genus thật của `soc_top`. Script tương ứng: `pnr/scripts/soc_floorplan.tcl`, được `make pnr-soc` gọi.

## 1. Diện tích cell chuẩn

Tổng hợp `soc_top` bằng Yosys với thư viện mở Nangate45 (cùng script `syn/yosys/synth_nangate.tcl` của Nhân), 8 macro SRAM để hộp đen. Quy đổi sang GPDK45 bằng tỉ lệ của accelerator, khối duy nhất đã có số Genus thật.

| Khối | Nangate45 (Yosys) | GPDK45 (Genus) |
| --- | --- | --- |
| `accel_wrapper` | 17 906 µm² | 14 665 µm² (21/10, `appendix/synth_accel/cg1`) |
| `soc_top`, không tính macro | 51 714 µm² | ≈ 42 400 µm² (nhân tỉ lệ 0,82) |

Số Genus thật (report `area.rpt` ghi tổng có cả 8 macro, mỗi macro 8 000 µm²):

| Netlist | Tổng | Trừ 8 macro |
| --- | --- | --- |
| `appendix/synth_soc` (29/10) | 116 757 µm² | 52 757 µm² |
| `appendix/synth_soc_keepflop` (30/10, giữ mọi flop cho LEC) | 117 408 µm² | **53 408 µm²** |

Dùng **53 408 µm²** để chọn floorplan. Bản sắp tới có buffer cho mạng reset (`soc.sdc` thêm `set_max_transition`, `set_max_fanout`) sẽ lớn hơn một chút, mật độ 70% vẫn còn chỗ.

Lưu ý: Yosys trong image Docker của nhóm không nhận `abc -fast` trong `syn/yosys/synth_nangate.tcl`. Lần chạy này dùng bản chép bỏ `-fast`.

## 2. Kích thước die

Đầu vào: 8 macro `sram_2k_macro` 80 × 100 µm (IMEM 16 KB = 4 macro, DMEM 16 KB = 4 macro, `BANK_W=2` trong `rtl/bus/soc_map.vh`), halo 5 µm, chừa 15 µm cho power ring.

| Kịch bản | Core | Die |
| --- | --- | --- |
| Ước lượng 25/10: 51 714 µm², mật độ 70% | 391 × 392 µm | 421 × 422 µm = 0,178 mm² |
| 31/10: 53 408 µm², mật độ 70% | 394 × 395 µm | 424 × 425 µm = 0,180 mm² |
| 07/11: 55 700 µm² (có SPI, PWM), mật độ 70% | 397 × 400 µm | 427 × 430 µm = 0,184 mm² |
| 07/11: 58 000 µm² (có SPI, PWM, DMA), mật độ 70% | 402 × 404 µm | 432 × 434 µm = 0,187 mm² |
| **Chọn (10/11):** 59 400 µm² (có SPI, PWM, DMA, I2C), mật độ 70% | **405 × 405 µm** | **435 × 435 µm = 0,189 mm²** |

Lệnh: `python3 pnr/scripts/estimate_die.py --std-area 59400 --macro 80x100 --util 0.70`, lặp `--macro 80x100` đủ 8 lần.

59 400 µm² = 53 900 µm² (Genus 31/10, reset có buffer, `docs/sta_results.md`) cộng khoảng 1 800 µm² cho SPI và PWM ghép vào ngày 07/11, cộng khoảng 2 300 µm² cho DMA bật mặc định cùng ngày (khối `dma_apb` trên Genus 29/10 là 2 318,8 µm², `appendix/synth_blocks`). Ngày 10/11 cộng thêm khoảng 500 µm² cho trọng tài 2 master của `sys_bus` và 850 µm² cho I2C (Yosys Nangate45 lần lượt 195 và 726 µm², nhân lên cho GPDK45). Số SPI, PWM lấy từ Yosys Nangate45 (526 và 1 092 µm²), nhân tỉ lệ GPDK45/Nangate45 của `uart_apb` (2 166 / 1 954). Khi Phát có diện tích Genus mới thì so lại, `pd_checks.rpt` cũng in mật độ thật sau PnR.

`--std-area` chỉ nhận diện tích cell chuẩn, script tự cộng macro và halo. Lần PnR 29/10 dùng lõi 524 × 523 µm vì đã nhập tổng 116 757 µm² (có cả macro), nên macro bị tính hai lần và lõi to gấp 1,76 lần cần thiết.

## 3. Đặt macro

```text
        cạnh trên
  ┌──────────────────────────┐
  │ IMEM0 IMEM1 IMEM2 IMEM3  │  4 × (80 + 10) = 360 µm < 405 µm
  │                          │
 trái    logic (core, bus,    phải
 clk,     ngoại vi, accel)    gpio_o
 rst_n,                       gpio_oe
 uart,                        (64 chân)
 gpio_i  dải cao ≈ 170 µm
  │                          │
  │ DMEM0 DMEM1 DMEM2 DMEM3  │
  └──────────────────────────┘
        cạnh dưới
```

- Mỗi hàng 4 macro sát cạnh, cố định trước placement. Chân tín hiệu của macro phải quay vào dải logic. `soc_floorplan.tcl` đọc LEF trong Innovus để biết chân nằm ở cạnh trên hay dưới rồi tự chọn `R0` hoặc `MX` cho từng hàng, in kết quả ra log (dòng `PD-02: macro signal pins ...`).
- Khe giữa 2 macro cạnh nhau là 10 µm (2 halo).
- Hàng cell chuẩn dưới macro bị cắt (`cutRow`).

## 4. Pin plan

| Cạnh | Chân | Số chân | Chiều dài cần (cách 4 µm) |
| --- | --- | --- | --- |
| Trái | `clk`, `rst_n`, `uart_rx`, `uart_tx`, `spi_sclk`, `spi_mosi`, `spi_miso`, `spi_cs_n`, `pwm_o`, `i2c_scl_i`, `i2c_scl_oe`, `i2c_sda_i`, `i2c_sda_oe`, `gpio_i[31:0]` | 45 | 180 µm |
| Phải | `gpio_o[31:0]`, `gpio_oe[31:0]` | 64 | 256 µm |

Tổng 109 chân (5 chân SPI, PWM thêm ngày 07/11, 4 chân I2C ngày 10/11). Cạnh trên và dưới không đặt chân vì đã có macro. Cả hai cạnh dọc dài 405 µm, đủ chỗ.

## 5. Power plan

- Ring lõi Metal7/Metal8, stripe Metal7 ngang và Metal8 dọc cách nhau 30 µm, như PD-01 (đã chạy được trên Innovus 21.1).
- Ring quanh từng macro, rồi `sroute -connect {blockPin}` nối chân nguồn của macro. Lớp của ring macro (mặc định Metal5/Metal6) chọn lại theo lớp chân VDD/VSS trong output `macro_info.sh`.

## 6. Kết quả và việc còn lại

Lần chạy 29/10 (`make pnr-accel` sửa tạm thành `soc_top`) đã place và route được `soc_top` với 8 macro, nhưng `run_all.tcl` chưa gọi script này nên Innovus tự đặt macro. Sửa ngày 31/10:

- `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl`. `make pnr-accel` chạy lại được như cũ.
- Lõi 394 × 395 µm thay cho 524 × 523 µm (07/11 nới thành 397 × 400 µm cho SPI, PWM, rồi 402 × 404 µm khi bật DMA, 405 × 405 µm ngày 10/11 khi có I2C).
- `CLKBUFX2` bị cấm ngay sau `init_design`. Lần 29/10 chỉ cấm trước CTS nên tối ưu placement chèn 1220 cell này làm buffer dữ liệu.

| Việc | Vì sao chưa xong | Khi nào |
| --- | --- | --- |
| Chạy `make pnr-soc` với netlist mới | Chờ Phát chạy lại `make synth-soc` (bản giữ flop và buffer mạng reset) | Buổi lên trường tới |
| Đưa report timing, DRC của `soc_top` vào `appendix/pnr_soc` | Report lần 29/10 nằm trên server | Cùng buổi trên |
| Chọn lại hướng macro và lớp ring | Output `macro_info.sh` (30/10) còn trên server, chưa commit | Cùng buổi trên |
