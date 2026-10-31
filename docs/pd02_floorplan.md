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
| **Chọn (31/10):** 53 408 µm², mật độ 70% | **394 × 395 µm** | **424 × 425 µm = 0,180 mm²** |
| Dư thêm: 53 408 µm², mật độ 60% | 410 × 410 µm | 440 × 440 µm = 0,194 mm² |

Lệnh: `python3 pnr/scripts/estimate_die.py --std-area 53408 --macro 80x100 --util 0.70`, lặp `--macro 80x100` đủ 8 lần.

`--std-area` chỉ nhận diện tích cell chuẩn, script tự cộng macro và halo. Lần PnR 29/10 dùng lõi 524 × 523 µm vì đã nhập tổng 116 757 µm² (có cả macro), nên macro bị tính hai lần và lõi to gấp 1,76 lần cần thiết.

## 3. Đặt macro

```text
        cạnh trên
  ┌──────────────────────────┐
  │ IMEM0 IMEM1 IMEM2 IMEM3  │  4 × (80 + 10) = 360 µm < 394 µm
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

- Mỗi hàng 4 macro sát cạnh, cố định trước placement. Hàng trên lật trục X để chân quay xuống dải logic. Hướng cụ thể chọn lại sau khi có output `scripts/macro_info.sh` (chân macro nằm ở cạnh nào).
- Khe giữa 2 macro cạnh nhau là 10 µm (2 halo).
- Hàng cell chuẩn dưới macro bị cắt (`cutRow`).

## 4. Pin plan

| Cạnh | Chân | Số chân | Chiều dài cần (cách 4 µm) |
| --- | --- | --- | --- |
| Trái | `clk`, `rst_n`, `uart_rx`, `uart_tx`, `gpio_i[31:0]` | 36 | 144 µm |
| Phải | `gpio_o[31:0]`, `gpio_oe[31:0]` | 64 | 256 µm |

Cạnh trên và dưới không đặt chân vì đã có macro. Cả hai cạnh dọc dài 395 µm, đủ chỗ.

## 5. Power plan

- Ring lõi Metal7/Metal8, stripe Metal7 ngang và Metal8 dọc cách nhau 30 µm, như PD-01 (đã chạy được trên Innovus 21.1).
- Ring quanh từng macro, rồi `sroute -connect {blockPin}` nối chân nguồn của macro. Lớp của ring macro (mặc định Metal5/Metal6) chọn lại theo lớp chân VDD/VSS trong output `macro_info.sh`.

## 6. Kết quả và việc còn lại

Lần chạy 29/10 (`make pnr-accel` sửa tạm thành `soc_top`) đã place và route được `soc_top` với 8 macro, nhưng `run_all.tcl` chưa gọi script này nên Innovus tự đặt macro. Sửa ngày 31/10:

- `make pnr-soc` chạy `run_all.tcl` với `TOP=soc_top` và gọi `soc_floorplan.tcl`. `make pnr-accel` chạy lại được như cũ.
- Lõi 394 × 395 µm thay cho 524 × 523 µm.
- `CLKBUFX2` bị cấm ngay sau `init_design`. Lần 29/10 chỉ cấm trước CTS nên tối ưu placement chèn 1220 cell này làm buffer dữ liệu.

| Việc | Vì sao chưa xong | Khi nào |
| --- | --- | --- |
| Chạy `make pnr-soc` với netlist mới | Chờ Phát chạy lại `make synth-soc` (bản giữ flop và buffer mạng reset) | Buổi lên trường tới |
| Đưa report timing, DRC của `soc_top` vào `appendix/pnr_soc` | Report lần 29/10 nằm trên server | Cùng buổi trên |
| Chọn lại hướng macro và lớp ring | Output `macro_info.sh` (30/10) còn trên server, chưa commit | Cùng buổi trên |
