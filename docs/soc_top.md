# soc_top, bộ đồng bộ reset, DMA và SDC (RTL-09, RTL-15, STA-01)

Chủ: Phát. Đặc tả SoC ở `docs/spec/soc_spec.md`. Bus và bộ nhớ ở `docs/bus_mem.md`.

## 1. File

| File | Nội dung |
| --- | --- |
| `rtl/bus/soc_top.v` | Top của SoC: core, bus, bộ nhớ, Timer, UART, GPIO, IRQC, accelerator |
| `rtl/bus/reset_sync.v` | Bộ đồng bộ reset 2 flop |
| `rtl/bus/dma_apb.v` | DMA chép word (RTL-15), cổng cấu hình APB ở khe 8 và cổng master 1 của `sys_bus` |
| `tb/unit/tb_dma_apb.v` | Unit test DMA, chạy trong `make unit-bus` |
| `tb/soc/tb_soc.v` | Testbench mức SoC, chỉ nối chân của chip |
| `fw/tests/soc/soc.S` | Test Timer, ngắt, WFI, UART, GPIO, accelerator, IRQC, truy cập sai |
| `fw/tests/soc/dma.S` | Test DMA trong SoC (chỉ chạy với `ENABLE_DMA = 1`) |
| `scripts/soc_run.sh` | Chạy một bài trên `tb_soc`, gọi từ `make fw-soc` |
| `syn/constraints/soc.sdc` | SDC v1 của `soc_top` (STA-01), dùng chung Genus, Innovus, Tempus và OpenSTA |

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
                                                 ├─ khe 1 uart_apb ─── uart_rx/tx, irq ─► IRQC bit 0
                                                 ├─ khe 2 gpio_apb ─── gpio_i/o/oe
                                                 ├─ khe 6 irqc_apb ─── irq ─► irq_external của core
                                                 ├─ khe 7 accel_apb ── irq ─► IRQC bit 1
                                                 └─ khe 8 dma_apb ──── irq ─► IRQC bit 4 (ENABLE_DMA = 1)
 dma_apb ── cổng master ─► sys_bus master 1 (ENABLE_DMA = 1, trọng tài round-robin)
