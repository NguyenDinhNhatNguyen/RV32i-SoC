# Môi trường làm việc ở nhà (HT-04)

Trường không mở VPN, nên ở nhà cả nhóm dùng bộ tool mã nguồn mở trong Docker image **IIC-OSIC-TOOLS** (Icarus, Verilator, GTKWave, Yosys, OpenROAD, KLayout, toolchain RISC-V). Cả nhóm dùng **cùng tag `2026.10`** và **cùng cổng 8080** để hướng dẫn giống nhau trên mọi máy. Số liệu chính thức cho report vẫn lấy trên server Cadence.

**Cần:** RAM từ 8 GB và một ổ còn trống **ít nhất 30 GB** (image giải nén khoảng 20 GB, cộng chỗ cho WSL và kết quả chạy).

**Chọn đường đi theo máy của bạn:**

| Máy của bạn | Làm các mục |
| --- | --- |
| Windows, ổ C còn trống từ 30 GB | 1 (bỏ qua bước 1.3) → 2 → 3 → 4 |
| Windows, ổ C chật nhưng có ổ D (hoặc ổ khác) còn trống | 1 (làm cả bước 1.3) → 2 → 3 → 4 |
| macOS hoặc Linux | Chỉ cài Docker, bỏ qua mục 1, làm từ mục 2 trong terminal thường |
| Máy yếu, không cài được Docker | Mục 10 (cài tool rời, chỉ đủ chạy mô phỏng) |

Xem ổ còn trống: File Explorer > This PC.

**Có hai loại cửa sổ dòng lệnh, đừng nhầm:**

| | Cửa sổ Ubuntu (WSL) | Terminal trong container |
| --- | --- | --- |
| Mở từ | Start menu > Ubuntu, hoặc terminal của VS Code ở chế độ **WSL: Ubuntu** | Desktop Linux ở `http://localhost:8080`, hoặc VS Code đã **Attach** vào container |
| Dấu nhắc | `ten@MAY:~$` | `/foss/designs/... >` hoặc `$` |
| Đường dẫn repo | `~/eda/designs/rv32i-soc` | `/foss/designs/rv32i-soc` |
| Dùng cho | `git`, `docker`, `scripts/eda.sh` | `make`, `iverilog`, `verilator`, `gtkwave` |

Hai đường dẫn là **cùng một thư mục**: sửa bên này, bên kia thấy ngay.

## 1. Cài WSL và Docker (Windows, làm một lần)

**1.1 Cài WSL.** Mở **PowerShell** (Run as Administrator):

```powershell
wsl --install
wsl --update
```

Khởi động lại máy, mở **Ubuntu** từ Start menu, đặt username và password cho Linux. Bản Ubuntu nào cũng được (24.04, 26.04...). Nếu đã có WSL từ trước thì chỉ cần chạy `wsl --update`.

**1.2 Cài Docker Desktop**, mở lên, vào Settings (bánh răng):

- **General**: bật "Use the WSL 2 based engine".
- **Resources > WSL integration**: bật công tắc cho **Ubuntu**.
- Bấm **Apply & restart**, chờ góc dưới bên trái hiện chữ xanh **Engine running**.

**1.3 Chỉ làm nếu ổ C còn dưới 30 GB:** để image và Ubuntu nằm ở ổ khác (ví dụ D).

- Tạo thư mục `D:\Docker\wsl` bằng File Explorer. Trong Docker Desktop vào **Settings > Resources > Advanced > Disk image location**, bấm Browse chọn thư mục đó, bấm **Apply & restart**. Làm bước này **trước** khi tải image ở mục 2 để khỏi phải chuyển 20 GB.
- Muốn chuyển cả Ubuntu (code nằm trong đó, thường chỉ vài GB): đóng hết cửa sổ Ubuntu, Quit Docker Desktop, rồi trong PowerShell:

  ```powershell
  wsl --shutdown
  mkdir D:\WSL
  wsl --manage Ubuntu --move D:\WSL\Ubuntu
  ```

  Xong thì mở lại Docker Desktop.

