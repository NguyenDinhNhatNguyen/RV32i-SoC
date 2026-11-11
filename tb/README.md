# Testbench

| Thư mục | Nội dung | Lệnh |
| --- | --- | --- |
| `unit/` | Testbench từng khối, tự so với mô hình vàng | `make unit-core`, `make unit-bus`, `make unit-periph`, `make check` |
| `core/` | `tb_core`: lõi với bộ nhớ lý tưởng, chạy firmware và riscv-tests | `make fw-core`, `make isa-core`, `make bench-core` |
| `soc/` | `tb_core_bus` (lõi và bus), `tb_soc` (toàn SoC) | `make fw-bus`, `make fw-soc` |
| `boot/` | `tb_boot`: bootloader UART trên `soc_top` | `make sim-boot` |
| `models/` | Mô hình SRAM dùng khi mô phỏng, thay macro thật. Mô hình slave I2C (`i2c_slave_model.v`) cho `tb_i2c_apb` và `tb_soc` | |
| `riscof/` | Plugin RISCOF cho riscv-arch-test | `make arch-core` |

Mỗi testbench in một dòng `PASS: ...` khi đạt, hoặc dòng bắt đầu bằng `FAIL` hay `ERROR` khi sai. Kết quả và sóng ghi vào `*/out/` (bị ignore). Preset GTKWave cho accelerator: `unit/accel.gtkw`.