```

## 4. Các điểm thiết kế

### 4.1 Reset

- `reset_sync` có 2 flop. Assert bất đồng bộ: `rst_n` xuống 0 thì `rst_n_sync` xuống 0 ngay. Deassert đồng bộ: `rst_n_sync` lên 1 ở cạnh lên thứ hai sau khi `rst_n` lên 1.
- Mọi khối dùng `rst_n_sync`, không khối nào nối thẳng `rst_n`.
- Hai flop là hai thanh ghi riêng chứ không gộp thành vector. Gộp thì Verilator báo `SYNCASYNCNET`, vì bit 0 làm dữ liệu còn bit 1 làm reset bất đồng bộ.
- SDC (STA-01, mục 4.7): chỉ false path từ chân `rst_n` vào `u_rst`. Đường từ `u_rst/sync_q` tới chân reset của các flop khác được kiểm recovery/removal.

### 4.2 Ngắt và bộ đếm thời gian

| Cổng của core | Nối với |
| --- | --- |
| `irq_timer_i` | `timer_apb.irq_timer` (mtime ≥ mtimecmp) |
| `irq_software_i` | `timer_apb.irq_software` (MSIP) |
| `irq_external_i` | `irqc_apb.irq`. IRQC gom `irq` của UART (bit 0), accelerator (bit 1) và DMA (bit 4, khi `ENABLE_DMA = 1`). Bit 2, 3 (GPIO, SPI) tạm nối 0 |
| `mtime_i` | `timer_apb.mtime_o`, để CSR `time`, `timeh` đọc đúng mtime |

### 4.3 Khe APB

| Khe | Khối | Trạng thái |
| --- | --- | --- |
| 0 | Timer | Đã nối |
| 1 | UART | Đã nối (RTL-10) |
| 2 | GPIO | Đã nối, `W = 32` |
| 3, 4, 5 | SPI, I2C, PWM | Chưa có RTL (Tầng 1, 2) |
| 6 | IRQC | Đã nối (RTL-11) |
| 7 | Accelerator | Đã nối qua `accel_apb` |
| 8 | DMA | Đã nối khi `ENABLE_DMA = 1` (RTL-15). Với `ENABLE_DMA = 0` khe trả err |

Khe chưa có RTL có bit `APB_EN = 0` nên `apb_bridge` trả err mà không tạo giao dịch APB.

Thêm một khối mới vào `soc_top`, ví dụ SPI (làm giống cách đã nối UART, IRQC):

1. Khởi tạo khối, nối `psel[SOC_APB_SPI]`, `penable`, `pwrite`, `paddr`, `pwdata`.
2. Nối `prdata`, `pready`, `pslverr` của khe vào chỗ đang gán giá trị rảnh.
3. Thêm bit `SOC_APB_SPI` vào `APB_EN`.
4. Nếu khối có ngắt: nối vào `irq_src[SOC_IRQ_SPI]` thay cho giá trị 0.

### 4.4 Tham số

| Tham số | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `ENABLE_M` | 1 | RV32M (đã pass rv32um, RTL-12) |
| `ENABLE_WFI_SLEEP` | 1 | WFI cho core ngủ thật |
| `ENABLE_DMA` | 0 | DMA và master thứ 2 của `sys_bus` (RTL-15, Tầng 2). Để 0 cho tới khi review 8/11 mở Tầng 2 |
| `GPIO_W` | 32 | Số chân GPIO. `gpio_apb` chỉ lint sạch với 32 |

Kích thước IMEM, DMEM lấy từ `SOC_IMEM_BANK_W`, `SOC_DMEM_BANK_W` trong `rtl/bus/soc_map.vh`.

### 4.5 DMA (RTL-15)

- Thanh ghi ở `docs/spec/periph.md` mục 7. DMA chép `LEN` word từ `SRC` sang `DST`, địa chỉ tăng 4 sau mỗi word, chép tiến từng word nên chồng vùng vẫn có kết quả xác định.
- Mỗi word là một lệnh đọc rồi một lệnh ghi trên `sys_bus`, đủ 4 byte (`be = 4'b1111`). Vì vậy DMA chép được giữa DMEM, IMEM (qua cổng dữ liệu) và vùng APB truy cập theo word như bộ đệm accelerator.
- Lệnh kế tiếp được phát ngay trong chu kỳ có phản hồi (luật 3), nên khi chỉ có DMA dùng bus thì mỗi word mất 2 chu kỳ (`tb_dma_apb` kiểm con số này).
- Core và DMA chia bus qua trọng tài round-robin của `sys_bus`. Cả bus chỉ có 1 yêu cầu chờ phản hồi, nên khi CPU đọc `STATUS` liên tục để chờ thì DMA chậm lại. Trong `dma.S`, chép 64 word DMEM sang DMEM mất 268 chu kỳ khi CPU đọc `STATUS` để chờ, còn vòng lặp `lw`/`sw` của CPU mất 448 chu kỳ. Chờ bằng ngắt (IRQC bit 4) thay cho đọc `STATUS` thì DMA chạy gần 2 chu kỳ mỗi word.
- Lỗi bus (địa chỉ không ánh xạ, `PSLVERR`) dừng DMA với `ERR = 1` và `DONE = 1`.

### 4.6 Sửa file của người khác

