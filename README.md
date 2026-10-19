# SoC RISC-V RV32I – Cadence GPDK 45nm

Đồ án Chuyên đề 1: thiết kế SoC lõi RV32I (pipeline 3 tầng IF/EX/WB) cùng SRAM, accelerator Lab 2, Timer, UART, GPIO, chạy tối thiểu 50 MHz, đi hết flow RTL → signoff.

- Kế hoạch & phân công: <https://docs.google.com/document/d/1RTnc3nwBibMsJxE9xoW7YXAB-516pJ7H3GNWsbQHur8/edit>
- Theo dõi tiến độ: <https://docs.google.com/spreadsheets/d/1xDhI0274hMBTG_rTxtYcNM3uWLCWMau0yEdtHtpaCv0/edit>
- Repo: <https://github.com/NguyenDinhNhatNguyen/RV32i-SoC>

## Cấu trúc thư mục

| Thư mục | Nội dung | Chủ |
| --- | --- | --- |
| `rtl/core` | Lõi RV32I | Nhân |
| `rtl/bus`, `rtl/mem` | Interconnect, wrapper SRAM, soc_top | Phát |
| `rtl/periph` | Timer, UART, GPIO, SPI, PWM, I2C | Phúc |
| `rtl/accel` | Wrapper accelerator Lab 2 | Nguyên |
| `tb/unit`, `tb/soc` | Testbench khối và mức SoC | Hiếu (+ chủ khối) |
| `fw` | Firmware, linker script, crt0 | Hiếu |
| `syn` | Script Genus, SDC | Phát |
| `pnr` | Script Innovus | Nguyên |
| `lec`, `sta`, `power` | Conformal, Tempus, Voltus | Phúc, Phát, Hiếu/Nguyên |
| `scripts` | Script tiện ích (kiểm tra server...) | Cả nhóm |
| `docs` | Spec, hướng dẫn môi trường | Cả nhóm |
| `ref` | Thiết kế tham chiếu (PicoRV32) | Nhân |
| `appendix/<bước>/` | Log, report chính thức đưa vào phụ lục | Cả nhóm |

## Quy ước

- RTL viết Verilog-2001, đồng bộ, không latch, không gated clock bằng tay, reset bất đồng bộ assert / đồng bộ deassert.
- Mỗi tính năng mở rộng có parameter bật/tắt (`ENABLE_M`, `ENABLE_DMA`, `ENABLE_SPI`...).
- Mỗi người một nhánh (`feat/<tên>-<việc>`), merge vào `main` qua pull request có ít nhất 1 người review.
- **Không commit thư viện GPDK45, file LIB/LEF/GDS của SRAM macro hay bất kỳ file nào của Cadence.** Script chỉ trỏ tới đường dẫn trên server qua biến môi trường (xem `pnr/scripts/config.tcl`).
- Log/report chính thức copy vào `appendix/<bước>/`. Thư mục chạy tool (`syn/run`, `pnr/run`...) bị bỏ qua bởi `.gitignore`.

## Làm việc nhà ↔ trường

Trường không mở VPN, nên Cadence chỉ chạy khi lên trường. Ở nhà dùng môi trường mã nguồn mở theo `docs/setup_home.md` (bật container và chạy test bằng `scripts/eda.sh`). Lần đầu lên trường chạy `scripts/check_server.sh` để ghi lại đường dẫn thư viện, SRAM macro và phiên bản tool.

Hướng dẫn chạy chi tiết cho accelerator và flow Cadence: `docs/runbook_nguyen.md`.

## Tự kiểm tra ở nhà

Cài môi trường một lần theo `docs/setup_home.md`. Mỗi lần kiểm tra, gõ trong cửa sổ Ubuntu (WSL) hoặc terminal VS Code:

### 1. Vào repo, lấy bản mới

```sh
cd ~/eda/designs/rv32i-soc
git pull
```

### 2. Bật container

```sh
scripts/eda.sh status     # "Dang chay" thì sang bước 3 luôn
scripts/eda.sh start      # nếu báo "Khong chay"
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
PASS: 40 phep nhan ma tran 4x4 khop mo hinh vang
PASS: APB3 - 10 phep nhan va 4 kiem tra PSLVERR dung
```

### 4. Tổng hợp thử bằng Yosys

Để xem số cell và cảnh báo latch. Không dùng số liệu này cho report.

```sh
scripts/eda.sh run 'yosys -p "read_verilog rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v; synth -top accel_wrapper; stat" | grep -E "^Warning|cells$"'
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
