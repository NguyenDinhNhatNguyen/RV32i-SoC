# Bus hệ thống và bộ nhớ (RTL-03, RTL-08)

Chủ: Phát. Giao thức bus theo `docs/spec/core.md` mục 5.1. Bản đồ địa chỉ theo `docs/spec/soc_spec.md` mục 3. Timing diagram ở `docs/timing_bus.md`.

## 1. File

| File | Nội dung |
| --- | --- |
| `rtl/bus/soc_map.vh` | Bản đồ địa chỉ, chỉ số khe APB, số macro mặc định. Nguồn duy nhất cho mọi khối |
| `rtl/bus/sys_bus.v` | Interconnect valid/ready, giải mã địa chỉ, trọng tài round-robin `N_MASTER`, slave lỗi |
| `rtl/bus/apb_bridge.v` | Cầu bus sang APB3, 9 khe PSEL, khe tắt bằng `APB_EN` |
| `rtl/mem/sram_array.v` | Ghép 2^`BANK_W` macro `sram_2k_macro` thành một mảng |
| `rtl/mem/sram_wrap.v` | Slave valid/ready cho mảng SRAM (DMEM), đọc-sửa-ghi cho SB/SH |
| `rtl/mem/imem_port.v` | IMEM dùng chung cho cổng lệnh và bus dữ liệu, kèm boot ROM |
| `rtl/mem/boot_rom.v`, `boot_rom_init.vh` | Boot ROM 1 KB bằng logic, nội dung tách riêng để script sinh lại |
| `tb/models/sram_2k_macro.v` | Mô hình ở nhà của macro, đúng tên và chân macro thật |
| `tb/unit/tb_sys_bus.v`, `tb_apb_bridge.v`, `tb_sram_wrap.v`, `tb_imem_port.v` | Unit test |
| `tb/soc/tb_core_bus.v`, `fw/tests/bus/bus.S` | Core thật chạy trên bus và bộ nhớ |

## 2. Sơ đồ nối

```text
             cổng lệnh (if_*)
 rv32_core ─────────────────────────────► imem_port ── 4 macro IMEM + boot ROM
     │ cổng dữ liệu (d_*)                     ▲
     ▼                                        │ imem_req
  sys_bus (master 0, master 1 là DMA khi ENABLE_DMA = 1) ──┤
     │                                        │ dmem_req
     │                                        ▼
     │                                    sram_wrap ── 4 macro DMEM
     │ apb_req
     ▼
  apb_bridge ── PSEL[0..8] ── Timer, UART, GPIO, SPI, I2C, PWM, IRQC, accel_apb, DMA
```

## 3. Giải mã địa chỉ

`sys_bus` chọn slave bằng `addr[31:28]`.

| Vùng | Slave | Điều kiện, ngoài ra trả err |
| --- | --- | --- |
| 0x0 | IMEM (cổng dữ liệu của `imem_port`) | offset < kích thước IMEM. Boot ROM 0x0001_0000 không đọc được từ bus dữ liệu |
| 0x1 | DMEM | offset < kích thước DMEM |
| 0x2, 0x3, 0x4 | `apb_bridge` | Cầu tự giải mã khe |
| còn lại | Slave lỗi | Luôn err |

`apb_bridge` chọn khe:

| Địa chỉ | Khe (bit PSEL) | Khối |
| --- | --- | --- |
| 0x2000_0000 + n × 0x1000, n = 0..6 | n | Timer, UART, GPIO, SPI, I2C, PWM, IRQC |
| 0x3000_0000 .. 0x3000_0FFF | 7 | Accelerator (`accel_apb`) |
| 0x4000_0000 .. 0x4000_0FFF | 8 | DMA (`dma_apb`, Tầng 2, khi `ENABLE_DMA = 1`) |

PADDR là 12 bit offset trong khe, khớp `accel_apb`, `timer_apb`, `gpio_apb`.

Cầu trả err mà không tạo giao dịch APB khi: địa chỉ không thuộc khe nào, khe có `APB_EN = 0` (tính năng đang tắt), hoặc `be != 4'b1111`. APB3 không có PSTRB nên firmware truy cập ngoại vi bằng `lw`/`sw`. Ví dụ `putchar` phải ghi UART bằng `sw`, không dùng `sb`.

