# RTL

Verilog-2005 tổng hợp được: không `initial`, không latch, reset `rst_n` tích cực thấp. Đặc tả ở `docs/spec/`.

| Thư mục | Nội dung | Chủ |
| --- | --- | --- |
| `core/` | Lõi RV32I 3 tầng `rv32_core` (ALU, decoder, CSR, regfile, M extension) | Nhân |
| `bus/` | `soc_top`, `sys_bus`, cầu APB, đồng bộ reset, bản đồ địa chỉ `soc_map.vh` | Phát |
| `mem/` | Wrapper SRAM macro, cổng IMEM, boot ROM | Phát |
| `periph/` | Timer, UART, GPIO (APB3) | Phúc |
| `accel/` | Lõi Lab 2 và wrapper accelerator | Nguyên |

Kiểm tra lint: `make lint-core`, `make lint-bus`, `make lint-soc`, `make lint-accel`.
