# Regression và coverage (VER-05)

Chạy toàn bộ test của RTL bằng một lệnh, đo coverage của `soc_top`, xác nhận RTL freeze 15/11.

## Cách chạy

Ở nhà, trong Docker của nhóm. Cần đủ submodule (`riscv-tests`, `riscv-arch-test`, `coremark`).

```sh
cd ~/eda/designs/rv32i-soc
git submodule update --init --recursive
scripts/eda.sh start
scripts/eda.sh run "make regress CLEAN=1"
scripts/eda.sh run "make cov-soc"
```

- `make regress` chạy lần lượt 15 target, mỗi target một log trong `tb/regress/`. Bảng kết quả ở `tb/regress/summary.txt`. Đạt khi dòng cuối là `REGRESS PASS`.
- `CLEAN=1` xoá hết kết quả mô phỏng cũ trước khi chạy, nên mọi thứ được build lại từ mã nguồn. Mất khoảng 12 phút.
- `QUICK=1` bỏ 3 target chậm (`arch-core-dut`, `bench-core`, `bench-soc`), còn khoảng 4 phút. Dùng sau mỗi lần merge.
- `LIST="fw-soc sim-boot"` chỉ chạy các target đã chọn.
- Một target lỗi thì các target sau vẫn chạy. Target đạt khi `make` trả về 0 và log không có dòng bắt đầu bằng `FAIL`.
- `make cov-soc` chạy sau `make regress`, vì nó dùng lại các file hex mà `fw-soc`, `fw-soc-c` và `bench-soc` tạo ra.

## Các target trong regression

| Target | Phủ | Mô phỏng |
| --- | --- | --- |
| `lint-all` | Verilator `-Wall` cho accel, core, bus, periph, `soc_top` (9 cấu hình) | Verilator |
| `unit-core` | ALU, regfile, decoder, imm_gen, lsu_align, CSR, muldiv, BTB | Icarus |
| `unit-bus` | `sys_bus`, `apb_bridge`, `sram_wrap`, `imem_port`, `dma_apb` | Icarus |
| `unit-periph` | Timer, GPIO, UART, IRQC, SPI, PWM, I2C | Icarus |
| `sim-accel`, `sim-accel-apb` | Accelerator so với golden, qua wrapper và qua APB | Icarus |
| `fw-core` | Test assembly của core trên `tb_core` (hazard, trap, ngắt, WFI, nhân chia) | Icarus |
| `isa-core` | riscv-tests rv32ui, rv32mi, rv32um trên `tb_core`, 4 chế độ bus | Icarus |
| `fw-bus` | Test assembly và riscv-tests qua `sys_bus` và SRAM | Icarus |
| `fw-soc` | `soc.S`, `spi_pwm.S`, `i2c.S`, `dma.S`, `bus.S` và riscv-tests trên `soc_top` | Icarus |
| `fw-soc-c` | Firmware C trên `soc_top` (`docs/fw_soc_c.md`) | Icarus |
| `sim-boot` | Bootloader UART: nạp, ELF C, CRC sai, địa chỉ sai, timeout, strap | Icarus |
| `arch-core-dut` | riscv-arch-test 3.10.0, phía core, chạy và ghi signature | Icarus |
| `bench-core`, `bench-soc` | Dhrystone, CoreMark tự kiểm CRC, accelerator so phần mềm | Icarus |

`arch-core-dut` không so signature với Spike vì trong Docker chưa có `riscof`. Lần so với Spike gần nhất ở `docs/riscof.md` (`make arch-core`).

## Kết quả regression (17/11/2026)

