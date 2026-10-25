# PD-02: ước lượng die, đặt macro, pin plan, power plan

Bản ước lượng ngày 25/10, làm ở nhà. Số chính thức thay vào khi có diện tích Genus của toàn SoC (STA-02, STA-04). Script tương ứng: `pnr/scripts/soc_floorplan.tcl`, chạy thử lần đầu ở PD-03.

## 1. Diện tích cell chuẩn

Tổng hợp `soc_top` bằng Yosys với thư viện mở Nangate45 (cùng script `syn/yosys/synth_nangate.tcl` của Nhân), 8 macro SRAM để hộp đen. Quy đổi sang GPDK45 bằng tỉ lệ của accelerator, khối duy nhất đã có số Genus thật.

| Khối | Nangate45 (Yosys) | GPDK45 (Genus) |
| --- | --- | --- |
| `accel_wrapper` | 17 906 µm² | 14 665 µm² (21/10, `appendix/synth_accel/cg1`) |
| `soc_top`, không tính macro | 51 714 µm² | ≈ 42 400 µm² (nhân tỉ lệ 0,82) |

Dùng **51 714 µm²** làm số an toàn để chọn floorplan. Số GPDK45 là quy đổi thô, chỉ để biết cỡ.

Lưu ý: Yosys trong image Docker của nhóm không nhận `abc -fast` trong `syn/yosys/synth_nangate.tcl`. Lần chạy này dùng bản chép bỏ `-fast`.

## 2. Kích thước die

Đầu vào: 8 macro `sram_2k_macro` 80 × 100 µm (IMEM 16 KB = 4 macro, DMEM 16 KB = 4 macro, `BANK_W=2` trong `rtl/bus/soc_map.vh`), halo 5 µm, chừa 15 µm cho power ring.

| Kịch bản | Core | Die |
| --- | --- | --- |
| Dự kiến: 42 400 µm², mật độ 70% | 374 × 375 µm | 404 × 405 µm = 0,163 mm² |
| **Chọn:** 51 714 µm², mật độ 70% | **391 × 392 µm** | **421 × 422 µm = 0,178 mm²** |
| Dư thêm: 51 714 µm², mật độ 60% | 407 × 407 µm | 437 × 437 µm = 0,191 mm² |

Lệnh: `python3 pnr/scripts/estimate_die.py --std-area 51714 --macro 80x100 (x8) --util 0.70`.

## 3. Đặt macro

```text
        cạnh trên
  ┌──────────────────────────┐
  │ IMEM0 IMEM1 IMEM2 IMEM3  │  4 × (80 + 10) = 360 µm < 391 µm
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

Cạnh trên và dưới không đặt chân vì đã có macro. Cả hai cạnh dọc dài 392 µm, đủ chỗ.

## 5. Power plan

- Ring lõi Metal7/Metal8, stripe Metal7 ngang và Metal8 dọc cách nhau 30 µm, như PD-01 (đã chạy được trên Innovus 21.1).
- Ring quanh từng macro, rồi `sroute -connect {blockPin}` nối chân nguồn của macro. Lớp của ring macro (mặc định Metal5/Metal6) chọn lại theo lớp chân VDD/VSS trong output `macro_info.sh`.

## 6. Còn lại

| Việc | Vì sao chưa xong | Khi nào |
| --- | --- | --- |
| Chạy `soc_floorplan.tcl` trên Innovus | Cần server trường và netlist Genus của `soc_top` | PD-03 (05/11) |
| Chọn hướng macro và lớp ring | Cần output `scripts/macro_info.sh` trên server | Buổi lên trường tới |
| Thay diện tích ước lượng bằng số Genus | Cần tổng hợp toàn SoC bằng Genus (Phát, STA-02) | 08/11 |
