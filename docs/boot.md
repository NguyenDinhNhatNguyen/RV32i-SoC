# Bootloader UART (P8)

Chủ: Nhân. Boot ROM 1 KB ở 0x0001_0000, là reset vector của core. Bootloader nhận chương trình qua UART, ghi từng segment vào IMEM hoặc DMEM rồi nhảy tới entry. Quyết định thiết kế: D-039, D-040 trong `docs/core_decisions.md`.

## 1. File

| File | Nội dung |
| --- | --- |
| `fw/boot/boot.S` | Bootloader, assembly thuần, chỉ dùng thanh ghi |
| `fw/boot/boot.ld` | ROM 1 KB ở 0x0001_0000, link lỗi nếu code không vừa |
| `scripts/gen_boot_rom.py` | ELF ra `rtl/mem/boot_rom_init.vh`, báo lỗi nếu quá 256 word |
| `scripts/uart_pack.py` | Đóng gói ELF (mỗi section một gói) hoặc `.bin` theo giao thức, hoặc gửi thẳng xuống board (pyserial) |
| `rtl/mem/boot_rom_init.vh` | Nội dung ROM, sinh bằng `make boot-gen`, không sửa tay |
| `tb/boot/tb_boot.v`, `tb/boot/hello.S`, `tb/boot/cprog.c` | Testbench bọc `soc_top` và hai chương trình thử (assembly, C) |

## 2. Chân strap

Bootloader đọc `gpio_i[0]` (GPIO `DATA_IN` bit 0) ngay sau reset.

| `gpio_i[0]` | Hành vi |
| --- | --- |
| 0 | Nhảy ngay về 0x0000_0000, không đụng UART. Giống boot ROM bản base |
| 1 | Boot qua UART: chờ MAGIC tối đa `TIMEOUT_CYCLES`, hết giờ thì nhảy về 0x0000_0000 |

- Board cần jumper kéo `gpio_i[0]` lên 1 khi muốn nạp chương trình. Sau khi boot, chương trình dùng chân này như GPIO bình thường.
- `tb_soc` có `PAD_IN[0] = 0` nên chạy thẳng IMEM, test cũ không chậm thêm (chỉ thêm khoảng 35 chu kỳ và 1 lần đọc APB).
- Trong lúc bootloader chạy, `mtvec` trỏ về nhánh nhảy IMEM. Bản build không có GPIO (ví dụ `tb_core_bus`) đọc GPIO bị lỗi bus, trap về nhánh này, kết quả giống strap 0.

## 3. Giao thức

Mọi số nhiều byte là little endian. UART 8N1.

| Hướng | Byte | Ý nghĩa |
| --- | --- | --- |
| PC → chip | `0xA5` MAGIC | Gửi lặp lại, cách nhau khoảng 2 ms, tới khi nhận READY |
| chip → PC | `0x3E` READY (`>`) | Bootloader đã thấy MAGIC |
| PC → chip | `0x5A` SYNC | Mở đầu gói. MAGIC thừa trước SYNC bị bỏ qua |
| PC → chip | addr (4 byte) | Địa chỉ nạp của segment |
| PC → chip | len (4 byte) | Số byte dữ liệu |
| PC → chip | entry (4 byte) | `0xFFFF_FFFF`: còn segment sau. Giá trị khác: gói cuối, địa chỉ nhảy tới |
| chip → PC | `0x06` ACK hoặc `0x15` NAK | Kiểm tra header |
| PC → chip | data (len byte) | Ghi thẳng vào IMEM hoặc DMEM qua cổng dữ liệu, từng word |
| PC → chip | crc (4 byte) | CRC-32 (như `zlib.crc32`) của addr, len, entry và data |
| chip → PC | ACK hoặc NAK | Kiểm tra CRC |

Mỗi segment là một gói (SYNC tới crc). Chương trình nhiều segment gửi lần lượt từng gói, chỉ gói cuối có entry thật.

Header hợp lệ khi:

- addr và len chia hết cho 4, len > 0.
- [addr, addr + len) nằm trọn trong IMEM (0x0000_0000, `SOC_IMEM_SIZE`) hoặc trọn trong DMEM (`SOC_DMEM_BASE`, `SOC_DMEM_SIZE`). Đoạn vượt cuối vùng bị NAK.
- entry bằng `0xFFFF_FFFF`, hoặc chia hết cho 4 và nằm trong IMEM.

Không hợp lệ thì NAK ngay sau header, bộ nhớ không bị ghi.

Sau ACK của gói có `entry = 0xFFFF_FFFF`, bootloader quay về chờ SYNC của gói kế. Sau ACK của gói cuối, nó chờ ACK ra hết đường truyền, chạy `fence.i` rồi nhảy tới entry. Trước khi nhảy nó xoá `mtvec` và các thanh ghi đã dùng (trừ `t0` giữ địa chỉ nhảy). UART giữ BAUDDIV của bootloader, CTRL như reset.

Sau NAK, bootloader quay về chờ SYNC, không còn timeout. PC gửi lại từ SYNC. Gói lỗi không bao giờ được chạy.

## 4. Sơ đồ trạng thái

```text
 reset
   │
   ▼
 STRAP ── gpio_i[0] = 0 hoặc lỗi bus ──────────────────────────────┐
   │ gpio_i[0] = 1                                                  │
   ▼                                                                │
 INIT UART (BAUDDIV, CTRL, bỏ byte cũ, xoá cờ lỗi)                  │
   │                                                                │
   ▼                                                                ▼
 WAIT_MAGIC ── hết TIMEOUT_CYCLES (mcycle) ───────────────► RUN_IMEM (nhảy 0x0)
   │ nhận MAGIC (byte khác bị bỏ)
   ▼
 gửi READY
   │
   ▼
 WAIT_SYNC ◄──────────────── gửi NAK ◄──────────────┐
   │ nhận SYNC (byte khác bị bỏ)                    │
   ▼                                                │
 HEADER (addr, len, entry) ── sai ──────────────────┤
   │ đúng, gửi ACK                                  │
   ▼                                                │
 DATA (ghi IMEM/DMEM, tính CRC) ─► CRC ── sai ──────┘
                              │ đúng, gửi ACK
                              ├── entry = 0xFFFF_FFFF ──► WAIT_SYNC (segment kế)
                              ▼
                       fence.i, nhảy tới entry
```

## 5. Tham số và kích thước

| Tham số make | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `BOOT_CLK_HZ` | 50000000 | Clock của SoC. `soc_top` không có tham số clock nên ghi ở đây |
| `BOOT_BAUD` | 115200 | BAUDDIV = round(CLK / (16 × BAUD)) = 27, bằng giá trị reset của UART |
| `BOOT_TIMEOUT` | 50000000 | Chu kỳ chờ MAGIC, 1 s ở 50 MHz, tối đa 2^31 |
| IMEM, DMEM | 16384, 16384 ở 0x1000_0000 | Lấy từ `SOC_IMEM_SIZE`, `SOC_DMEM_BASE`, `SOC_DMEM_SIZE` trong `rtl/bus/soc_map.vh` |

- ROM: 143 / 256 word (572 byte). Bootloader không dùng DMEM cho chính nó, không dùng stack.
- Đổi tham số: `make boot-gen BOOT_TIMEOUT=100000000`, rồi chạy lại `make sim-boot` và commit `boot_rom_init.vh`.

## 6. Thời gian nạp

Mỗi byte 10 bit. Ở 115200 baud là 86,8 µs mỗi byte. Mỗi gói có 17 byte phụ (SYNC, addr, len, entry, crc), cả luồng thêm 1 byte MAGIC.

| Chương trình | Byte truyền | Thời gian |
| --- | --- | --- |
| `hello.S` (24 word), đo trong `rtl_load` | 113 từ SYNC tới ACK | 496 232 chu kỳ = 9,9 ms ở 50 MHz |
| `cprog.c` (4 segment, 380 byte dữ liệu) | 449 | 39 ms |
| Đầy IMEM 16 KB | 16 402 | 1,42 s |

