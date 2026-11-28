# SoC RISC-V RV32I – Cadence GPDK 45nm

Đồ án Chuyên đề 1: thiết kế SoC lõi RV32I (pipeline 3 tầng IF/EX/WB) cùng SRAM, accelerator Lab 2, Timer, UART, GPIO, chạy tối thiểu 50 MHz, đi hết flow RTL → signoff.

- Kế hoạch & phân công: <https://docs.google.com/document/d/1RTnc3nwBibMsJxE9xoW7YXAB-516pJ7H3GNWsbQHur8/edit>
- Theo dõi tiến độ: <https://docs.google.com/spreadsheets/d/1xDhI0274hMBTG_rTxtYcNM3uWLCWMau0yEdtHtpaCv0/edit>

## Kiến trúc

```text
rv32_core ── nạp lệnh ──► IMEM (4 macro) + boot ROM
    └─ dữ liệu ─► sys_bus ─┬─► DMEM (4 macro)
                           └─► cầu APB ─┬─ Timer, UART, GPIO, IRQC
                                        ├─ SPI, PWM, I2C
                                        ├─ Accelerator 4x4 (Lab 2)
                                        └─ DMA (master thứ 2 của sys_bus)
```

Đặc tả: [SoC](docs/spec/soc_spec.md), [ngoại vi](docs/spec/periph.md), [accelerator](docs/spec/accel.md), [lõi](docs/spec/core.md). Mục lục tài liệu: [docs/README.md](docs/README.md).

## Trạng thái (26/11)

Từ 28/11 nhóm làm thêm V2 (lõi 5 tầng, accelerator tự cộng dồn, xem Sheet). RTL trên `main` đã có thay đổi của V2. Bản V1 đã sign-off ở bảng dưới nằm ở tag `v1-signoff`, chạy lại hoặc kiểm V1 thì dùng tag này.

| Phần | Kết quả |
| --- | --- |
| Lõi RV32IM | riscv-tests 472/472, test assembly 112/112, unit 11/11. GLS có SDF 49/49, LEC 0 non-equivalent (lõi đứng riêng, 30/10) |
| Bus, SoC | fw-bus 124/124, fw-soc 131/131 (có SPI, PWM, I2C), bootloader `sim-boot` PASS, lint 0 warning |
| Ngoại vi | Timer, UART, GPIO, IRQC, SPI, PWM, I2C đã ghép vào `soc_top` (I2C từ 10/11) |
| Accelerator | Mô phỏng PASS, flow Cadence chạy lại với lõi Lab 2 ngày 29/10, skew ≤ 80 ps |
| SoC qua Cadence | Genus và Tempus đạt 20 ns trên RTL đầy đủ (12/11). PnR tới route ngày 12/11 và thử ba cỡ lõi ngày 13/11 (`docs/pnr_soc_status.md`). F_max sau tổng hợp khoảng 200 MHz (14/11). Netlist chính thức tổng hợp và PnR ở 9 ns trên RTL `e60437a`. **Chốt 100 MHz (18/11)**: Tempus sau layout `_p9` ở 10 ns dư setup 0,977 ns, hold, recovery, removal đều dương (`docs/sta_results.md` mục 5, 6). LEC RTL ↔ netlist chính thức còn 1 điểm Non-equivalent được chấp nhận kèm chứng minh (`spi clk_cnt_reg[15]`, bit hằng 0), LEC netlist tổng hợp ↔ sau layout PASS (`docs/lec_soc.md`). Mốc M2 đạt 25/11 |
| Kiểm chứng mức cổng | GLS zero delay 71/71 trên netlist Genus (19/11). GLS có SDF sau layout ở 10 ns 71/71, 0 vi phạm timing sau khi reset nhả (26/11). GLS hai góc max (slow) và min (fast) 71/71 mỗi góc (VER-09, 26/11, `docs/gls_soc.md`) |
| Công suất, IR drop | Trước layout theo testcase 0,31 đến 0,48 mW ở 100 MHz, toggle mặc định 0,74 mW (`docs/power_soc.md`). Sau layout 0,58 đến 0,96 mW (PWR-02). IR drop tĩnh VDD trên layout cuối sụt lớn nhất 1,69 mV, ngưỡng 45 mV (LEC-06, `docs/ir_drop.md`) |
| Layout cuối (26/11) | `_p9` sau PD-08 (`route_trim`): DRC 0, antenna 0, connectivity sạch, GDS đủ Metal1 đến Metal9. Tempus 4 view ở 10 ns setup +0,977, hold +0,020 ns (STA-06). LEC netlist tổng hợp ↔ layout cuối PASS (LEC-05). Bảng PPA ở `docs/eva03_ppa.md`, đánh giá ở `docs/eva05_eval.md` |

## Bắt đầu nhanh

```sh
git clone --recursive https://github.com/NguyenDinhNhatNguyen/RV32i-SoC.git rv32i-soc
# Clone rồi mà thiếu submodule: git submodule update --init --recursive
```

Cài môi trường theo [docs/setup_home.md](docs/setup_home.md), rồi chạy:

```sh
scripts/eda.sh check                                             # accelerator, 2 dòng PASS
scripts/eda.sh run "make lint-core unit-core fw-core isa-core"   # lõi
scripts/eda.sh run "make lint-bus unit-bus fw-bus lint-soc fw-soc"  # bus và SoC
scripts/eda.sh run "make help"                                   # danh sách target
```

Cách làm việc với Git, quy trình commit và cách tự kiểm RTL trước khi đánh "Xong" trên Sheet: [CONTRIBUTING.md](CONTRIBUTING.md).

