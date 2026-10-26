# Script tiện ích

| Script | Việc | Chạy ở |
| --- | --- | --- |
| `eda.sh` | Bật, tắt container và chạy lệnh trong đó (`start`, `status`, `check`, `run`, `wave`, `stop`) | Nhà (WSL) |
| `core_run.sh`, `bus_run.sh`, `soc_run.sh` | Chạy một bài mô phỏng, được `make fw-*` gọi | Container |
| `arch_run.sh` | Chạy một bài riscv-arch-test | Container |
| `elf2hex.py` | Tách ELF thành ảnh IMEM, DMEM cho `$readmemh` | Container |
| `gen_boot_rom.py` | ELF của bootloader ra `rtl/mem/boot_rom_init.vh` (`make boot-gen`) | Container |
| `uart_pack.py` | Đóng gói `.bin` theo giao thức bootloader, hoặc gửi xuống board | Bất kỳ |
| `isa_status.py` | Lập bảng kết quả riscv-tests | Container |
| `yosys_summary.sh`, `get_nangate45.sh` | Tóm tắt Yosys, tải thư viện Nangate45 mở | Container |
| `ppa_table.py` | Gom số PPA từ report Genus, Innovus | Bất kỳ |
| `check_server.sh` | Ghi lại tool và PDK trên server (HT-01) | Server trường |
| `macro_info.sh` | Tóm tắt SRAM macro, không copy file thư viện | Server trường |