## 4. Các điểm thiết kế

### 4.1 sys_bus

- Cả bus tối đa 1 yêu cầu chờ phản hồi. Yêu cầu mới được nhận khi bus rảnh hoặc ngay trong chu kỳ có phản hồi. Với 1 master thì không mất chu kỳ nào so với nối thẳng (load liên tiếp vẫn 1 lệnh mỗi chu kỳ). Với 2 master, giao dịch của DMA và core xen kẽ nhau, đơn giản và luôn đúng thứ tự.
- Trọng tài round-robin. Khi yêu cầu đã hiện ra ở slave mà slave chưa nhận (wait state của SB/SH), quyền được giữ cho master đó. Nhờ vậy slave luôn thấy yêu cầu giữ nguyên (luật 1).
- `m_rsp_err` riêng từng master và bằng 0 khi không có `rsp_valid`, vì core dùng `d_rsp_err_i` không qua `d_rsp_valid_i`.
- Không có đường từ ready của slave ngược về valid của slave (luật 5).

### 4.2 Bộ nhớ

- Mặc định phương án C (spec SoC mục 7.2): IMEM 16 KB, DMEM 16 KB, mỗi vùng 4 macro. Đổi bằng `SOC_IMEM_BANK_W`, `SOC_DMEM_BANK_W` trong `soc_map.vh` (0 = 1 macro 4 KB, 1 = 8 KB, 2 = 16 KB). Nhớ sửa `fw/common/link.ld` và `tb/core/core_tb_map.vh` cho khớp.
- Bit địa chỉ cao chọn macro. Chỉ macro được chọn có `CEN = 0`, các macro khác tắt để tiết kiệm công suất. Mux chọn Q dùng bit chọn đã chốt ở chu kỳ đọc.
- SB/SH: đọc-sửa-ghi trong 2 chu kỳ (spec SoC mục 7.3). Đọc và SW vẫn 1 chu kỳ.
- `rsp_rdata = 0` với lệnh ghi, vì sau chu kỳ ghi Q của macro giữ giá trị cũ chứ không phải dữ liệu vừa ghi (mục 6).
- IMEM: bus được ưu tiên hơn lấy lệnh, IF dừng 1 chu kỳ. Lấy lệnh ở boot ROM không bị bus chặn.
- Boot ROM 1 KB ở 0x0001_0000, reset vector mặc định của core (spec SoC mục 7.1). Nội dung là bootloader UART của Nhân (`fw/boot/boot.S`), sinh vào `boot_rom_init.vh` bằng `scripts/gen_boot_rom.py` (`make boot-gen`), giữ định dạng `8'hNN: word = 32'hXXXXXXXX;`. Chân `gpio_i[0] = 0` thì nhảy thẳng về IMEM, bằng 1 thì nạp chương trình qua UART (`docs/boot.md`).

### 4.3 Các điểm spec SoC mục 7 mà RTL đang theo

Nhóm đã chốt cả 5 điểm ngày 25/10 (SP-01), đúng như RTL. Bảng dưới ghi chỗ cần đổi nếu sau này chọn khác.

| Điểm | RTL hiện tại | Đổi thế nào nếu nhóm chọn khác |
| --- | --- | --- |
| 7.1 Reset vector | Boot ROM 0x0001_0000 (bootloader UART, `gpio_i[0] = 0` thì nhảy về 0x0) | Đặt `RESET_PC = 0` ở core, boot ROM vẫn để đó |
| 7.2 IMEM, DMEM | 16 KB mỗi vùng | `SOC_*_BANK_W` |
| 7.3 SB, SH | Đọc-sửa-ghi | Không cần đổi |
| 7.4 Địa chỉ không ánh xạ | Trả err | Phải sửa slave lỗi trong `sys_bus` |
| 7.5 Accelerator | Qua `apb_bridge` + `accel_apb`, khe 7 | Không cần đổi |

## 5. Kiểm chứng ở nhà

```sh
scripts/eda.sh run "make lint-bus"   # Verilator -Wall, 11 cấu hình, 0 warning
scripts/eda.sh run "make unit-bus"   # 7 lần chạy unit test
scripts/eda.sh run "make fw-bus"     # core trên bus thật, cần submodule riscv-tests
```

Kết quả ngày 22/10:

| Lệnh | Kết quả |
| --- | --- |
| `make lint-bus` | 0 warning: `sys_bus` với N_MASTER = 1, 2, 4, `sram_array`, `sram_wrap`, `imem_port` với BANK_W = 0, 2, `apb_bridge`, `boot_rom` |
| `make unit-bus` | 7/7 PASS |
| `make fw-bus` | 124/124 PASS: `smoke`, `hazard`, `bus`, rv32ui, rv32mi (M0W0 và M1W1), rv32um (M1W1) |
| Yosys `synth` | Không cảnh báo, không latch |

Unit test kiểm tra:

- `tb_sys_bus`: 2 master, slave có wait state và trễ ngẫu nhiên, so dữ liệu và err với tham chiếu. Kiểm tra luật 1 và luật 3 ở cả phía master lẫn slave, địa chỉ không ánh xạ không tới slave nào và có err ở chu kỳ sau.
- `tb_apb_bridge`: slave có wait state và PSLVERR, khe tắt, truy cập không đủ word, giao thức APB3 (one-hot, SETUP rồi ACCESS, tín hiệu giữ nguyên khi PREADY = 0). Chạy một phép nhân ma trận trên `accel_apb` thật.
- `tb_sram_wrap`: đọc/ghi word, half, byte so với tham chiếu, đúng 1 wait state cho SB/SH, cổng đọc ưu tiên thấp.
- `tb_imem_port`: lấy lệnh ở IMEM, boot ROM, địa chỉ lỗi xen với bus dữ liệu ghi IMEM.

`tb_core_bus` chạy core từ boot ROM, qua `sys_bus` vào 8 macro mô phỏng. Test `bus.S` đọc INFO, nhân ma trận bằng accelerator, kiểm tra access fault cho từng loại lỗi bus, in "bus ok" qua UART giả.

Đã cấy thử 22 lỗi vào bản sao RTL (bỏ kiểm tra yêu cầu đang chờ, bỏ giữ quyền, err không chặn theo valid, bỏ kiểm tra kích thước DMEM, trả phản hồi sai master, slave lỗi trả chậm, bỏ kiểm tra be, bỏ `APB_EN`, rdata khác 0 khi ghi, bỏ pha SETUP, bỏ qua PREADY, sai khe accelerator, bỏ đọc-sửa-ghi, không ghép byte, lấy lệnh không nhường bus, rdata không chặn khi ghi, mux Q không chốt, boot ROM bị bus chặn, if_err tổ hợp, chọn ROM tổ hợp, sai nội dung ROM, chốt bit chọn macro cả khi ghi). Unit test bắt 21 lỗi. Lỗi cuối cùng tương đương về logic vì sau chu kỳ ghi wrapper không dùng Q.

## 6. Trên server

- Genus: thêm `sram_2k_macro.lib` vào `read_libs`, `init_hdl_search_path` gồm `rtl/bus` và `rtl/mem` (cho file `.vh`). Không đọc `tb/models/sram_2k_macro.v`.
- Xcelium (GLS): dùng `~/PDK_GPDK45/lib/sram_2k_macro.v` thay cho mô hình ở nhà.
- Hành vi Q của macro thật (đọc model `.v` trên server bằng `scripts/macro_info.sh` ngày 30/10): Q chỉ đổi ở chu kỳ đọc. Ở chu kỳ ghi và khi `CEN = 1`, Q giữ giá trị cũ. Wrapper không dựa vào hai hành vi này (lệnh ghi trả `rsp_rdata = 0`), nên đúng với macro thật. Mô hình ở nhà cho Q thành X khi ghi, chặt hơn macro thật, nên giữ nguyên.

## 7. Việc còn lại cho người khác

- RTL-09 (Phát): đã có `soc_top` và bộ đồng bộ reset, xem `docs/soc_top.md`.
- Phúc: ngoại vi APB nối vào khe theo bảng mục 3. PREADY của khe trống nối 1.
- Nhân: bootloader UART đã sinh lại `boot_rom_init.vh` (D-039, D-040). `tb_imem_port` đọc word kỳ vọng từ chính file này.
- Hiếu: firmware ghi ngoại vi bằng `sw`/`lw`. Testbench SoC nạp chương trình vào mô hình macro như `tb_core_bus`.
