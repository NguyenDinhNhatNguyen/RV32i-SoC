# Tài liệu

Mục lục tài liệu của đồ án, xếp theo chủ đề. Kế hoạch, phân công và tiến độ nằm trên Google Doc và Sheet (link ở `README.md` gốc).

## Đặc tả

| File | Nội dung |
| --- | --- |
| `spec/requirements.md` | Yêu cầu đề bài và nơi đáp ứng |
| `spec/soc_spec.md` | Clock, reset, bus, bản đồ địa chỉ, bộ nhớ, ngắt, các quyết định đã chốt |
| `spec/periph.md` | Thanh ghi Timer, UART, GPIO, IRQC, DMA, SPI, PWM, I2C, boot ROM, chân ngoài của `soc_top` |
| `spec/accel.md` | Accelerator nhân ma trận: thanh ghi, firmware, ghép lõi Lab 2 |
| `spec/core.md` | Lõi RV32I: pipeline, CSR, ngắt, giao diện bus |

## Hướng dẫn

| File | Nội dung |
| --- | --- |
| `setup_home.md` | Cài môi trường ở nhà (WSL, Docker, VS Code) |
| `flow_notes.md` | Chạy flow Cadence ở trường, tiêu chí nghiệm thu, lỗi thường gặp |

## Ghi chú thiết kế

| File | Nội dung |
| --- | --- |
| `core_decisions.md` | Nhật ký quyết định thiết kế lõi |
| `bus_mem.md` | Bus hệ thống, wrapper SRAM, boot ROM |
| `soc_top.md` | Nối dây `soc_top`, bộ đồng bộ reset, DMA, SDC |
| `boot.md` | Bootloader UART trong boot ROM: chân strap, giao thức, cách nạp và test |
| `timing_bus.md` | Timing diagram bus |
| `sta_results.md` | Bảng kết quả các lần chạy STA của `soc_top` (ở trường và ở nhà) |
| `macro_notes.md` | SRAM macro qua từng bước flow |
| `genus_core.md` | Genus, Conformal, GLS cho `rv32_core` ở trường, quét chu kỳ tìm F_max |
| `pd02_floorplan.md` | Ước lượng die, đặt macro, pin plan, power plan |
| `pnr_soc_status.md` | Theo dõi các việc PnR của `soc_top` |
| `ir_drop.md` | IR drop tĩnh của `soc_top` bằng Voltus: cách chạy, kết quả 20/11, giới hạn (LEC-04, LEC-06) |
| `lec_soc.md` | LEC Conformal của `soc_top` và `apb_bridge`: flow, cách chạy, kết quả chạy thử (LEC-01) |

## Kiểm chứng và đánh giá

| File | Nội dung |
| --- | --- |
| `riscv-tests-status.md` | Kết quả riscv-tests và test assembly của lõi |
| `riscof.md` | riscv-arch-test qua RISCOF |
| `lint_status.md` | Quy trình lint sau mỗi lần merge, danh sách waiver, bảng kết quả (VER-03) |
| `regression.md` | `make regress` (15 target), coverage `soc_top` bằng Verilator, xác nhận RTL freeze (VER-05) |
| `gls_soc.md` | GLS netlist `soc_top` bằng `tb_soc -DGLS`, các bước ở nhà và trên server (VER-07), GLS có SDF sau layout (VER-08, mục 8) |
| `power_soc.md` | Công suất `soc_top` trước layout theo testcase (SAIF từ GLS) và theo toggle rate mặc định (PWR-01) |
| `fw_soc_c.md` | Firmware C trên `soc_top`: UART, GPIO, timer, ngắt, accelerator, rv32um (VER-04) |
| `bench_core.md` | Dhrystone, CoreMark trên `tb_core` |
| `bench_soc.md` | Dhrystone, CoreMark trên `soc_top`, speedup accelerator (EVA-01) |
| `timing_core.md` | Timing ước lượng của lõi (Nangate45, flow nhà) |
| `btb_eval.md` | Thử nghiệm dự đoán nhánh (tĩnh, BTB): CPI, diện tích, timing, đề xuất |
| `eva02_compare.md` | So `rv32_core` với PicoRV32 (cùng flow Genus), Ibex và SERV (số công bố) theo kGE, CoreMark/MHz, DMIPS/MHz (EVA-02) |
| `yosys_compare.md` | Tổng hợp thử bằng Yosys, so với PicoRV32 |

## Report

`report/` chứa bản nháp các chương report, `figures/` chứa hình và script vẽ hình.
