# Môi trường làm việc ở nhà (HT-04)

Trường không mở VPN, nên ở nhà cả nhóm dùng bộ tool mã nguồn mở trong Docker image **IIC-OSIC-TOOLS** (Icarus, Verilator, GTKWave, Yosys, OpenROAD, KLayout, toolchain RISC-V). Cả nhóm dùng **cùng tag `2026.10`** và **cùng cổng 8080** để hướng dẫn giống nhau trên mọi máy. Số liệu chính thức cho report vẫn lấy trên server Cadence.

Hướng dẫn này là đúng các bước đã chạy được trên máy Nguyên (Windows 11, Ubuntu 26.04 trên WSL, Docker Desktop 4.55, dữ liệu Docker để ở ổ D).

**Cần:** Windows 10 bản 19044 trở lên hoặc Windows 11, RAM từ 8 GB, một ổ còn trống ít nhất 25 GB (nên dùng ổ D nếu ổ C chật).

**Có hai loại cửa sổ dòng lệnh, đừng nhầm:**

| | Cửa sổ Ubuntu (WSL) | Terminal trong container |
| --- | --- | --- |
| Mở từ | Start menu > Ubuntu, hoặc terminal của VS Code ở chế độ **WSL: Ubuntu** | Desktop Linux ở `http://localhost:8080`, hoặc VS Code đã **Attach** vào container |
| Dấu nhắc | `ten@MAY:~$` | `/foss/designs/... >` hoặc `$` |
| Đường dẫn repo | `~/eda/designs/rv32i-soc` | `/foss/designs/rv32i-soc` |
| Dùng cho | `git`, `docker`, `scripts/eda.sh` | `make`, `iverilog`, `verilator`, `gtkwave` |

Hai đường dẫn là **cùng một thư mục**: sửa bên này, bên kia thấy ngay.

## 1. Cài WSL và Docker (làm một lần)

1. Mở **PowerShell** (Run as Administrator) và chạy:
   ```powershell
   wsl --install
   wsl --update
   ```
   Khởi động lại máy, mở **Ubuntu** từ Start menu, đặt username và password cho Linux. Bản Ubuntu nào cũng được (24.04, 26.04...).
2. Cài **Docker Desktop**, mở lên, rồi vào Settings (bánh răng):
   - **General**: bật "Use the WSL 2 based engine".
   - **Resources > WSL integration**: bật công tắc cho **Ubuntu**.
   - **Resources > Advanced > Disk image location**: bấm Browse, chọn thư mục ở ổ còn trống, ví dụ `D:\Docker\wsl` (tạo trước bằng File Explorer). Image khoảng 20 GB sẽ nằm ở đây thay vì ổ C.
   - Bấm **Apply & restart**, chờ góc dưới bên trái hiện chữ xanh **Engine running**.
3. (Tuỳ chọn, nên làm nếu ổ C chật) Chuyển cả Ubuntu sang ổ D. Đóng hết cửa sổ Ubuntu, Quit Docker Desktop, rồi trong PowerShell:
   ```powershell
   wsl --shutdown
   mkdir D:\WSL
   wsl --manage Ubuntu --move D:\WSL\Ubuntu
   ```
   Xong thì mở lại Docker Desktop.
4. Mở **Ubuntu** và kiểm tra:
   ```sh
   docker run --rm hello-world
   ```
   Dòng `Unable to find image 'hello-world:latest' locally` là bình thường (lần đầu nó tự tải). Đạt khi in ra **Hello from Docker!**

## 2. Lấy tool và repo (làm một lần)

Mọi lệnh từ đây gõ trong **cửa sổ Ubuntu**. Không clone vào ổ Windows (`/mnt/c`, `/mnt/d`): chạy chậm và hỏng ký tự xuống dòng.

```sh
git config --global core.autocrlf input
git config --global user.name  "Ho Ten Day Du"
git config --global user.email "email@gmail.com"

mkdir -p ~/eda/designs && cd ~/eda
git clone --depth 1 https://github.com/iic-jku/IIC-OSIC-TOOLS.git
git clone https://github.com/NguyenDinhNhatNguyen/rv32i-soc.git designs/rv32i-soc

docker pull hpretl/iic-osic-tools:2026.10
```