## Cấu trúc thư mục

| Thư mục | Nội dung | Chủ |
| --- | --- | --- |
| [`rtl/core`](rtl/core) | Lõi RV32I | Nhân |
| [`rtl/bus`](rtl/bus), [`rtl/mem`](rtl/mem) | Interconnect, wrapper SRAM, soc_top | Phát |
| [`rtl/periph`](rtl/periph) | Timer, UART, GPIO, SPI, PWM, I2C | Phúc |
| [`rtl/accel`](rtl/accel) | Lõi Lab 2 và wrapper accelerator | Nguyên |
| [`tb`](tb) | Testbench khối, lõi và mức SoC | Hiếu (+ chủ khối) |
| [`fw`](fw) | Firmware, linker script, crt0, benchmark | Hiếu |
| [`syn`](syn) | Script Genus, SDC, Yosys thử ở nhà | Phát |
| [`pnr`](pnr) | Script Innovus | Nguyên |
| [`lec`](lec), [`sta`](sta), [`power`](power) | Conformal, Tempus, Voltus | Phúc, Phát, Hiếu/Nguyên |
| [`scripts`](scripts) | Script tiện ích (container, chạy test, kiểm tra server) | Cả nhóm |
| [`docs`](docs) | Spec, hướng dẫn, ghi chú thiết kế | Cả nhóm |
| [`ref`](ref) | Thiết kế tham chiếu (PicoRV32) | Nhân |
| [`appendix`](appendix) | Log, report chính thức đưa vào phụ lục | Cả nhóm |

Mỗi thư mục có `README.md` riêng ghi nội dung và lệnh chạy.

## Quy ước

- RTL viết Verilog-2005 (Genus đọc ở chế độ 2001, nên không khai báo `localparam` trong `generate`), đồng bộ, không latch, không gated clock bằng tay, reset bất đồng bộ assert / đồng bộ deassert.
- Mỗi tính năng mở rộng có parameter bật/tắt (`ENABLE_M`, `ENABLE_DMA`, `ENABLE_SPI`...).
- Comment trong code và output test viết tiếng Anh. Tài liệu trong `docs/` viết tiếng Việt.
- **Không commit thư viện GPDK45, file LIB/LEF/GDS của SRAM macro hay bất kỳ file nào của Cadence.** Script chỉ trỏ tới đường dẫn trên server (xem [`pnr/scripts/config.tcl`](pnr/scripts/config.tcl)).
- Log/report chính thức copy vào `appendix/<bước>/`. Thư mục chạy tool (`syn/run*`, `pnr/run*`...) bị bỏ qua bởi `.gitignore`.

## Làm việc nhà ↔ trường

Trường không mở VPN, nên Cadence chỉ chạy khi lên trường. Ở nhà dùng môi trường mã nguồn mở theo [docs/setup_home.md](docs/setup_home.md) (bật container và chạy test bằng `scripts/eda.sh`). Chạy flow Cadence ở trường theo [docs/flow_notes.md](docs/flow_notes.md).

## Tự kiểm tra ở nhà

Cài môi trường một lần theo [docs/setup_home.md](docs/setup_home.md). Mỗi lần kiểm tra, gõ trong cửa sổ Ubuntu (WSL) hoặc terminal VS Code:

### 1. Vào repo, lấy bản mới

```sh
cd ~/eda/designs/rv32i-soc
git pull
```

### 2. Bật container

```sh
scripts/eda.sh status     # "Running: ..." thì sang bước 3 luôn
scripts/eda.sh start      # nếu báo "Not running"
```

`start` có thể hỏi một câu và chờ bấm một phím:

| Thông báo | Nghĩa | Bấm |
| --- | --- | --- |
| Không hỏi gì | Chưa có container, đang tạo mới | — |
| `Press "s" to start, and "r" to remove` | Container có rồi nhưng đang tắt | `s` để bật (bấm Enter thì container vẫn tắt) |
| `Press "s" to stop, and "r" to stop & remove` | Container đang chạy rồi | Enter để giữ nguyên (bấm `s` là tắt container) |

`r` xoá container (code trong `~/eda/designs` không mất). Chỉ dùng khi container lỗi, xong chạy `scripts/eda.sh start` lại để tạo mới.

### 3. Lint và mô phỏng

```sh
scripts/eda.sh check
```

Đạt khi không có dòng `%Warning` và cuối cùng có 2 dòng:

```text
PASS: 40 matrix multiplies 4x4 match the golden model
PASS: APB3 - 10 multiplies and 4 PSLVERR checks correct
```

Sửa lõi, bus hoặc SoC thì chạy thêm hai lệnh ở mục "Bắt đầu nhanh". Mỗi target in dòng tổng kết dạng `... passed, 0 failed` hoặc `PASS`.

### 4. Tổng hợp thử bằng Yosys

Để xem số cell và cảnh báo latch. Không dùng số liệu này cho report.

```sh
scripts/eda.sh run 'yosys -p "read_verilog rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v; synth -top accel_wrapper; stat" | grep -E "^Warning|cells$"'
```

Đạt khi chỉ thấy các dòng `... cells` và không có dòng nào bắt đầu bằng `Warning`. Bỏ phần `| grep ...` để xem toàn bộ log.

### 5. Xem sóng (khi cần)

```sh
scripts/eda.sh wave
```

Mở `http://localhost:8080` (mật khẩu `abc123`) để xem GTKWave. Hoặc mở `tb/unit/out/accel.vcd` trong VS Code bằng extension VaporView.

### 6. Tắt container khi xong việc

```sh
scripts/eda.sh stop
```
