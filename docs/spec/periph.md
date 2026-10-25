# Đặc tả ngoại vi và boot ROM

Bản đồ thanh ghi của các khối nối sau cầu APB3. Địa chỉ gốc lấy từ `rtl/bus/soc_map.vh` (`docs/spec/soc_spec.md` mục 3). Accelerator có tài liệu riêng ở `docs/spec/accel.md`.

Quy ước chung cho mọi ngoại vi APB3:

- Chỉ truy cập theo word (`addr[1:0] = 0`). Địa chỉ lệch hoặc offset không định nghĩa trả `PSLVERR`, cầu APB chuyển thành `err` trên bus.
- Mỗi khối chiếm cửa sổ 4 KB, giải mã bằng `PADDR[11:2]`.
- Ngắt ra là dạng mức, qua 1 flop (trễ 1 chu kỳ). Phần mềm xoá ngắt tại chính ngoại vi.

## 1. Timer (`rtl/periph/timer_apb.v`, 0x2000_0000)

Timer kiểu CLINT rút gọn, đếm mỗi chu kỳ clock.

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | MTIME_LO | RW | 0 | 32 bit thấp của bộ đếm |
| 0x04 | MTIME_HI | RW | 0 | 32 bit cao |
| 0x08 | MTIMECMP_LO | RW | 0xFFFF_FFFF | 32 bit thấp của giá trị so sánh |
| 0x0C | MTIMECMP_HI | RW | 0xFFFF_FFFF | 32 bit cao |
| 0x10 | MSIP | RW | 0 | bit0 nối `irq_software_i` của lõi |

- `irq_timer = (mtime >= mtimecmp)`, nối thẳng `irq_timer_i` của lõi.
- Ghi mtimecmp 64 bit không gây ngắt giả: ghi HI = 0xFFFF_FFFF, rồi LO, rồi HI.
- Đọc mtime 64 bit: đọc HI, LO, HI rồi so hai lần HI để bắt trường hợp nhớ giữa chừng.

## 2. UART (`rtl/periph/uart_apb.v`, 0x2000_1000)

UART 8N1, FIFO TX và RX sâu `2**FIFO_AW` byte (mặc định 8).

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | DATA | W | — | Đẩy byte `[7:0]` vào FIFO TX. FIFO đầy thì byte bị bỏ và bật TXOVF |
| 0x00 | DATA | R | — | Lấy byte `[7:0]` từ FIFO RX. FIFO rỗng trả 0, không báo lỗi |
| 0x04 | STATUS | R | — | bit0 TXF, bit1 TXE, bit2 TXB, bit3 RXF, bit4 RXNE, bit5 OVR, bit6 FE, bit7 TXOVF |
| 0x04 | STATUS | W | — | Ghi 1 vào bit 5..7 để xoá. Các bit khác bỏ qua |
| 0x08 | CTRL | RW | 0x03 | bit0 TXEN, bit1 RXEN, bit2 TXIE, bit3 RXIE, bit4 ERRIE |
| 0x0C | BAUDDIV | RW | 27 | `baud = f_clk / (16 × DIV)`. 27 cho 115200 baud ở 50 MHz (sai số +0,47%) |

Ý nghĩa các bit STATUS:

| Bit | Tên | Ý nghĩa |
| --- | --- | --- |
| 0 | TXF | FIFO TX đầy |
| 1 | TXE | FIFO TX rỗng |
| 2 | TXB | Đang dịch bit ra |
| 3 | RXF | FIFO RX đầy |
| 4 | RXNE | FIFO RX có dữ liệu |
| 5 | OVR | Có byte mới tới khi FIFO RX đầy (giữ tới khi xoá) |
| 6 | FE | Bit stop bằng 0 (giữ tới khi xoá) |
| 7 | TXOVF | Ghi DATA khi FIFO TX đầy (giữ tới khi xoá) |

- `irq = TXIE & TXE | RXIE & RXNE | ERRIE & (OVR | FE | TXOVF)`.
- RX lấy mẫu 16 lần mỗi bit, ở giữa bit. Chân `uart_rx` đi qua bộ đồng bộ 2 flop.

## 3. GPIO (`rtl/periph/gpio_apb.v`, 0x2000_2000)

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | DATA_OUT | RW | 0 | Giá trị xuất ra chân |
| 0x04 | DATA_IN | R | — | Giá trị chân (qua đồng bộ 2 flop). Ghi trả `PSLVERR` |
| 0x08 | DIR | RW | 0 | 1 là xuất, 0 là nhập |

- Không có tri-state bên trong. `gpio_o`, `gpio_oe`, `gpio_i` tách riêng, pad thêm ở mức chip.
- Chưa có ngắt GPIO.

## 4. Bộ gom ngắt IRQC (0x2000_6000, RTL-11, chưa có RTL)

Thanh ghi đã chốt ở `docs/spec/soc_spec.md` mục 5:

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | PENDING | R | — | Mỗi bit là mức hiện tại của một nguồn ngắt |
| 0x04 | ENABLE | RW | 0 | Bật từng nguồn |

`irq_external_i = |(PENDING & ENABLE)`.

Gán bit nguồn ngắt (đề xuất, người làm RTL-11 chốt khi viết RTL):

| Bit | Nguồn | Có sẵn ở `soc_top` |
| --- | --- | --- |
| 0 | UART | `uart_irq` |
| 1 | Accelerator | `accel_irq` |
| 2 | GPIO | Chưa có, để 0 |
| 3 | SPI | Chưa có, để 0 |
| 4 | DMA | Chưa có, để 0 |

Hiện `soc_top` nối `irq_external = 0` và khe APB 6 chưa bật.

## 5. Boot ROM (`rtl/mem/boot_rom.v`, 0x0001_0000)

- 1 KB (256 word), làm bằng logic tổng hợp, không dùng macro.
- Là reset vector của lõi (`RESET_PC = 0x0001_0000`). Chỉ cổng nạp lệnh đọc được, cổng dữ liệu không thấy.
- Đọc đồng bộ như SRAM: dữ liệu có ở chu kỳ sau.
- Nội dung ở `rtl/mem/boot_rom_init.vh`. Bản hiện tại chỉ có `jalr x0, 0(x0)` để nhảy về đầu IMEM. Bản bootloader qua UART (Nhân) sẽ sinh lại file này bằng script, giữ nguyên định dạng.

## 6. Chân ngoài của `soc_top`

| Chân | Hướng | Độ rộng | Ý nghĩa |
| --- | --- | --- | --- |
| `clk` | vào | 1 | Clock hệ thống, mục tiêu 50 MHz |
| `rst_n` | vào | 1 | Reset ngoài, tích cực thấp, bất đồng bộ |
| `gpio_i` | vào | 32 | Chân GPIO đọc vào |
| `gpio_o` | ra | 32 | Giá trị GPIO xuất ra |
| `gpio_oe` | ra | 32 | 1 khi chân là ngõ ra |
| `uart_rx` | vào | 1 | UART nhận |
| `uart_tx` | ra | 1 | UART phát |

Tổng 100 chân tín hiệu. Vị trí chân trên die: `pnr/scripts/soc_floorplan.tcl` (cạnh trái và phải).
