# riscv-arch-test qua RISCOF

Bộ test kiến trúc chính thức (submodule `fw/riscv-arch-test`, tag 3.10.0, bản cuối dùng RISCOF) chạy trên `tb_core`.
RISCOF dịch từng test cho core và cho Spike, chạy cả hai rồi so signature.

## Đã có trong repo

| File | Vai trò |
| --- | --- |
| `tb/riscof/config_M0W1.ini`, `config_M1W1.ini` | Cấu hình RISCOF cho ENABLE_M=0 và 1 |
| `tb/riscof/rv32_core/` | Plugin DUT, ISA yaml, platform yaml, env (`model_test.h`, `link.ld`) |
| `tb/riscof/spike_ref/` | Plugin Spike làm tham chiếu, dùng env `spike_simple` trong submodule |
| `scripts/arch_run.sh` | Dịch và chạy một test trên tb_core, ghi `DUT-rv32_core.signature` |
| `tb/core/tb_core.v` | Thêm plusarg `+signature= +sig_begin= +sig_end=` để ghi signature khi PASS |

tb_core cho arch-test dịch với IMEM 2 MB (`-DCORE_TB_IMEM_SIZE`), vì `jal-01` dài khoảng 1,7 MB và các test nhánh khoảng 300 KB.
Mọi section nằm trong IMEM như `fw/common/link_isa.ld`.

Bộ test mà ISA yaml chọn (RV32I/IM, Zicsr, Zifencei, không C, không hỗ trợ truy cập lệch):

- ENABLE_M=0: `I` (39 test), `Zifencei/Fencei`, `privilege/ecall`, `ebreak`, `misalign2-jalr-01`. Tổng 43.
- ENABLE_M=1: thêm 8 test `M`. Tổng 51.

## Chạy

```sh
git submodule update --init --recursive
make arch-core-dut          # chỉ phía core, không cần RISCOF/Spike
make arch-core              # RISCOF + Spike, báo cáo ở tb/riscof/out/<cấu hình>/report.html
```

`make arch-core-dut` chỉ kiểm test dịch được, core chạy tới RVMODEL_HALT không bị trap lạ và ghi được signature.
Nó **không** kiểm signature đúng. Phải chạy `make arch-core` mới biết core đúng chuẩn.

Kết quả 22/10/2026: `make arch-core-dut` 94/94 PASS (43 lần với M0W1, 51 lần với M1W1). `make arch-core` chưa chạy được vì máy chưa có RISCOF và Spike.

## Cài RISCOF và Spike (Ubuntu/WSL)

Cần quyền sudo cho gói hệ thống:

```sh
sudo apt install -y python3-pip python3-venv device-tree-compiler build-essential git

# RISCOF trong venv riêng
python3 -m venv ~/riscof-venv
~/riscof-venv/bin/pip install git+https://github.com/riscv/riscof.git
echo 'export PATH=$HOME/riscof-venv/bin:$PATH' >> ~/.bashrc

# Spike, cài vào ~/.local
git clone https://github.com/riscv-software-src/riscv-isa-sim.git ~/src/riscv-isa-sim
cd ~/src/riscv-isa-sim && mkdir -p build && cd build
../configure --prefix=$HOME/.local
make -j$(nproc) && make install
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
```

Mở terminal mới rồi kiểm: `riscof --version` và `spike --help | head -1`.
Plugin dùng `riscv64-unknown-elf-gcc` cho cả core và Spike. Toolchain khác thì đổi khoá `prefix` trong `config_*.ini`.

## Khi có test FAIL

- Signature của core: `tb/riscof/out/<cấu hình>/<đường dẫn test>/dut/DUT-rv32_core.signature`, log `tb.log` cùng thư mục.
- Signature của Spike: thư mục `ref/` cạnh đó.
- Chạy lại một test với vết lệnh: `scripts/arch_run.sh M1W1 <file .S> <thư mục> TEST_CASE_1=True` rồi thêm `+trace` vào lệnh vvp trong `tb.log` nếu cần.