Lệnh cuối tải khoảng 4 GB, chờ tới khi in `Status: Downloaded newer image ...`. Nếu chạy lại mà thấy `fatal: destination path ... already exists` thì nghĩa là đã clone rồi, bỏ qua.

## 3. Bật môi trường (mỗi lần làm việc)

Trong cửa sổ Ubuntu:

```sh
cd ~/eda/designs/rv32i-soc
git pull
scripts/eda.sh start
```

Mở Chrome vào **`http://localhost:8080`**, mật khẩu **`abc123`**. Sẽ thấy một desktop Linux.

Nhóm dùng cổng 8080 thay vì 80 vì nhiều máy Windows có IIS chiếm cổng 80 (vào `http://localhost` chỉ thấy trang liệt kê file `localhost - /`).

Lệnh khác của `scripts/eda.sh` (chạy trong cửa sổ Ubuntu):

| Lệnh | Việc làm |
| --- | --- |
| `scripts/eda.sh status` | Container có đang chạy không |
| `scripts/eda.sh check` | Lint + 2 bài mô phỏng accelerator |
| `scripts/eda.sh run "make wave-accel"` | Chạy một lệnh bất kỳ trong container |
| `scripts/eda.sh shell` | Vào shell của container ngay trong cửa sổ Ubuntu |
| `scripts/eda.sh stop` | Tắt container khi xong việc |

## 4. Kiểm tra (tiêu chí nghiệm thu HT-04)

Trong cửa sổ Ubuntu:

```sh
scripts/eda.sh check
```

Hoặc trong Terminal của desktop VNC:

```sh
cd /foss/designs/rv32i-soc
make lint-accel && make sim-accel && make sim-accel-apb
```

**Đạt khi:** lint không in dòng `%Warning` nào, và có hai dòng

```
PASS: 40 phep nhan ma tran 4x4 khop mo hinh vang
PASS: APB3 - 10 phep nhan va 4 kiem tra PSLVERR dung
```

Chụp màn hình gửi vào kênh nhóm.

## 5. Xem sóng

Trong **Terminal của desktop VNC** (GTKWave hiện trong trang `localhost:8080`, không hiện trên Windows):

```sh
cd /foss/designs/rv32i-soc
make wave-accel
gtkwave tb/unit/out/accel.vcd tb/unit/accel.gtkw &
```

File `accel.gtkw` đã chọn sẵn các tín hiệu chính (bus, FSM `state`/`cnt`/`busy`/`done`/`irq`, dữ liệu lệch pha `a_feed`/`b_feed`). Vào **Time > Zoom > Zoom Best Fit** để xem toàn bộ. Nhớ có dấu `&` ở cuối, nếu không Terminal sẽ bị GTKWave giữ.

## 6. Làm việc bằng VS Code trên Windows (khuyên dùng)

Cài VS Code bình thường trên Windows, rồi cài 2 extension của Microsoft: **WSL** và **Dev Containers**.

**Mở repo để sửa code và dùng git:**

