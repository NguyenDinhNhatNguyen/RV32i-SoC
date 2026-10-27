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

## 4. Bộ gom ngắt IRQC (`rtl/periph/irqc_apb.v`, 0x2000_6000, RTL-11)

Thanh ghi đã chốt ở `docs/spec/soc_spec.md` mục 5:

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | PENDING | R | — | Mỗi bit là mức hiện tại của một nguồn ngắt. Ghi trả `PSLVERR` |
| 0x04 | ENABLE | RW | 0 | Bật từng nguồn. Chỉ giữ 5 bit thấp |

- `irq = |(PENDING & ENABLE)`, qua 1 flop, nối `irq_external_i` của lõi.
- `PENDING` đi theo mức của nguồn kể cả khi `ENABLE` tắt, nên phần mềm đọc được nguồn nào đang chờ.
- Không có ghi 1 để xoá. Phần mềm xoá ngắt tại chính ngoại vi: đọc `DATA` của UART, ghi 1 vào bit `DONE` của accelerator.

Gán bit nguồn ngắt (macro `SOC_IRQ_*` trong `rtl/bus/soc_map.vh`):

| Bit | Nguồn | Có sẵn ở `soc_top` |
| --- | --- | --- |
| 0 | UART | `uart_irq` |
| 1 | Accelerator | `accel_irq` |
| 2 | GPIO | Chưa có, để 0 |
| 3 | SPI | Chưa có, để 0 |
| 4 | DMA | `dma_irq` khi `ENABLE_DMA = 1`, ngược lại 0 |

Khe APB 6 đã bật trong `soc_top`. Thêm nguồn mới (GPIO, SPI, DMA) thì nối vào bit tương ứng của `irq_src` trong `soc_top`.

## 5. Boot ROM (`rtl/mem/boot_rom.v`, 0x0001_0000)

- 1 KB (256 word), làm bằng logic tổng hợp, không dùng macro.
- Là reset vector của lõi (`RESET_PC = 0x0001_0000`). Chỉ cổng nạp lệnh đọc được, cổng dữ liệu không thấy.
- Đọc đồng bộ như SRAM: dữ liệu có ở chu kỳ sau.
- Nội dung ở `rtl/mem/boot_rom_init.vh`: bootloader UART của Nhân (`fw/boot/boot.S`), sinh bằng `scripts/gen_boot_rom.py` (`make boot-gen`). Chân `gpio_i[0] = 0` thì nhảy thẳng về đầu IMEM, bằng 1 thì nạp chương trình qua UART. Giao thức ở `docs/boot.md`.

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

## 7. DMA (`rtl/bus/dma_apb.v`, 0x4000_0000, RTL-15, Tầng 2)

Chỉ có khi `soc_top` dựng với `ENABLE_DMA = 1`. Khi đó DMA là master thứ 2 của `sys_bus`, chia bus với core qua trọng tài round-robin. Với `ENABLE_DMA = 0` mọi truy cập vào 0x4000_0000 trả `err`.

| Offset | Tên | Truy cập | Reset | Ý nghĩa |
| --- | --- | --- | --- | --- |
| 0x00 | SRC | RW | 0 | Địa chỉ byte nguồn. Bit 1:0 luôn đọc 0 |
| 0x04 | DST | RW | 0 | Địa chỉ byte đích. Bit 1:0 luôn đọc 0 |
| 0x08 | LEN | RW | 0 | Số word cần chép, 16 bit |
| 0x0C | CTRL | W | — | bit0 START (chỉ nhận khi rảnh), bit1 IRQ_EN |
| 0x0C | CTRL | R | 0 | bit1 IRQ_EN |
| 0x10 | STATUS | R | 0 | bit0 BUSY, bit1 DONE, bit2 ERR |
| 0x10 | STATUS | W | — | Ghi 1 vào bit1 hoặc bit2 để xoá |

- Chép theo word (`be = 4'b1111`), cả nguồn và đích tăng 4 sau mỗi word, chép tiến từng word.
- Ghi SRC, DST, LEN, CTRL khi BUSY bị bỏ qua. SRC, DST, LEN giữ giá trị đã ghi, địa chỉ đang chạy nằm bên trong.
- START xoá DONE và ERR. `LEN = 0` thì DONE bật ngay, không có giao dịch bus.
- Lỗi bus khi đọc hoặc ghi dừng DMA với ERR = 1 và DONE = 1. Các word trước lỗi đã được chép.
- `irq = DONE & IRQ_EN`, qua 1 flop, vào IRQC bit 4. Phần mềm xoá bằng cách ghi 1 vào bit DONE của STATUS.
- Quy trình: ghi SRC, DST, LEN, ghi CTRL = 1 (hoặc 3 nếu dùng ngắt), chờ DONE hoặc ngắt, đọc ERR, ghi STATUS = 2 để xoá DONE.
