# Script tiện ích

| Script | Việc | Chạy ở |
| --- | --- | --- |
| `eda.sh` | Bật, tắt container và chạy lệnh trong đó (`start`, `status`, `check`, `run`, `wave`, `stop`) | Nhà (WSL) |
| `core_run.sh`, `bus_run.sh`, `soc_run.sh` | Chạy một bài mô phỏng, được `make fw-*` gọi | Container |
| `bench_soc_run.sh` | Chạy một benchmark trên `tb_soc`, được `make bench-soc` gọi | Container |
| `gls_core.sh` | GLS netlist `rv32_core` với `tb_core -DGLS`, rv32ui và rv32um (`make gls-core`, `docs/genus_core.md`) | Server trường |
| `arch_run.sh` | Chạy một bài riscv-arch-test | Container |
| `elf2hex.py` | Tách ELF thành ảnh IMEM, DMEM cho `$readmemh` | Container |
| `gen_boot_rom.py` | ELF của bootloader ra `rtl/mem/boot_rom_init.vh` (`make boot-gen`) | Container |
| `uart_pack.py` | Đóng gói ELF (mỗi section một gói) hoặc `.bin` theo giao thức bootloader, hoặc gửi xuống board | Bất kỳ |
| `isa_status.py` | Lập bảng kết quả riscv-tests | Container |
| `yosys_summary.sh`, `get_nangate45.sh` | Tóm tắt Yosys, tải thư viện Nangate45 mở | Container |
| `ppa_table.py` | Gom số PPA từ report Genus, Innovus | Bất kỳ |
| `check_server.sh` | Ghi lại tool và PDK trên server (HT-01) | Server trường |
| `macro_info.sh` | Tóm tắt SRAM macro, không copy file thư viện | Server trường |
| `save_reports.sh` | Chép report văn bản vào `appendix/`, bỏ qua netlist, SPEF, GDS (`make save-pnr-soc`) | Server trường |
| `regress.sh` | Chạy toàn bộ regression, in bảng PASS/FAIL (`make regress`, VER-05) | Container |
| `gls_soc.sh` | GLS netlist `soc_top` với `tb_soc -DGLS` (`make gls-soc`, VER-07) | Server (xrun), container (Icarus) |
| `gls_paths.py` | Tìm 8 macro SRAM trong netlist, ghi `gls_paths.vh` cho `tb_soc` | Cả hai |
| `power_soc.sh` | Genus tính công suất cho từng SAIF và toggle rate mặc định, bảng `summary.md` (`make power-soc`, PWR-01) | Server |
| `soc_cov.sh` | Coverage line và toggle của `soc_top` bằng Verilator (`make cov-soc`, VER-05) | Container |
| `hal_lint.sh` | Lint HAL cho `soc_top`, đếm thông báo theo mức và rule (`make lint-hal`, VER-03) | Server trường |