**1.4 Kiểm tra.** Mở **Ubuntu**:

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

Nếu container đã có từ lần trước, `start` sẽ hỏi và chờ bấm một phím:

- `Press "s" to start, and "r" to remove`: container đang tắt, bấm `s` để bật.
- `Press "s" to stop, and "r" to stop & remove`: container đang chạy rồi, bấm Enter để giữ nguyên. Bấm `s` là tắt container.
- `r` xoá container (code trong `~/eda/designs` không mất). Chỉ dùng khi container lỗi, xong chạy `scripts/eda.sh start` lại để tạo mới.

Nhóm dùng cổng 8080 thay vì 80 vì nhiều máy Windows có IIS chiếm cổng 80. Nếu máy bạn có chương trình khác đã dùng 8080 (lỗi `port is already allocated`), chọn cổng khác và dùng nó mọi lần, ví dụ thêm dòng `export WEBSERVER_PORT=8081` vào cuối file `~/.bashrc` rồi mở lại Ubuntu.

Lệnh khác của `scripts/eda.sh` (chạy trong cửa sổ Ubuntu):

| Lệnh | Việc làm |
| --- | --- |
| `scripts/eda.sh status` | Container có đang chạy không |
| `scripts/eda.sh check` | Lint + 2 bài mô phỏng accelerator |
| `scripts/eda.sh run "make wave-accel"` | Chạy một lệnh bất kỳ trong container |
| `scripts/eda.sh shell` | Vào shell của container ngay trong cửa sổ Ubuntu |
| `scripts/eda.sh wave` | Mô phỏng ghi sóng rồi mở GTKWave trên desktop VNC |
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

```text
PASS: 40 phep nhan ma tran 4x4 khop mo hinh vang
PASS: APB3 - 10 phep nhan va 4 kiem tra PSLVERR dung
```

Chụp màn hình gửi vào kênh nhóm.

## 5. Xem sóng

Nhanh nhất: trong cửa sổ Ubuntu gõ `scripts/eda.sh wave`, rồi mở `http://localhost:8080` là thấy GTKWave. Hoặc làm tay:

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
| `port is already allocated` | Có thể container cũ còn giữ cổng: `docker rm -f iic-osic-tools_xvnc_uid_$(id -u)` rồi `scripts/eda.sh start`. Vẫn lỗi thì cổng bị chương trình khác dùng: đổi cổng như ở mục 3 |
| `fatal: destination path ... already exists` | Đã clone rồi, bỏ qua và dùng `git pull` để cập nhật |
| `$'\r': command not found` | Repo bị clone từ Windows. Xoá, chạy `git config --global core.autocrlf input`, clone lại trong Ubuntu |
| `make: iverilog: No such file` hoặc `/foss/designs: No such file` | Đang gõ trong cửa sổ Ubuntu. Dùng `scripts/eda.sh run "..."` hoặc Terminal của container |
| Chạy `gtkwave` không thấy cửa sổ | Nó hiện trong trang `localhost:8080`, chuyển sang tab Chrome đó |
| Không bấm được F1 trong VS Code | Dùng `Ctrl+Shift+P` hoặc `Fn+F1` |
| Ổ C đầy trong lúc `docker pull` | Làm bước 1.3, rồi `docker system prune` và pull lại |
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
- Không đưa số liệu nangate45 vào report, chỉ dùng để xem xu hướng.
- Không sửa script Genus/Innovus để chạy ở nhà: hai bộ script khác nhau, chỉ SDC dùng chung.

## 10. Máy không cài được Docker

Cài tool rời trong Ubuntu (WSL) hoặc Linux, đủ để mô phỏng và lint:

```sh
sudo apt update && sudo apt install -y iverilog verilator gtkwave make git
cd ~/eda/designs/rv32i-soc
make lint-accel && make sim-accel && make sim-accel-apb
```

Phiên bản tool sẽ khác image của nhóm. Nếu kết quả khác với máy người khác, tin kết quả trong Docker. GTKWave mở thẳng trên Windows nhờ WSLg.
