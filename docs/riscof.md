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

IMEM của tb_core cho arch-test đặt ở 0x8000_0000 (`-DCORE_TB_IMEM_BASE`, `RESET_PC` của core lấy theo giá trị này), trùng địa chỉ nạp của Spike.
`link.ld`, `scripts/arch_run.sh` (`ARCH_IMEM_BASE`) và `elf2hex.py --imem-base` dùng cùng địa chỉ. Các test khác của tb_core vẫn ở 0x0.
Lý do: signature của `misalign-jal-01` là `a0 - địa chỉ nhãn`, phụ thuộc địa chỉ nạp. Ở 0x0 core lệch Spike đúng 0x80000000 dù hành vi giống hệt.
Chọn dời tb_core thay vì chạy Spike ở 0x0, vì Spike đặt debug module ở 0x0–0xFFF, boot ROM ở 0x1000 và CLINT ở 0x2000000.
Chạy Spike ở 0x0 phải sửa memory map và boot của Spike, còn dời tb_core chỉ đổi một macro lúc dịch, không đụng RTL.

Bộ test mà ISA yaml chọn (RV32I/IM, Zicsr, Zifencei, không C, không hỗ trợ truy cập lệch):

- ENABLE_M=0: `I` (39 test), `Zifencei/Fencei`, 15 test `privilege` (`ecall`, `ebreak` và 13 test `misalign-*`). Tổng 55.
- ENABLE_M=1: thêm 8 test `M`. Tổng 63.

RISCOF 3.10.0 còn chọn 41 test `pmp32`. Chúng cần S/U-mode và thanh ghi PMP (lệnh đầu tiên đọc `medeleg` đã trap), mà core chỉ có M-mode.
Không loại được bằng ISA yaml: cả 41 test chỉ có điều kiện `check ISA:=regex(.*32.*)` và `check ISA:=regex(.*I.*Zicsr.*)`,
và RISCOF (`eval_cond` trong `riscof/framework/test.py`) chỉ xét các điều kiện `check` này. Muốn loại thì phải bỏ Zicsr khỏi ISA,
khi đó mất luôn `ecall`, `ebreak` và các test `misalign-*`. Vì vậy `make arch-core` chạy `riscof testlist`, lọc bỏ `pmp32` rồi mới `riscof run --testfile`.

## Chạy

```sh
git submodule update --init --recursive
make arch-core-dut          # chỉ phía core, không cần RISCOF/Spike
make arch-core              # RISCOF + Spike, báo cáo ở tb/riscof/out/<cấu hình>/report.html
```

`make arch-core-dut` chỉ kiểm test dịch được, core chạy tới RVMODEL_HALT không bị trap lạ và ghi được signature.
Nó **không** kiểm signature đúng. Phải chạy `make arch-core` mới biết core đúng chuẩn.
`make arch-core` đếm Passed/Failed trong `report.html` và trả lỗi nếu có test Failed (bản thân `riscof run` luôn trả 0).

## Kết quả (23/10/2026)

Công cụ: RISCOF 1.25.3, riscv-isac 0.18.0, riscv-config 3.18.3, Spike 1.1.1-dev (riscv-isa-sim commit `6a13e0c5`, 21/10/2026),
riscv64-unknown-elf-gcc 13.2.0, Icarus Verilog 12.0, riscv-arch-test 3.10.0.

| Cấu hình | Số test | Passed | Failed |
| --- | --- | --- | --- |
| M0W1 (ENABLE_M=0) | 55 | 55 | 0 |
| M1W1 (ENABLE_M=1) | 63 | 63 | 0 |

`make arch-core` mất khoảng 3 phút. `make arch-core-dut`: 118/118 PASS (55 + 63).

Lần chạy đầu (cùng ngày) có 2 test lệch ở cả hai cấu hình, đã sửa:

- `privilege/ebreak`: core ghi mtval = 0, Spike ghi PC của lệnh EBREAK. Đã đổi core ghi PC (D-035 trong `docs/core_decisions.md`).
- `privilege/misalign-jal-01`: core 0xfffffda2, Spike 0x7ffffda2, chỉ do khác địa chỉ nạp. Đã dời IMEM của tb_core cho arch-test lên 0x8000_0000 (mục trên).

## Cài RISCOF và Spike (Ubuntu/WSL)

Cần quyền sudo cho gói hệ thống:

```sh
sudo apt install -y python3-pip python3-venv device-tree-compiler build-essential git

# RISCOF 1.25.3 từ pip, trong venv riêng (kéo theo riscv-isac 0.18.0)
python3 -m venv ~/riscof-venv
~/riscof-venv/bin/pip install riscof==1.25.3
echo 'export PATH=$HOME/riscof-venv/bin:$PATH' >> ~/.bashrc

# Spike, cài vào ~/.local. Cần lấy submodule trước khi configure
git clone https://github.com/riscv-software-src/riscv-isa-sim.git ~/src/riscv-isa-sim
cd ~/src/riscv-isa-sim && git submodule update --init --recursive
mkdir -p build && cd build
../configure --prefix=$HOME/.local
make -j$(nproc) && make install
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
```

Mở terminal mới rồi kiểm: `riscof --version` (1.25.3) và `spike --help | head -1` (1.1.1-dev).
Các lệnh này chạy trong shell WSL, không cần container.
Plugin dùng `riscv64-unknown-elf-gcc` cho cả core và Spike. Toolchain khác thì đổi khoá `prefix` trong `config_*.ini`.

## Khi có test FAIL

- Signature của core: `tb/riscof/out/<cấu hình>/<đường dẫn test>/dut/DUT-rv32_core.signature`, log `tb.log` cùng thư mục.
- Signature của Spike: thư mục `ref/` cạnh đó.
- Chạy lại một test với vết lệnh: `scripts/arch_run.sh M1W1 <file .S> <thư mục> TEST_CASE_1=True` rồi thêm `+trace` vào lệnh vvp trong `tb.log` nếu cần.
