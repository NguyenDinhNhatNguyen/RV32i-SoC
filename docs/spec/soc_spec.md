# Đặc tả SoC (SP-01)

Bản nháp ngày 21/10 để cả nhóm chốt. Phần lõi chi tiết nằm ở `docs/spec/core.md` (nhánh `feat/nhan-core` của Nhân), tài liệu này chỉ ghi những gì các khối phải thống nhất với nhau: clock, reset, bus, bản đồ địa chỉ, bộ nhớ, ngắt và giao diện accelerator.

Mục 7 là các điểm còn mâu thuẫn giữa Doc kế hoạch, spec lõi và kết quả kiểm tra server. Mỗi điểm có đề xuất. Cả nhóm trả lời trong nhóm chat hoặc sửa thẳng file này, chốt xong thì đổi trạng thái thành "Đã chốt".

## 1. Clock và reset

- Một miền clock `clk`, không có CDC. Mục tiêu tối thiểu 50 MHz (chu kỳ 20 ns), quét tần số ở tuần 4–5.
- Reset `rst_n` tích cực mức thấp, bất đồng bộ khi assert, đồng bộ khi deassert.
- Một bộ đồng bộ reset 2 flop ở `soc_top`. Mọi khối dùng chung ngõ ra của bộ đồng bộ này.
- SDC: chỉ false path từ chân `rst_n` tới bộ đồng bộ. Đường deassert sau đó phải kiểm recovery/removal.

## 2. Bus hệ thống

Dùng đúng giao thức trong `docs/spec/core.md` mục 5.1, tóm tắt:

| Kênh | Tín hiệu | Hướng |
| --- | --- | --- |
| Yêu cầu | `req_valid`, `req_ready`, `addr[31:0]`, `we`, `be[3:0]`, `wdata[31:0]` | master → slave, riêng `req_ready` ngược lại |
| Phản hồi | `rsp_valid`, `rdata[31:0]`, `err` | slave → master |

- Yêu cầu được nhận khi `req_valid && req_ready`. `req_ready=0` là wait state.
- Mỗi yêu cầu có đúng một `rsp_valid`, sớm nhất ở chu kỳ sau, theo thứ tự. Tối đa 1 yêu cầu đang chờ.
- `err` chỉ có nghĩa khi `rsp_valid=1`, khi đó `rdata=0`.
- `sys_bus` có tham số `N_MASTER` (1 lúc đầu, 2 khi có DMA, trọng tài round-robin).

Ngoại vi tốc độ thấp nối qua một cầu `bus → APB3` (theo mục "Đối chiếu với phương án chuẩn" của Doc kế hoạch). Mỗi ngoại vi là một APB3 slave, `PSLVERR` của slave được cầu chuyển thành `err`.

## 3. Bản đồ địa chỉ

Giải mã bằng `addr[31:28]` chọn vùng, `addr[15:12]` chọn ngoại vi trong vùng `0x2`.

| Vùng | Địa chỉ gốc | Kích thước | Ghi chú |
| --- | --- | --- | --- |
| IMEM | 0x0000_0000 | xem mục 7.2 | `.text`, đọc/ghi được từ bus để nạp chương trình |
| Boot ROM | 0x0001_0000 | xem mục 7.1 | Chỉ khi chốt reset vector ở đây |
| DMEM | 0x1000_0000 | xem mục 7.2 | `.rodata`, `.data`, `.bss`, stack ở đỉnh |
| Timer | 0x2000_0000 | 4 KB | mtime/mtimecmp kiểu CLINT |
| UART | 0x2000_1000 | 4 KB | |
| GPIO | 0x2000_2000 | 4 KB | |
| SPI | 0x2000_3000 | 4 KB | Tầng 1 |
| I2C | 0x2000_4000 | 4 KB | Tầng 2 |
| PWM | 0x2000_5000 | 4 KB | Tầng 1 |
| Accelerator | 0x3000_0000 | 4 KB | Bản đồ thanh ghi ở `docs/runbook_nguyen.md` |
| DMA | 0x4000_0000 | 4 KB | Tầng 2 |

`tb/core/core_tb_map.vh` và `fw/common/link.ld` phải khớp bảng này.

## 4. Bộ nhớ

Kết quả HT-01 (21/10): trên server có macro `sram_2k_macro`.

| Thông số | Giá trị |
| --- | --- |
| Tổ chức | 1024 word × 32 bit = 4 KB |
| Kích thước | 80 × 100 µm |
| Chân | `CLK`, `CEN` (tích cực thấp), `WEN` (tích cực thấp), `A[9:0]`, `D[31:0]`, `Q[31:0]` |
| Ghi theo byte | Không có |
| File | LEF, `.lib`, model `.v`. Không có GDS và CDL, thầy xác nhận không cần (22/10) |

