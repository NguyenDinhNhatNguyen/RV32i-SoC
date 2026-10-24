# soc_top và bộ đồng bộ reset (RTL-09)

Chủ: Phát. Đặc tả SoC ở `docs/spec/soc_spec.md`. Bus và bộ nhớ ở `docs/bus_mem.md`.

## 1. File

| File | Nội dung |
| --- | --- |
| `rtl/bus/soc_top.v` | Top của SoC: core, bus, bộ nhớ, Timer, UART, GPIO, accelerator |
| `rtl/bus/reset_sync.v` | Bộ đồng bộ reset 2 flop |
| `tb/soc/tb_soc.v` | Testbench mức SoC, chỉ nối chân của chip |
| `fw/tests/soc/soc.S` | Test Timer, ngắt, WFI, UART, GPIO, accelerator, khe trống |
| `scripts/soc_run.sh` | Chạy một bài trên `tb_soc`, gọi từ `make fw-soc` |

## 2. Chân của chip

| Chân | Hướng | Ý nghĩa |
| --- | --- | --- |
| `clk` | in | Clock duy nhất, mục tiêu 50 MHz |
| `rst_n` | in | Reset ngoài, tích cực thấp, bất đồng bộ |
| `gpio_i[31:0]`, `gpio_o[31:0]`, `gpio_oe[31:0]` | in, out, out | GPIO. `gpio_oe = 1` là ngõ ra, pad 3 trạng thái nối ở mức chip |
| `uart_rx`, `uart_tx` | in, out | UART 8N1, mặc định 115200 baud ở 50 MHz (`BAUDDIV = 27`) |

Tổng cộng 100 chân tín hiệu. Đây là danh sách cho pin plan (PD-02).

## 3. Sơ đồ nối

```text
 rst_n ─► reset_sync ─► rst_n_sync (mọi khối)

 rv32_core ── cổng lệnh ──────────────► imem_port (IMEM 4 macro + boot ROM)
     └─ cổng dữ liệu ─► sys_bus ─┬─► imem_port (cổng dữ liệu)
                                 ├─► sram_wrap (DMEM 4 macro)
                                 └─► apb_bridge ─┬─ khe 0 timer_apb ── irq_timer, irq_software, mtime ─► core
                                                 ├─ khe 1 uart_apb ─── uart_rx/tx, irq (chờ IRQC)
                                                 ├─ khe 2 gpio_apb ─── gpio_i/o/oe
                                                 └─ khe 7 accel_apb ── irq (chờ IRQC)
```

## 4. Các điểm thiết kế

### 4.1 Reset

- `reset_sync` có 2 flop. Assert bất đồng bộ: `rst_n` xuống 0 thì `rst_n_sync` xuống 0 ngay. Deassert đồng bộ: `rst_n_sync` lên 1 ở cạnh lên thứ hai sau khi `rst_n` lên 1.
- Mọi khối dùng `rst_n_sync`, không khối nào nối thẳng `rst_n`.
- Hai flop là hai thanh ghi riêng chứ không gộp thành vector. Gộp thì Verilator báo `SYNCASYNCNET`, vì bit 0 làm dữ liệu còn bit 1 làm reset bất đồng bộ.
- SDC (STA-01): chỉ false path từ chân `rst_n` vào `u_rst`. Đường từ `u_rst/sync_q` tới chân reset của các flop khác phải kiểm recovery/removal.

### 4.2 Ngắt và bộ đếm thời gian

| Cổng của core | Nối với |
| --- | --- |
| `irq_timer_i` | `timer_apb.irq_timer` (mtime ≥ mtimecmp) |
| `irq_software_i` | `timer_apb.irq_software` (MSIP) |
| `irq_external_i` | 0, chờ IRQC (RTL-11). `irq` của UART và accelerator đã kéo tới `soc_top` |
| `mtime_i` | `timer_apb.mtime_o`, để CSR `time`, `timeh` đọc đúng mtime |

### 4.3 Khe APB

| Khe | Khối | Trạng thái |
| --- | --- | --- |
| 0 | Timer | Đã nối |
| 1 | UART | Đã nối (RTL-10) |
| 2 | GPIO | Đã nối, `W = 32` |
| 3, 4, 5 | SPI, I2C, PWM | Chưa có RTL (Tầng 1, 2) |
| 6 | IRQC | Chưa có RTL (RTL-11) |
| 7 | Accelerator | Đã nối qua `accel_apb` |
| 8 | DMA | Chưa có RTL (Tầng 2) |

Khe chưa có RTL có bit `APB_EN = 0` nên `apb_bridge` trả err mà không tạo giao dịch APB.

Thêm một khối mới vào `soc_top`, ví dụ IRQC (làm giống cách đã nối UART):
1. Khởi tạo khối, nối `psel[SOC_APB_IRQC]`, `penable`, `pwrite`, `paddr`, `pwdata`.
2. Nối `prdata`, `pready`, `pslverr` của khe vào chỗ đang gán giá trị rảnh.
3. Thêm bit `SOC_APB_IRQC` vào `APB_EN`.
4. Với IRQC: nối `uart_irq`, `accel_irq` vào ngõ vào, ngõ ra vào `irq_external`.

