# Bootloader UART (P8)

Chủ: Nhân. Boot ROM 1 KB ở 0x0001_0000, là reset vector của core. Bootloader nhận chương trình qua UART, ghi vào IMEM rồi nhảy tới. Quyết định thiết kế: D-039 trong `docs/core_decisions.md`.

## 1. File

| File | Nội dung |
| --- | --- |
| `fw/boot/boot.S` | Bootloader, assembly thuần, chỉ dùng thanh ghi |
| `fw/boot/boot.ld` | ROM 1 KB ở 0x0001_0000, link lỗi nếu code không vừa |
| `scripts/gen_boot_rom.py` | ELF ra `rtl/mem/boot_rom_init.vh`, báo lỗi nếu quá 256 word |
| `scripts/uart_pack.py` | Đóng gói `.bin` theo giao thức, hoặc gửi thẳng xuống board (pyserial) |
| `rtl/mem/boot_rom_init.vh` | Nội dung ROM, sinh bằng `make boot-gen`, không sửa tay |
| `tb/boot/tb_boot.v`, `tb/boot/hello.S` | Testbench bọc `soc_top` và chương trình thử |

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
| PC → chip | addr (4 byte) | Địa chỉ nạp, cũng là địa chỉ nhảy tới |
| PC → chip | len (4 byte) | Số byte dữ liệu |
| chip → PC | `0x06` ACK hoặc `0x15` NAK | Kiểm tra header |
| PC → chip | data (len byte) | Ghi thẳng vào IMEM qua cổng dữ liệu, từng word |
| PC → chip | crc (4 byte) | CRC-32 (như `zlib.crc32`) của addr, len và data |
| chip → PC | ACK hoặc NAK | Kiểm tra CRC |

Header hợp lệ khi: addr và len chia hết cho 4, len > 0, addr < kích thước IMEM, addr + len ≤ kích thước IMEM. Không hợp lệ thì NAK ngay sau header, IMEM không bị ghi.

Sau ACK cuối, bootloader chờ ACK ra hết đường truyền, chạy `fence.i` rồi nhảy tới addr. Trước khi nhảy nó xoá `mtvec` và các thanh ghi đã dùng (trừ `t0` giữ địa chỉ nhảy). UART giữ BAUDDIV của bootloader, CTRL như reset.

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
 HEADER (addr, len) ── sai ─────────────────────────┤
   │ đúng, gửi ACK                                  │
   ▼                                                │
 DATA (ghi IMEM, tính CRC) ─► CRC ── sai ───────────┘
                              │ đúng, gửi ACK
                              ▼
                       fence.i, nhảy tới addr
```

## 5. Tham số và kích thước

| Tham số make | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `BOOT_CLK_HZ` | 50000000 | Clock của SoC. `soc_top` không có tham số clock nên ghi ở đây |
| `BOOT_BAUD` | 115200 | BAUDDIV = round(CLK / (16 × BAUD)) = 27, bằng giá trị reset của UART |
| `BOOT_TIMEOUT` | 50000000 | Chu kỳ chờ MAGIC, 1 s ở 50 MHz, tối đa 2^31 |
| IMEM | 16384 | Lấy từ `SOC_IMEM_SIZE` trong `rtl/bus/soc_map.vh` |

- ROM: 127 / 256 word (508 byte). Không dùng DMEM, không dùng stack.
- Đổi tham số: `make boot-gen BOOT_TIMEOUT=100000000`, rồi chạy lại `make sim-boot` và commit `boot_rom_init.vh`.

## 6. Thời gian nạp

Mỗi byte 10 bit. Ở 115200 baud là 86,8 µs mỗi byte. Gói có 14 byte phụ (MAGIC, SYNC, addr, len, crc).

| Chương trình | Byte truyền | Thời gian |
| --- | --- | --- |
| `hello.S` (24 word), đo trong `rtl_load` | 109 từ SYNC tới ACK | 478 926 chu kỳ = 9,6 ms ở 50 MHz |
| Đầy IMEM 16 KB | 16 398 | 1,42 s |

Bootloader xử lý một byte (đọc UART, CRC từng bit, ghi IMEM) trong khoảng 100 chu kỳ, nhỏ hơn nhiều so với 4320 chu kỳ của một byte ở 115200 baud. ROM mô phỏng chạy với BAUDDIV 1 (160 chu kỳ mỗi byte) vẫn đúng.

## 7. Cách chạy

```sh
scripts/eda.sh run "make boot-gen"     # build boot.S, sinh lại rtl/mem/boot_rom_init.vh
scripts/eda.sh run "make sim-boot"     # 6 test, khoảng 2 phút (T=timeout chạy một test)
```

`sim-boot` build lại ROM từ `boot.S` và báo FAIL nếu khác file đã commit. Phần lớn test dùng ROM mô phỏng từ cùng mã nguồn, chỉ khác timeout 20 000 chu kỳ và BAUDDIV 1, để chạy nhanh. ROM này đứng trước `rtl/mem` trong `-I` nên `boot_rom.v` include nó.

| Test | ROM | Kiểm tra |
| --- | --- | --- |
| `load` | mô phỏng | MAGIC tới sau 10 000 chu kỳ, nạp `hello` vào 0x2000, chạy PASS |
| `badcrc` | mô phỏng | CRC sai thì NAK sau dữ liệu, gửi lại gói đúng thì PASS |
| `badaddr` | mô phỏng | NAK cho addr = 0x4000, gói vượt cuối IMEM, addr lệch 0x1002, addr = boot ROM. Không ghi IMEM. Gói kết thúc đúng ở cuối IMEM (0x3F00, 256 byte) thì PASS |
| `timeout` | mô phỏng | Không gửi gì, nhảy về 0x0 sau 20 000 chu kỳ, chạy `hello` nạp sẵn, PASS |
| `fastboot` | đã commit | Strap 0, nhảy về 0x0 trong 40 chu kỳ, PASS |
| `rtl_load` | đã commit | Nạp ở 115200 baud thật, PASS |

Mỗi test còn kiểm: bootloader không gửi byte thừa, chương trình in đúng "boot ok", lần lấy lệnh đầu tiên ngoài ROM đúng địa chỉ.

Nạp trên board:

```sh
riscv64-unknown-elf-objcopy -O binary -j .text prog.elf prog.bin
python3 scripts/uart_pack.py prog.bin --addr 0x0 --port /dev/ttyUSB0   # rồi nhấn reset
```

Chương trình chạy từ IMEM có `.data` hoặc `.rodata` trong DMEM thì chưa nạp được bằng bản này, vì bootloader chỉ ghi IMEM.

## 8. Việc cho người khác

- Phát: `tb/unit/tb_imem_port.v` dòng 127 so ROM với nội dung bản base (word 0 = `jalr`, còn lại 0), nên `make unit-bus` FAIL 2 cấu hình với ROM mới. Nên lấy giá trị mong đợi từ `boot_rom_init.vh` (include vào một function `case`).
- Phát: rule vvp của `fw-bus`, `fw-soc` không phụ thuộc `rtl/mem/boot_rom_init.vh`, nên đổi ROM xong phải xoá `tb/soc/out/**/*.vvp` thì mới build lại. Rule của `bench-soc` và `sim-boot` đã có phụ thuộc này.
- Phát: nếu đổi `PAD_IN` của `tb_soc` thì giữ bit 0 bằng 0. Bit 0 bằng 1 thì mọi test chờ timeout 1 s và hết thời gian mô phỏng.
