# Môi trường làm việc ở nhà (HT-04)

Trường không mở VPN, nên ở nhà cả nhóm dùng bộ tool mã nguồn mở đóng gói trong Docker image **IIC-OSIC-TOOLS**. Mọi người dùng chung một image để không lệch phiên bản. Số liệu chính thức vẫn lấy trên server Cadence.

## 1. Cài WSL2 và Docker (Windows, làm một lần)

1. Mở PowerShell bằng quyền Administrator, chạy `wsl --install`, khởi động lại máy. Mặc định sẽ cài Ubuntu.
2. Cài Docker Desktop, trong Settings bật "Use the WSL 2 based engine" và bật tích hợp với distro Ubuntu.
3. Mở Ubuntu (WSL), kiểm tra: `docker run --rm hello-world`.

Máy macOS/Linux: chỉ cần cài Docker.

## 2. Lấy image và khởi động

```sh
# trong Ubuntu (WSL)
mkdir -p ~/eda && cd ~/eda
git clone --depth 1 https://github.com/iic-jku/IIC-OSIC-TOOLS.git
git clone <link repo nhóm> designs/soc-rv32i     # repo của nhóm
cd IIC-OSIC-TOOLS
./start_x.sh        # hoặc ./start_vnc.sh rồi mở trình duyệt theo hướng dẫn in ra
```

Image khá nặng (cỡ chục GB), lần đầu tải lâu, nên tải bằng mạng ổn định. Các script `start_*.sh` mount thư mục `~/eda/designs` vào container (thường tại `/foss/designs`). Nếu tên script hoặc đường dẫn khác, xem README của repo IIC-OSIC-TOOLS vì dự án cập nhật thường xuyên.

## 3. Kiểm tra tool trong container

```sh
which iverilog verilator yosys openroad klayout gtkwave
which riscv64-unknown-elf-gcc riscv32-unknown-elf-gcc spike   # có thể thiếu, xem mục 5
cd /foss/designs/soc-rv32i && make sim-accel                  # phải in "PASS"
```

## 4. Luyện thiết kế vật lý ở nhà (OpenROAD + nangate45)

Platform nangate45 của OpenROAD-flow-scripts có SRAM macro giả `fakeram45`, giống cấu trúc bài của nhóm (logic + SRAM hard macro).

```sh
cd /foss/designs
git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts/flow
# dùng openroad/yosys có sẵn trong image thay vì build lại
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk        # chạy thử thiết kế nhỏ
```

Nếu `make` báo thiếu biến tool, đặt `OPENROAD_EXE`, `YOSYS_EXE` trỏ vào `$(which openroad)` và `$(which yosys)`. Sau khi `gcd` chạy được, tạo `designs/nangate45/accel/config.mk` cho wrapper accelerator để tập floorplan, đặt macro, CTS, route.

## 5. Toolchain RISC-V nếu image chưa có

Cài trong Ubuntu (WSL) hoặc container: `sudo apt install gcc-riscv64-unknown-elf` rồi biên dịch với `-march=rv32i_zicsr -mabi=ilp32`. Spike: `sudo apt install device-tree-compiler` rồi build từ https://github.com/riscv-software-src/riscv-isa-sim.

## 6. Ba điều không làm

- Không copy thư viện GPDK45, file SRAM macro hay license Cadence về máy cá nhân hay lên GitHub.
- Không đưa số liệu nangate45 vào report; chỉ dùng để xem xu hướng.
- Không sửa script Genus/Innovus để chạy ở nhà: hai bộ script khác nhau, chỉ SDC dùng chung.
