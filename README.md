# SoC RISC-V RV32I – Cadence GPDK 45nm

Đồ án Chuyên đề 1: thiết kế SoC lõi RV32I (pipeline 3 tầng IF/EX/WB) cùng SRAM, accelerator Lab 2, Timer, UART, GPIO, chạy tối thiểu 50 MHz, đi hết flow RTL → signoff.

- Kế hoạch & phân công: https://docs.google.com/document/d/1RTnc3nwBibMsJxE9xoW7YXAB-516pJ7H3GNWsbQHur8/edit
- Theo dõi tiến độ: https://docs.google.com/spreadsheets/d/1xDhI0274hMBTG_rTxtYcNM3uWLCWMau0yEdtHtpaCv0/edit
- Repo: https://github.com/NguyenDinhNhatNguyen/RV32i-SoC

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

## Chạy thử nhanh (ở nhà)

```sh
make sim-accel      # testbench wrapper accelerator (Icarus Verilog)
```