### 4.4 Tham số

| Tham số | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `ENABLE_M` | 1 | RV32M (đã pass rv32um, RTL-12) |
| `ENABLE_WFI_SLEEP` | 1 | WFI cho core ngủ thật |
| `GPIO_W` | 32 | Số chân GPIO. `gpio_apb` chỉ lint sạch với 32 |

Kích thước IMEM, DMEM lấy từ `SOC_IMEM_BANK_W`, `SOC_DMEM_BANK_W` trong `rtl/bus/soc_map.vh`.

### 4.5 Sửa file của người khác

| File | Sửa | Lý do |
| --- | --- | --- |
| `rtl/periph/timer_apb.v` | Thêm cổng `mtime_o = {mtime_hi, mtime_lo}` | Core cần `mtime_i` cho CSR `time`. Không đổi hành vi cũ, `tb_timer_apb` vẫn PASS |
| `rtl/periph/gpio_apb.v` | Thêm dòng trống cuối file | Verilator báo `EOFNEWLINE`, lint của `soc_top` FAIL |
| `rtl/periph/uart_apb.v`, `uart_fifo.v` | Thêm `` `timescale 1ns/1ps `` | Verilator báo `TIMESCALEMOD` vì các file khác đều có, lint của `soc_top` FAIL. `tb_uart_apb` vẫn PASS |

## 5. Kiểm chứng ở nhà

```sh
scripts/eda.sh run "make lint-soc"   # Verilator -Wall, 4 cấu hình ENABLE_M x ENABLE_WFI_SLEEP
scripts/eda.sh run "make fw-soc"     # smoke, hazard, soc.S, bus.S, riscv-tests trên soc_top
```

Kết quả ngày 24/10 (sau khi nối UART):

| Lệnh | Kết quả |
| --- | --- |
| `make lint-soc` | 0 warning ở cả 4 cấu hình |
| `make fw-soc` | 126/126 PASS: `smoke`, `hazard`, `soc`, `bus`, rv32ui, rv32mi (M0W0 và M1W1), rv32um (M1W1) |
| Yosys `synth -top soc_top` | Không cảnh báo, không latch, đủ 8 macro |
| Test cũ | `fw-bus` 124/124, `unit-bus` 7/7, `tb_timer_apb`, `tb_gpio_apb`, `tb_uart_apb`, `eda.sh check`, `lint-core`, `unit-core`, `fw-core`, `isa-core` vẫn PASS |

`tb_soc` kiểm bộ đồng bộ reset trước khi chạy chương trình: nhả reset giữa chu kỳ thì `rst_n_sync` lên 1 đúng ở cạnh thứ hai, kéo reset xuống giữa chu kỳ thì `rst_n_sync` xuống 0 ngay.

`tb_soc` nối `uart_tx` vòng về `uart_rx`. Bộ giải mã 8N1 của tb đọc `uart_tx` theo `BAUDDIV` hiện tại, in ký tự ra log và báo FAIL nếu start bit hoặc stop bit sai.

`soc.S` kiểm:
- Timer: mtime chạy, CSR `time`/`timeh` khớp mtime sau khi ghi `MTIME_LO`/`MTIME_HI`.
- Ngắt timer đánh thức WFI: với `ENABLE_WFI_SLEEP = 1` core ngủ 286 chu kỳ.
- Ngắt phần mềm qua MSIP, handler xoá nguồn ngắt tại ngoại vi.
- UART: `CTRL`, `BAUDDIV` sau reset, gửi "soc ok" qua TX và nhận lại đủ ở RX, không có cờ OVR, FE, TXOVF. Log in ra "soc ok".
- GPIO: `DIR`, `DATA_OUT`, `DATA_IN` đọc lại qua pad của tb, ghi `DATA_IN` thành store access fault.
- Accelerator: nhân ma trận 4x4 đúng kết quả tính sẵn.
- Khe IRQC, `sb` vào UART, offset lạ của Timer và UART thành access fault.

Đã cấy thử 14 lỗi vào bản sao `soc_top` và `reset_sync`: mtime nối 0, hở `irq_timer`, hở `irq_software`, tắt khe GPIO, hở `gpio_i`, Timer nhận nhầm PSEL của GPIO, tắt khe accelerator, tắt khe UART, hở `uart_rx`, hở `uart_tx`, UART nhận nhầm PSEL của GPIO, reset chỉ 1 flop, reset assert đồng bộ, core dùng reset chưa đồng bộ. `tb_soc` bắt được cả 14.

## 6. Còn lại

- RTL-11 (Nhân, Phúc): IRQC ở khe 6, gom `irq` của UART và accelerator vào `irq_external_i`. GPIO hiện chưa có ngõ ra ngắt.
- STA-01 (Phát): SDC cho `soc_top` theo mục 4.1.
- Trên server: Genus cho `soc_top` (cần `sram_2k_macro.lib`), GLS với `sram_2k_macro.v` thật.