Commit `3289802` của `main`, có RTL bỏ các bit thanh ghi hằng của uart, spi, i2c và core (`513611d`, PR #12). Cộng thêm các script của VER-05 chưa commit lúc chạy (chỉ thêm `scripts/regress.sh`, `scripts/soc_cov.sh` và target Makefile, RTL không đổi). Verilator 5.052, Icarus 14.0, GCC 16.1. Lần chạy 13/11 trên `fa432dc` cũng ra 15/15 PASS.

| Target | Kết quả | Thời gian |
| --- | --- | ---: |
| `lint-all` | PASS 5/5 | 4 s |
| `unit-core` | 11/11 | 53 s |
| `unit-bus` | 8/8 | 2 s |
| `unit-periph` | 7/7 | 0 s |
| `sim-accel` | 40 phép nhân 4 × 4 khớp golden | 0 s |
| `sim-accel-apb` | 10 phép nhân và 4 lần PSLVERR đúng | 0 s |
| `fw-core` | 112/112 | 13 s |
| `isa-core` | 472/472 | 10 s |
| `fw-bus` | 124/124 | 3 s |
| `fw-soc` | 131/131 | 4 s |
| `fw-soc-c` | 2/2 | 25 s |
| `sim-boot` | 7/7 | 44 s |
| `arch-core-dut` | 118/118 | 28 s |
| `bench-core` | 4/4 | 195 s |
| `bench-soc` | 6/6 | 453 s |
| **Tổng** | **15/15 target PASS** | 834 s |

Bảng gốc ở `appendix/ver05_regress/regress_summary.txt`.

## Coverage `soc_top`

`make cov-soc` build `tb_soc` bằng Verilator với `--coverage-line --coverage-toggle`, cấu hình `ENABLE_M=1`, `ENABLE_WFI_SLEEP=1`, `ENABLE_DMA=1` (bản M1W1 của `fw-soc`). Nó chạy lại 74 chương trình của cấu hình này:

- `soc.S`, `spi_pwm.S`, `i2c.S`, `dma.S`, `bus.S`, `smoke`, `hazard`
- 63 riscv-tests (rv32ui, rv32mi, rv32um)
- Firmware C `soc_fw_rv32im`
- Dhrystone, CoreMark và `accel_bench` bản rv32im

Cả 74 chương trình đều PASS trên Verilator. Như vậy RTL chạy đúng trên hai trình mô phỏng khác nhau (Icarus và Verilator).

Dòng PASS của `tb_soc` dùng chuỗi ghép `{"...", "..."}` làm định dạng của `$display`. Verilator in dòng này thành số. `scripts/soc_cov.sh` vì vậy coi một lần chạy là đạt khi tới `$finish` mà không có dòng `FAIL` hay `ERROR`. `tb_soc` chỉ gọi `$finish` trong `end_test`, và mọi trường hợp lỗi (timeout, trap, UART) đều in `FAIL`. Đã thử với một firmware cố tình sai: Verilator in đúng `FAIL ... (test 8)`.

### Kết quả (17/11/2026, `3289802`)

| | Điểm phủ | Tỉ lệ |
| --- | ---: | ---: |
| Line (khối lệnh của Verilator) | 354/371 | **95,4%** |
| Toggle (mỗi bit 0→1 và 1→0) | 18 112/22 532 | **80,4%** |

| Module | Line | Toggle |
| --- | ---: | ---: |
| `rv32_core.v` | 98,0% | 81,0% |
| `rv32_alu.v`, `rv32_lsu_align.v`, `rv32_muldiv.v` | 100% | 100% / 100% / 99,9% |
| `rv32_csr.v` | 96,4% | 55,0% |
| `rv32_decoder.v` | 92,0% | 99,5% |
| `rv32_btb.v` | 100% | 43,1% |
| `sys_bus.v`, `apb_bridge.v`, `sram_wrap.v` | 100% | 94,6% / 95,4% / 99,3% |
| `dma_apb.v` | 95,0% | 64,1% |
| `accel_wrapper.v`, `accelerator_top.v`, `pe.v` | 95,0% / 87,5% / 100% | 98,0% / 99,9% / 99,3% |
| `timer_apb.v`, `gpio_apb.v`, `irqc_apb.v` | 100% | 68,2% / 95,9% / 64,2% |
| `uart_apb.v` | 90,0% | 65,7% |
| `spi_apb.v`, `pwm_apb.v`, `i2c_apb.v` | 87,5% / 90,0% / 82,4% | 59,5% / 34,1% / 61,2% |

Bảng đủ 30 module ở `appendix/ver05_regress/cov_soc_summary.txt`.

### 15 dòng chưa phủ (17 điểm)

7 dòng là nhánh `default` của `case` đã liệt kê đủ giá trị, không thể tới được:

| Chỗ | Lý do |
| --- | --- |
| `accel_wrapper.v:97`, `accelerator_top.v:131` | `default` của FSM, mọi trạng thái đã có nhánh riêng |
| `rv32_imm_gen.v:24` | `default` của `case` theo kiểu immediate, mọi kiểu đã có nhánh |
| `i2c_apb.v:205`, `pwm_apb.v:47`, `spi_apb.v:137`, `uart_apb.v:285` | `default` của FSM hoặc của bộ giải mã địa chỉ đọc |

8 dòng là tình huống thật mà test mức SoC chưa tạo ra. Cột cuối ghi test khác có tạo tình huống đó hay không (tra trong mã testbench, chưa đo coverage):

| Chỗ | Tình huống | Test khác |
| --- | --- | --- |
| `rv32_core.v:322` | Lấy lệnh bị lỗi bus | Có: `fw/tests/asm/trap.S` trên `tb_core` (`fw-core`) |
| `rv32_decoder.v:180` | Lệnh SYSTEM đặc quyền không hợp lệ (không phải ECALL, EBREAK, MRET, WFI) | Có thể: `tb_rv32_decoder` thử các mã illegal viết tay và ngẫu nhiên |
| `dma_apb.v:151` | DMA đọc nhận phản hồi lỗi | Có: `tb_dma_apb` (`unit-bus`) |
| `uart_apb.v:236` | RX chờ đường dây lên 1 sau lỗi khung | Có thể: `tb_uart_apb` gửi khung sai stop bit |
| `rv32_csr.v:237`, `:246` | Ghi `mcycle`, `mcycleh` | Chưa thấy test nào |
| `uart_apb.v:101` | Tắt cả TX và RX cùng lúc | Chưa thấy test nào |
| `i2c_apb.v:143` | Lệnh đọc ngay sau START, không có ghi | Chưa chắc. `i2c.S` và `tb_i2c_apb` đọc sau repeated START |

Unit test chạy bằng Icarus nên chưa đo coverage. Không có điểm nào cho thấy lỗi chức năng. 3 tình huống "chưa thấy test nào" nên thêm vào test của chủ khối nếu còn thời gian sau freeze (chỉ thêm test, không đổi RTL).

### Toggle thấp

Toggle thấp hầu hết do bit không bao giờ đổi trong hệ thống này, không phải do thiếu test:

- `rv32_btb.v` (43%), `rv32_csr.v` (55%): tag BTB và các thanh ghi địa chỉ (`mepc`, `mtval`) có nhiều bit cao. IMEM chỉ 16 KB, nên các bit trên bit 14 của PC luôn bằng 0.
- Ngoại vi APB: các bit cao của `PWDATA`, `PRDATA` và của thanh ghi cấu hình ít khi dùng (chia tần UART, chu kỳ PWM 32 bit, giá trị so sánh timer 64 bit).
- `pwm_apb.v` (34%): bộ đếm 32 bit chỉ chạy vài chu kỳ PWM ngắn trong `spi_pwm.S`.

## Xác nhận RTL freeze

Ngày 17/11/2026, trên commit `3289802` của `main` (sau PR #12 bỏ bit hằng):

- 15/15 target regression PASS, build lại từ đầu.
- 74/74 chương trình SoC PASS trên Verilator, giống kết quả Icarus.
- Lint Verilator 0 warning (`docs/lint_status.md`). HAL không có lỗi ngoài `CBPAHI` đã waive.
- Line coverage `soc_top` 95,4%. 7 dòng chưa phủ là `default` không tới được, 8 dòng là tình huống hiếm, phần lớn đã có test riêng ngoài mức SoC.

RTL đủ điều kiện freeze. Sau 15/11, mọi thay đổi RTL phải chạy lại `make regress` và `make cov-soc`, rồi thêm một dòng vào bảng dưới.

| Ngày | Commit | Regression | Coverage line / toggle | Ghi chú |
| --- | --- | --- | --- | --- |
| 13/11 | `fa432dc` | 15/15 PASS | 95,4% / 80,3% | Lần đầu |
| 17/11 | `3289802` | 15/15 PASS | 95,4% / 80,4% | Sau `513611d` (bỏ bit thanh ghi hằng ở uart, spi, i2c, core). Cùng 15 dòng chưa phủ. Xác nhận RTL freeze |
