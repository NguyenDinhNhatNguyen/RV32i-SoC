# Môi trường làm việc ở nhà (HT-04)

Trường không mở VPN, nên ở nhà cả nhóm dùng bộ tool mã nguồn mở đóng gói trong Docker image **IIC-OSIC-TOOLS** (Icarus, Verilator, GTKWave, Yosys, OpenROAD, KLayout, toolchain RISC-V, Spike). Cả nhóm dùng **cùng một tag image `2026.10`** để không lệch phiên bản. Số liệu chính thức cho report vẫn lấy trên server Cadence.

Cần: Windows 10 bản 19044 trở lên hoặc Windows 11, RAM từ 8 GB, ổ đĩa trống ít nhất 25 GB (image nén khoảng 4 GB, giải nén cần khoảng 20 GB).

## 1. Cài WSL2 và Docker (Windows, làm một lần)

1. Mở PowerShell **Run as Administrator**:
   ```powershell
   wsl --install -d Ubuntu-24.04
   wsl --update
   ```
   Khởi động lại máy, mở "Ubuntu 24.04" từ Start, đặt username/password cho Linux.
2. Cài Docker Desktop. Trong Settings: General bật "Use the WSL 2 based engine"; Resources > WSL integration bật cho Ubuntu-24.04. Bấm Apply & restart.
3. Trong cửa sổ Ubuntu kiểm tra:
   ```sh
   docker run --rm hello-world      # phải in "Hello from Docker!"
   ```

Máy macOS/Linux: chỉ cần cài Docker, làm tiếp từ mục 2 trong terminal thường.

**Quan trọng:** mọi lệnh từ đây trở đi gõ trong cửa sổ **Ubuntu (WSL)**, không gõ trong PowerShell. Không clone repo vào ổ `C:` (`/mnt/c/...`): chạy chậm và dễ hỏng file do ký tự xuống dòng kiểu Windows.

## 2. Lấy image và repo nhóm

```sh
# trong Ubuntu (WSL)
git config --global core.autocrlf input
git config --global user.name  "Ho Ten"
git config --global user.email "email@gmail.com"

mkdir -p ~/eda/designs && cd ~/eda
git clone --depth 1 https://github.com/iic-jku/IIC-OSIC-TOOLS.git
git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git designs/rv32i-soc

docker pull hpretl/iic-osic-tools:2026.10      # tải một lần, khá lâu
```

Thư mục `~/eda/designs` trong WSL sẽ hiện trong container là `/foss/designs`. Sửa code ở đâu cũng được (VS Code mở bằng lệnh `code ~/eda/designs/rv32i-soc` trong WSL), container thấy ngay.

## 3. Khởi động container

Cách khuyên dùng là **VNC qua trình duyệt** (ít lỗi đồ hoạ nhất trên Windows):

```sh
cd ~/eda/IIC-OSIC-TOOLS
DOCKER_TAG=2026.10 ./start_vnc.sh
```

Mở trình duyệt vào `http://localhost`, mật khẩu `abc123`. Sẽ thấy một desktop Linux, mở Terminal trong đó.

- Cổng 80 bị chiếm (lỗi "port is already allocated"): chạy `DOCKER_TAG=2026.10 WEBSERVER_PORT=8080 ./start_vnc.sh`, rồi mở `http://localhost:8080`.
- Lần sau chỉ cần chạy lại đúng lệnh trên; script tự khởi động lại container cũ. Tắt: `docker stop iic-osic-tools_xvnc_uid_$(id -u)`.
- Muốn cửa sổ GUI hiện thẳng trên Windows (WSLg) thì dùng `DOCKER_TAG=2026.10 ./start_x.sh`. Nếu GUI lỗi, quay về VNC.

## 4. Kiểm tra tool và chạy repo

Trong Terminal của container:

```sh
which iverilog verilator yosys gtkwave openroad klayout riscv64-unknown-elf-gcc spike
cd /foss/designs/rv32i-soc
make sim-accel          # phải in "PASS: 40 phep nhan ..."
make sim-accel-apb      # phải in "PASS: APB3 ..."
make lint-accel         # Verilator, không có %Warning là tốt
make wave-accel && gtkwave tb/unit/out/accel.vcd &
```

Đạt khi cả hai lệnh `sim` in PASS. Đây cũng là tiêu chí nghiệm thu HT-04: một người khác Nguyên làm theo file này từ đầu và ra PASS.

Thử tổng hợp nhanh bằng Yosys (chỉ xem số cell, không dùng cho report):

```sh
yosys -p "read_verilog rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v; synth -top accel_wrapper; stat"
```

Biên dịch firmware RV32I (toolchain trong image là bản multilib, có sẵn rv32i):

```sh
printf '#include "accel.h"\nstatic int8_t a[16], b[16]; static int32_t c[16];\nint main(void){ accel_matmul(a, b, c); return c[0]; }\n' > /tmp/t.c
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -O2 -Ifw -c /tmp/t.c -o /tmp/t.o && echo OK
```

## 5. Luyện thiết kế vật lý ở nhà (OpenROAD + nangate45)

Image không kèm nangate45, nhưng repo OpenROAD-flow-scripts (ORFS) có sẵn platform nangate45 và SRAM giả `fakeram45`, giống cấu trúc SoC của nhóm (logic + SRAM hard macro).

```sh
cd /foss/designs
git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts/flow
export OPENROAD_EXE=$(which openroad) YOSYS_EXE=$(which yosys)
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk         # thiết kế nhỏ, vài phút
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk gui_final
```

Nếu ORFS báo lỗi do lệch phiên bản OpenROAD trong image, dùng image chính thức của ORFS thay thế (chạy trong Ubuntu WSL, ngoài container IIC):

```sh
docker run --rm -it -v ~/eda/designs:/work openroad/orfs:latest bash
cd /OpenROAD-flow-scripts/flow && make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk
```

Sau khi `gcd` chạy được, tạo `designs/nangate45/accel/config.mk` cho wrapper accelerator để tập floorplan, CTS, route.

## 6. Lỗi thường gặp

| Triệu chứng | Cách xử lý |
| --- | --- |
| `docker: command not found` trong Ubuntu | Docker Desktop chưa bật WSL integration cho Ubuntu-24.04 (mục 1 bước 2) |
| `permission denied ... docker.sock` | Mở Docker Desktop trước, đợi biểu tượng cá voi hết chạy rồi thử lại |
| `$'\r': command not found` khi chạy script | Repo bị clone từ Windows. Xoá, chạy `git config --global core.autocrlf input`, clone lại trong WSL |
| Trình duyệt không vào được `localhost` | Xem lại cổng (mục 3), hoặc `docker logs iic-osic-tools_xvnc_uid_$(id -u)` |
| GTKWave/KLayout không hiện hoặc đen màn hình | Trong container: `export LIBGL_ALWAYS_SOFTWARE=1`, hoặc chuyển sang VNC |
| `make: iverilog: No such file` | Đang gõ ngoài container. Mở Terminal trong desktop VNC |
| Hết ổ đĩa | `docker system prune` để xoá image/cache cũ; giữ lại tag `2026.10` |

Không có Docker (máy yếu)? Có thể cài tool rời trong Ubuntu 24.04: `sudo apt install iverilog verilator gtkwave yosys make`, đủ cho `make sim-accel`. Phiên bản sẽ khác image, chỉ dùng tạm.

## 7. Ba điều không làm

- Không copy thư viện GPDK45, file SRAM macro hay license Cadence về máy cá nhân hay lên GitHub.
- Không đưa số liệu nangate45 vào report; chỉ dùng để xem xu hướng.
- Không sửa script Genus/Innovus để chạy ở nhà: hai bộ script khác nhau, chỉ SDC dùng chung.