| File | Sửa | Lý do |
| --- | --- | --- |
| `rtl/periph/timer_apb.v` | Thêm cổng `mtime_o = {mtime_hi, mtime_lo}` | Core cần `mtime_i` cho CSR `time`. Không đổi hành vi cũ, `tb_timer_apb` vẫn PASS |
| `rtl/periph/gpio_apb.v` | Thêm dòng trống cuối file | Verilator báo `EOFNEWLINE`, lint của `soc_top` FAIL |
| `rtl/periph/uart_apb.v`, `uart_fifo.v` | Thêm `` `timescale 1ns/1ps `` | Verilator báo `TIMESCALEMOD` vì các file khác đều có, lint của `soc_top` FAIL. `tb_uart_apb` vẫn PASS |

IRQC (`rtl/periph/irqc_apb.v`, `tb/unit/tb_irqc_apb.v`) do Phát viết cho RTL-11, theo khuôn `gpio_apb` và thanh ghi đã chốt ở `soc_spec.md` mục 5. Gán bit theo macro `SOC_IRQ_*` thêm vào `soc_map.vh`. `tb_irqc_apb` chưa có target Makefile, giống các testbench Timer, GPIO, UART (VER-02).

### 4.7 Ràng buộc thời gian (SDC v1, STA-01)

File `syn/constraints/soc.sdc`. Mỗi ràng buộc có chú thích lý do ngay trong file.

| Ràng buộc | Giá trị | Ghi chú |
| --- | --- | --- |
| Clock `clk` | Chu kỳ 20 ns (50 MHz), duty 50% | Một miền clock |
| Uncertainty | Setup 0,15 ns, hold 0,08 ns | Giống Lab 01 và `accel.sdc` |
| Clock transition | 0,08 ns | Chỉ dùng trước CTS, sau CTS tool dùng clock thật |
| Input delay | Max 4,8 ns, min 0,3 ns cho `gpio_i[*]`, `uart_rx` | Khoảng 24% chu kỳ như Lab. Hai chân này bất đồng bộ, đi thẳng vào bộ đồng bộ 2 flop |
| Output delay | Max 4,0 ns, min 0,2 ns cho `gpio_o[*]`, `gpio_oe[*]`, `uart_tx` | Khoảng 20% chu kỳ. Mọi ngõ ra đều lấy từ flop |
| Input slew, output load | `set_input_transition 0,1`, `set_load -pin_load 0,05` | Không ghi tên cell thư viện, để chạy được cả GPDK45 lẫn Nangate45 |
| Reset | `set_false_path -from rst_n`, kèm input delay 0 | `rst_n` chỉ vào 2 flop của `u_rst`. Đường deassert từ `u_rst` tới chân reset các flop là đường thường, tool kiểm recovery và removal |

Khác với `accel.sdc`:
- Không dùng `remove_from_collection`, vì OpenSTA không có lệnh này. Cổng được liệt kê bằng tên.
- Không dùng `set_driving_cell -lib_cell INVX2`, vì `INVX2` là tên cell của GPDK45, không có trong Nangate45.

Xem recovery và removal:
- Tempus, Innovus: `report_timing -check_type recovery` và `-check_type removal`.
- OpenSTA: `report_checks -path_group asynchronous` (OpenSTA 3.1 bật sẵn kiểm này).

Kiểm thử ở nhà (26/10). Tổng hợp `soc_top` bằng flow Nangate45 của Nhân (`syn/yosys/synth_nangate.tcl`, macro SRAM để hộp đen, khoảng 11 phút), rồi chạy OpenSTA với `soc.sdc`:
- OpenSTA đọc `soc.sdc` không lỗi. `check_setup -verbose` không báo gì: không còn cổng thiếu delay, không có endpoint thiếu ràng buộc.
- Recovery và removal được kiểm trên 2917 chân reset (nhóm `asynchronous`). Recovery đạt, slack 4,91 ns.
- Removal báo âm (-2,56 ns). Đây là do netlist ở nhà, không phải do SDC: Yosys không chèn buffer cho mạng `rst_n_sync`, một flop lái thẳng 2917 chân nên slew lên 11,75 ns và thư viện ngoại suy thời gian removal thành 14,9 ns. Genus sẽ chèn buffer theo giới hạn transition và fanout của thư viện, Innovus dựng cây buffer cho mạng này. Kết quả chính thức lấy từ Genus và Tempus (STA-02, STA-05).
- Setup và hold của nhóm `clk` đều đạt ở 20 ns. Đường qua macro SRAM chưa được tính vì ở nhà macro không có `.lib`.
- Số liệu Nangate45 chỉ để xem xu hướng, không dùng cho report.

Lưu ý cho STA-02 và PD: mạng `rst_n_sync` có fanout khoảng 2900. Cần xem `report_timing -check_type recovery/removal` và max transition của mạng này sau Genus và sau CTS.

## 5. Kiểm chứng ở nhà

```sh
scripts/eda.sh run "make lint-soc"   # Verilator -Wall, 8 cấu hình ENABLE_M x ENABLE_WFI_SLEEP x ENABLE_DMA
scripts/eda.sh run "make fw-soc"     # smoke, hazard, soc.S, bus.S, dma.S, riscv-tests trên soc_top
```

Kết quả ngày 26/10 (sau khi thêm DMA). `fw-soc` dựng M0W0 với `ENABLE_DMA = 0` và M1W1 với `ENABLE_DMA = 1`, nên cả hai cách đều được chạy:

| Lệnh | Kết quả |
| --- | --- |
| `make lint-soc` | 0 warning ở cả 8 cấu hình |
| `make fw-soc` | 127/127 PASS: `smoke`, `hazard`, `soc`, `bus`, rv32ui, rv32mi (M0W0 và M1W1), rv32um và `dma` (M1W1) |
| `make unit-bus` | 8/8 PASS, gồm `tb_dma_apb` (thử thêm seed 2, 3, 7) |
| Yosys `synth -top soc_top` | Không cảnh báo, không latch, đủ 8 macro, cả `ENABLE_DMA = 0` và `1` |
| Test cũ | `fw-bus` 124/124, `tb_timer_apb`, `tb_gpio_apb`, `tb_uart_apb`, `tb_irqc_apb`, `eda.sh check`, `lint-core`, `unit-core`, `fw-core`, `isa-core` vẫn PASS |

`tb_soc` kiểm bộ đồng bộ reset trước khi chạy chương trình: nhả reset giữa chu kỳ thì `rst_n_sync` lên 1 đúng ở cạnh thứ hai, kéo reset xuống giữa chu kỳ thì `rst_n_sync` xuống 0 ngay.

`tb_soc` nối `uart_tx` vòng về `uart_rx`. Bộ giải mã 8N1 của tb đọc `uart_tx` theo `BAUDDIV` hiện tại, in ký tự ra log và báo FAIL nếu start bit hoặc stop bit sai.

`soc.S` kiểm:

- Timer: mtime chạy, CSR `time`/`timeh` khớp mtime sau khi ghi `MTIME_LO`/`MTIME_HI`.
- Ngắt timer đánh thức WFI: với `ENABLE_WFI_SLEEP = 1` core ngủ 286 chu kỳ.
- Ngắt phần mềm qua MSIP, handler xoá nguồn ngắt tại ngoại vi.
- UART: `CTRL`, `BAUDDIV` sau reset, gửi "soc ok" qua TX và nhận lại đủ ở RX, không có cờ OVR, FE, TXOVF. Log in ra "soc ok".
- GPIO: `DIR`, `DATA_OUT`, `DATA_IN` đọc lại qua pad của tb, ghi `DATA_IN` thành store access fault.
- Accelerator: nhân ma trận 4x4 đúng kết quả tính sẵn.
- IRQC: giá trị reset, `ENABLE` chỉ giữ 5 bit, `PENDING` thấy nguồn accelerator kể cả khi `ENABLE` tắt và không có ngắt, bật `ENABLE` thì có ngắt ngoài (`mcause = 0x8000000B`). Ngắt ngoài từ UART khi nhận byte (`RXIE`), handler đọc `DATA` để xoá. Mỗi lần chỉ vào handler đúng 1 lần.
- `sb` vào UART, ghi `PENDING` của IRQC, offset lạ của Timer, UART, IRQC thành access fault.

`dma.S` kiểm: giá trị reset, `LEN = 0`, chép DMEM sang DMEM so với vòng lặp CPU (in số chu kỳ ra UART), DMEM sang bộ đệm A/B của accelerator rồi kết quả C_BUF về DMEM, DMA ghi vào IMEM, CPU đọc ghi DMEM trong lúc DMA chạy, ghi `SRC` khi bận bị bỏ qua, ngắt DMA qua IRQC, lỗi bus và offset lạ.

`tb_dma_apb` kiểm DMA riêng với mô hình slave có wait state và trễ ngẫu nhiên: 200 lần chép ngẫu nhiên (có chồng vùng), luật bus 1, 3 ở cổng master, lỗi bus khi đọc và khi ghi, `LEN = 0`, ghi khi bận, ghi 1 để xoá, `irq`, 2 chu kỳ mỗi word.

Đã cấy thử 15 lỗi vào DMA và phần nối DMA (phát yêu cầu khi chưa có ready, phát yêu cầu khi còn chờ phản hồi, sai số word, không tăng địa chỉ, bỏ qua lỗi đọc, cho ghi khi bận, START không xoá ERR, `LEN = 0` vẫn chạy, `irq` bỏ qua `IRQ_EN`, `be` thiếu byte, không giữ `wdata`, ghi 1 để xoá sai bit, tắt khe DMA, hở ngắt DMA, hở `err` của master DMA). Bắt được cả 15.

Đã cấy thử 22 lỗi vào bản sao `soc_top`, `reset_sync` và `irqc_apb`: mtime nối 0, hở `irq_timer`, hở `irq_software`, tắt khe GPIO, hở `gpio_i`, Timer nhận nhầm PSEL của GPIO, tắt khe accelerator, tắt khe UART, hở `uart_rx`, hở `uart_tx`, UART nhận nhầm PSEL của GPIO, reset chỉ 1 flop, reset assert đồng bộ, core dùng reset chưa đồng bộ, tắt khe IRQC, hở `irq_external`, hở bit accelerator, hở bit UART, đổi chỗ bit UART và accelerator, IRQC bỏ qua `ENABLE`, cho ghi `PENDING`, `ENABLE` reset về 1. `tb_soc` bắt được cả 22.

## 6. Còn lại

- GPIO chưa có ngõ ra ngắt, bit 2 của IRQC đang nối 0.
- Bật `ENABLE_DMA` mặc định hay không: nhóm quyết ở review 8/11 (Tầng 2).
- STA-02 (Phát): script Genus cho `soc_top` dùng `soc.sdc` (cần `sram_2k_macro.lib`), kiểm 0 unconstrained endpoint và recovery/removal sau khi Genus chèn buffer.
- Trên server: Genus cho `soc_top` (cần `sram_2k_macro.lib`), GLS với `sram_2k_macro.v` thật.
