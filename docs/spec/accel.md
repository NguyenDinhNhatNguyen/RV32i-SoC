# Đặc tả accelerator nhân ma trận (RTL-05)

Accelerator của Lab 2 (mảng systolic 4x4) được bọc thành ngoại vi để CPU điều khiển bằng lệnh `sw`/`lw`. Base `0x3000_0000`, cửa sổ 4 KB, nối vào khe APB 7 của `soc_top`.

## 1. Các file

| File | Vai trò |
| --- | --- |
| `rtl/accel/pe.v`, `rtl/accel/accelerator_top.v` | Lõi Lab 2: 16 PE, mỗi PE nhân 8x8 có dấu, tích luỹ 20 bit |
| `rtl/accel/accel_wrapper.v` | Thanh ghi, bộ đệm A, B, FSM IDLE → CLR → RUN, bộ sinh lệch pha (skew), ngắt |
| `rtl/accel/accel_apb.v` | Vỏ APB3: chỉ truy cập word, `PSLVERR` cho địa chỉ không định nghĩa và khi ghi C_BUF |
| `fw/accel.h` | Macro thanh ghi và hàm `accel_matmul()` cho firmware |
| `tb/unit/tb_accel_wrapper.v` | 40 phép nhân ngẫu nhiên và các ca biên, so với mô hình vàng |
| `tb/unit/tb_accel_apb.v` | 10 phép nhân qua APB và 4 kiểm tra `PSLVERR` |
| `fw/tests/soc/soc.S` | Bài `soc`: nhân ma trận trên accelerator trong toàn SoC |

## 2. Bản đồ thanh ghi

| Offset | Tên | Truy cập | Ý nghĩa |
| --- | --- | --- | --- |
| 0x000 | CTRL | W | bit0 START (chỉ nhận khi rảnh), bit1 IRQ_EN |
| 0x000 | CTRL | R | bit1 IRQ_EN |
| 0x004 | STATUS | R | bit0 BUSY, bit1 DONE |
| 0x004 | STATUS | W | Ghi 1 vào bit1 để xoá DONE |
| 0x008 | INFO | R | `{N, DW, AW, LAT}` mỗi trường 8 bit, từ MSB xuống. Hiện là `0x0408_140A` |
| 0x100–0x10C | A_BUF | RW | 16 byte ma trận A, `A[i][k]` ở byte `i*4+k`, little-endian trong word |
| 0x200–0x20C | B_BUF | RW | 16 byte ma trận B, `B[k][j]` ở byte `k*4+j` |
| 0x300–0x33C | C_BUF | R | 16 kết quả, `C[i][j]` ở word `i*4+j`, 20 bit mở rộng dấu lên 32 bit |

- Ghi A, B hoặc CTRL khi BUSY bị bỏ qua.
- Qua APB, offset 0x00C–0x0FC, offset từ 0x400 trở lên và mọi lệnh ghi vào C_BUF trả `PSLVERR`. Lõi gặp access fault thay vì đọc ra 0.
- `irq = DONE & IRQ_EN`, dạng mức, đi vào bộ gom ngắt (`docs/spec/periph.md` mục 4).

## 3. Quy trình firmware

1. Ghi A vào A_BUF, B vào B_BUF (4 lệnh `sw` mỗi ma trận).
2. Ghi CTRL = 1 (hoặc 3 nếu dùng ngắt).
3. Chờ STATUS.DONE = 1 (hoặc chờ ngắt). Mất 12 chu kỳ: 1 chu kỳ CLR và LAT = 10 chu kỳ RUN.
4. Đọc 16 word C_BUF.
5. Ghi STATUS = 2 để xoá DONE.

`accel_matmul(a, b, c)` trong `fw/accel.h` làm đúng các bước trên bằng polling.

## 4. Hoạt động bên trong

- **IDLE:** chờ START.
- **CLR (1 chu kỳ):** pulse `start` và `clear` cho lõi Lab 2, xoá tích luỹ và thanh ghi truyền.
- **RUN (LAT = 3N − 2 = 10 chu kỳ):** ở chu kỳ `t`, hàng `i` nhận `A[i][t-i]`, cột `j` nhận `B[t-j][j]`, ngoài phạm vi thì đưa 0. Hết RUN thì bật DONE.
- Lõi trả một hàng kết quả mỗi lần, chọn bằng `row_sel` one-hot. Wrapper lấy hàng từ địa chỉ C_BUF (`widx[3:2]`) và cột từ `widx[1:0]`.

## 5. Ghép lõi Lab 2 (25/10)

| Câu hỏi | Lõi Lab 2 | Wrapper xử lý |
| --- | --- | --- |
| Có dấu hay không dấu | Có dấu, 8 bit, tích luỹ 20 bit | `SIGNED = 1` |
| Lõi có tự lệch pha dữ liệu không | Không, `a_row*`, `b_col*` vào thẳng biên mảng | Giữ bộ sinh skew của wrapper |
| Có start/busy/done không | Có. `busy` kéo dài 10 chu kỳ sau `start`, `valid_in = busy` | Pulse `start` cùng `clear` ở CLR, `busy` trùng 10 chu kỳ RUN |
| Kết quả ra thế nào | Đọc một hàng qua `row_sel`, đủ sau 3N − 2 = 10 chu kỳ | `LAT = 10`, `row_sel` lấy từ địa chỉ C_BUF |

Chỗ đã sửa trong lõi Lab 2:

- `pe.v` thêm chân `en`. Thanh ghi truyền và tích luỹ chỉ cập nhật khi `en = 1`, `accelerator_top` nối `en = busy`. Nhờ vậy Genus gate clock được (Yosys đếm 863/864 flop có enable).
- `clr_acc` xoá cả thanh ghi truyền, vì khi `en = 0` chúng giữ giá trị của lần chạy trước.
- Thêm `` `timescale `` cho khớp các file khác (Verilator báo TIMESCALEMOD).

Tham số lõi cố định N = 4, DW = 8, AW = 20. Giữ nguyên tham số mặc định của wrapper.

## 6. Kiểm chứng

| Lệnh | Đạt khi |
| --- | --- |
| `make lint-accel` | 0 `%Warning` |
| `make sim-accel` | `PASS: 40 matrix multiplies 4x4 match the golden model` |
| `make sim-accel-apb` | `PASS: APB3 - 10 multiplies and 4 PSLVERR checks correct` |
| `make fw-soc` | Bài `soc` PASS (nhân ma trận qua APB trong toàn SoC) |
| `make wave-accel` | Mở GTKWave với preset `tb/unit/accel.gtkw` |

Preset sóng chọn sẵn `dut.state`, `dut.busy`, `dut.done`, `dut.cnt`, `dut.a_feed`, `dut.b_feed`, `irq`. Hình FSM IDLE → CLR → RUN và dữ liệu lệch pha dùng tốt cho report.

Kết quả 25/10: check 2 PASS, lint 0 warning, `unit-bus` 7/7, `fw-soc` 126/126.