Bootloader xử lý một byte (đọc UART, CRC từng bit, ghi IMEM) trong khoảng 100 chu kỳ, nhỏ hơn nhiều so với 4320 chu kỳ của một byte ở 115200 baud. ROM mô phỏng chạy với BAUDDIV 1 (160 chu kỳ mỗi byte) vẫn đúng.

## 7. Cách chạy

```sh
scripts/eda.sh run "make boot-gen"     # build boot.S, sinh lại rtl/mem/boot_rom_init.vh
scripts/eda.sh run "make sim-boot"     # 7 test, khoảng 1 phút (T=timeout chạy một test)
```

`sim-boot` build lại ROM từ `boot.S` và báo FAIL nếu khác file đã commit. Phần lớn test dùng ROM mô phỏng từ cùng mã nguồn, chỉ khác timeout 20 000 chu kỳ và BAUDDIV 1, để chạy nhanh. ROM này đứng trước `rtl/mem` trong `-I` nên `boot_rom.v` include nó.

| Test | ROM | Kiểm tra |
| --- | --- | --- |
| `load` | mô phỏng | MAGIC tới sau 10 000 chu kỳ, nạp `hello` vào 0x2000, chạy PASS |
| `celf` | mô phỏng | Nạp `cprog.elf`: `.text` vào IMEM, `.rodata`, `.data`, `.tohost` vào DMEM. Chương trình kiểm biến toàn cục khởi tạo khác 0, mảng hằng, chuỗi hằng, `.bss` bằng 0, in "boot ok" |
| `badcrc` | mô phỏng | CRC sai thì NAK sau dữ liệu, gửi lại gói đúng thì PASS |
| `badaddr` | mô phỏng | NAK cho addr = 0x4000, gói vượt cuối IMEM, addr lệch 0x1002, addr = boot ROM, gói vượt cuối DMEM, addr = 0x1000_4000, entry trong DMEM, entry lệch. Không ghi bộ nhớ. Gói kết thúc đúng ở cuối IMEM (0x3F00, 256 byte) thì PASS |
| `timeout` | mô phỏng | Không gửi gì, nhảy về 0x0 sau 20 000 chu kỳ, chạy `hello` nạp sẵn, PASS |
| `fastboot` | đã commit | Strap 0, nhảy về 0x0 trong 40 chu kỳ, PASS |
| `rtl_load` | đã commit | Nạp ở 115200 baud thật, PASS |

Mỗi test còn kiểm: số lần ghi IMEM/DMEM đúng len / 4 cho mỗi gói, bootloader không gửi byte thừa, chương trình in đúng "boot ok", lần lấy lệnh đầu tiên ngoài ROM đúng địa chỉ.

Nạp trên board:

```sh
python3 scripts/uart_pack.py prog.elf --port /dev/ttyUSB0               # rồi nhấn reset
python3 scripts/uart_pack.py prog.bin --addr 0x0 --port /dev/ttyUSB0    # file .bin, một gói
```

Với ELF, `uart_pack.py` gửi mỗi section có nội dung (`.text`, `.rodata`, `.data`, ...) thành một gói đúng địa chỉ chạy của nó, theo thứ tự địa chỉ, gói cuối mang entry của ELF. `.bss` không gửi, crt0 tự xoá. Chương trình link bằng `fw/common/link.ld` (địa chỉ nạp bằng địa chỉ chạy) nạp được trực tiếp.

## 8. Việc cho người khác

- Phát: rule vvp của `fw-bus`, `fw-soc` không phụ thuộc `rtl/mem/boot_rom_init.vh`, nên đổi ROM xong phải xoá `tb/soc/out/**/*.vvp` thì mới build lại. Rule của `bench-soc` và `sim-boot` đã có phụ thuộc này.
- Phát: nếu đổi `PAD_IN` của `tb_soc` thì giữ bit 0 bằng 0. Bit 0 bằng 1 thì mọi test chờ timeout 1 s và hết thời gian mô phỏng.