Đọc đồng bộ: `Q` có ở chu kỳ sau, khớp luật `rsp_valid` ở chu kỳ sau của bus.

## 5. Ngắt

- Lõi có 3 ngõ vào mức: `irq_software_i`, `irq_timer_i`, `irq_external_i` (`docs/spec/core.md` mục 4.10).
- `irq_timer_i` lấy từ Timer (mtime ≥ mtimecmp).
- `irq_external_i` là OR của các nguồn ngoại vi qua bộ gom ngắt rút gọn (RTL-11): UART, GPIO, accelerator (`irq` của wrapper), sau này SPI và DMA.
- Mỗi nguồn có bit enable và bit pending riêng trong bộ gom ngắt, ghi 1 để xoá.

## 6. Accelerator

- Nối như một APB3 slave, dùng `rtl/accel/accel_apb.v` đã có (APB3 chỉ truy cập word, `PSLVERR` cho địa chỉ không định nghĩa và khi ghi vào C_BUF).
- Bản đồ thanh ghi (base 0x3000_0000): CTRL 0x000, STATUS 0x004, INFO 0x008, A_BUF 0x100, B_BUF 0x200, C_BUF 0x300. Chi tiết ở `docs/runbook_nguyen.md`.
- `irq` của accelerator vào bộ gom ngắt (mục 5).
- Firmware dùng `fw/accel.h`.

## 7. Các điểm cần chốt

### 7.1 Reset vector

- Doc kế hoạch: 0x0000_0000 (đầu IMEM).
- `rv32_core`: mặc định `RESET_PC = 0x0001_0000` (boot ROM).
- **Đề xuất:** giữ 0x0001_0000 như lõi. RTL-08 đã có boot ROM nhỏ để nạp IMEM. Trong mô phỏng, tham số `RESET_PC` đặt lại 0x0000_0000 để chạy thẳng chương trình nạp bằng `$readmemh`.

### 7.2 Dung lượng IMEM và DMEM

- Một macro chỉ 4 KB. `tb/core/core_tb_map.vh` đang giả định mỗi vùng 16 KB.
- CoreMark cần khoảng 12–16 KB cho `.text` và vài KB cho dữ liệu và stack. Dhrystone nhỏ hơn nhiều.
- Phương án:

| Phương án | IMEM | DMEM | Số macro | Diện tích macro | Chạy được |
| --- | --- | --- | --- | --- | --- |
| A | 4 KB | 4 KB | 2 | 0,016 mm² | Dhrystone, riscv-tests |
| B | 8 KB | 8 KB | 4 | 0,032 mm² | Dhrystone, có thể CoreMark bản thu gọn |
| C | 16 KB | 16 KB | 8 | 0,064 mm² | CoreMark, khớp testbench hiện tại |

- **Đề xuất:** C. Khớp testbench của Nhân và đủ cho CoreMark (điểm PPA). Floorplan lớn hơn nhưng PD-02 tính lại được ngay khi có diện tích cell chuẩn. Nếu nhóm muốn layout nhỏ và nhanh xong thì chọn B.

### 7.3 Ghi theo byte (SB, SH)

- Lõi phát `be[3:0]`, macro không có chân ghi theo byte.
- **Đề xuất:** wrapper SRAM (RTL-08) đọc–sửa–ghi khi `be != 4'b1111`. Chu kỳ 1 đọc word với `req_ready=0`, chu kỳ 2 ghép byte mới và ghi. Store byte/half mất thêm 1 chu kỳ, đúng luật wait state của bus. SW và mọi lệnh đọc vẫn 1 chu kỳ.

### 7.4 Địa chỉ không ánh xạ

- Doc kế hoạch: đọc trả 0, ghi bị bỏ qua.
- `docs/spec/core.md`: slave lỗi trả `err`, lõi gây access fault.
- **Đề xuất:** trả `err` như spec lõi. Lỗi phần mềm lộ ra ngay thay vì đọc ra 0 âm thầm, và `accel_apb` đã làm vậy với `PSLVERR`.

### 7.5 Đường nối accelerator

- Bus của lõi trả dữ liệu ở chu kỳ sau. `accel_wrapper` trả `s_rdata` ngay trong chu kỳ.
- **Đề xuất:** nối qua cầu APB bằng `accel_apb` (mục 6). Không cần sửa wrapper, và ngoại vi nào cũng đi cùng một đường.

## 8. Trạng thái

| Mục | Trạng thái |
| --- | --- |
| 1. Clock, reset | Theo Doc kế hoạch |
| 2. Bus | Theo `docs/spec/core.md` 5.1 |
| 3. Bản đồ địa chỉ | Chờ 7.1, 7.2 |
| 4. Bộ nhớ | Thông số đã có từ HT-01, chờ 7.2, 7.3 |
| 5. Ngắt | Nháp |
| 6. Accelerator | Chờ 7.5 |