1. Mở VS Code, nhấn `Ctrl+Shift+P` (hoặc bấm nút `><` màu xanh góc dưới bên trái), chọn **WSL: Connect to WSL**.
2. File > Open Folder > `/home/<ten>/eda/designs/rv32i-soc`.
3. Góc dưới bên trái hiện **WSL: Ubuntu** là đúng. Terminal (``Ctrl+` ``) lúc này là cửa sổ Ubuntu: dùng cho `git` và `scripts/eda.sh`.

Cách nhanh: trong cửa sổ Ubuntu gõ `cd ~/eda/designs/rv32i-soc && code .`

**Chạy `make` ngay trong VS Code:** container phải đang chạy (`scripts/eda.sh start`), rồi `Ctrl+Shift+P` > **Dev Containers: Attach to Running Container** > chọn `iic-osic-tools_xvnc_uid_1000` > File > Open Folder > `/foss/designs/rv32i-soc`. Terminal ở cửa sổ này có `make`, `iverilog`, `verilator`.

**Extension nên cài thêm:**

- **Verilog-HDL/SystemVerilog** (mshr-h): tô màu, báo lỗi khi gõ. Trong cửa sổ Attach, chọn linter `verilator`.
- **VaporView**: mở file `.vcd` thành tab sóng ngay trong VS Code. Cài bằng nút **Install in Container**. Bấm `+` cạnh tên tín hiệu để thêm vào khung sóng.
- **Claude Code** (Anthropic), cài ở cửa sổ WSL: bấm biểu tượng tia lửa góc trên bên phải để mở. Claude Code chạy mô phỏng bằng `scripts/eda.sh check` hoặc `scripts/eda.sh run "<lệnh>"`.

Không mở repo bằng đường dẫn `\\wsl.localhost\...` trong File > Open Folder kiểu Windows: chậm và git Windows làm hỏng ký tự xuống dòng.

## 7. Lỗi đã gặp và cách xử lý

| Triệu chứng | Cách xử lý |
| --- | --- |
| `docker: command not found` trong Ubuntu | Docker Desktop chưa bật WSL integration cho Ubuntu (mục 1 bước 2) |
| `permission denied ... docker.sock` | Docker Desktop chưa khởi động xong. Chờ chữ **Engine running** rồi thử lại |
| Docker Desktop báo "There was a problem with WSL ... `wsl.exe --unmount docker_data.vhdx`" | Bấm **Quit**. PowerShell: `wsl --shutdown`, chờ 10 giây, mở lại Docker Desktop |
| `docker pull` báo `read-only file system` | Như dòng trên. Nếu vẫn lỗi: Docker Desktop > biểu tượng con bọ (Troubleshoot) > **Clean / Purge data** > tick WSL 2 > Delete (chỉ xoá image Docker, không mất code), rồi pull lại |
| `http://localhost` hiện trang `localhost - /` liệt kê file | Đó là IIS của Windows. Dùng `http://localhost:8080` (`scripts/eda.sh start` đã dùng cổng này) |
| `port is already allocated` | Container cũ còn giữ cổng: `docker rm -f iic-osic-tools_xvnc_uid_$(id -u)` rồi `scripts/eda.sh start` |
| `fatal: destination path ... already exists` | Đã clone rồi, bỏ qua; dùng `git pull` để cập nhật |
| `$'\r': command not found` | Repo bị clone từ Windows. Xoá, chạy `git config --global core.autocrlf input`, clone lại trong Ubuntu |
| `make: iverilog: No such file` hoặc `/foss/designs: No such file` | Đang gõ trong cửa sổ Ubuntu. Dùng `scripts/eda.sh run "..."` hoặc Terminal của container |
| Chạy `gtkwave` không thấy cửa sổ | Nó hiện trong trang `localhost:8080`, chuyển sang tab Chrome đó |
| Không bấm được F1 trong VS Code | Dùng `Ctrl+Shift+P` hoặc `Fn+F1` |
| GTKWave/KLayout đen màn hình | Trong container: `export LIBGL_ALWAYS_SOFTWARE=1` rồi mở lại |

## 8. Luyện thiết kế vật lý ở nhà (tuỳ chọn, OpenROAD + nangate45)

Image không kèm nangate45, nhưng OpenROAD-flow-scripts (ORFS) có platform nangate45 và SRAM giả `fakeram45`, giống cấu trúc SoC của nhóm. Trong Terminal của container:

```sh
cd /foss/designs
git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts/flow
export OPENROAD_EXE=$(which openroad) YOSYS_EXE=$(which yosys)
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk gui_final
```

Nếu ORFS báo lỗi do lệch phiên bản OpenROAD, dùng image riêng của ORFS (trong cửa sổ Ubuntu):

```sh
docker run --rm -it -v ~/eda/designs:/work openroad/orfs:latest bash
cd /OpenROAD-flow-scripts/flow && make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk
```

Firmware RV32I biên dịch được bằng toolchain có sẵn trong container: `riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -Ifw ...`.

## 9. Ba điều không làm

- Không copy thư viện GPDK45, file SRAM macro hay license Cadence về máy cá nhân hay lên GitHub.
- Không đưa số liệu nangate45 vào report; chỉ dùng để xem xu hướng.
- Không sửa script Genus/Innovus để chạy ở nhà: hai bộ script khác nhau, chỉ SDC dùng chung.
