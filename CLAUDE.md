# CLAUDE.md

Hướng dẫn cho Claude Code khi làm việc trong repo này. Người dùng là sinh viên nhóm CE434 (đồ án SoC RV32I, GPDK 45 nm). Trả lời bằng tiếng Việt, ngắn gọn, dễ hiểu.

## Dự án

SoC RV32I 3 tầng (IF/EX/WB) + SRAM hard macro + accelerator systolic 4x4 (Lab 2) + Timer, UART, GPIO, chạy từ RTL tới GDS bằng Cadence (Genus, Conformal, Innovus) trên server trường. Ở nhà chỉ mô phỏng, lint và thử flow mã nguồn mở.

- Kế hoạch, phân công: `README.md` (có link Google Doc, Sheet).
- Yêu cầu đề bài đã tóm tắt: `docs/spec/requirements.md`. Quy ước flow Cadence theo Lab: `docs/flow_notes.md`.
- Bản đồ địa chỉ, thanh ghi accelerator: `docs/runbook_nguyen.md`, `rtl/accel/accel_wrapper.v`, `fw/accel.h`.
- Đặc tả core RV32I (pipeline, bus valid/ready, kiểm chứng): `docs/spec/core.md`, chạy `make lint-core unit-core fw-core isa-core` (riscv-tests là submodule: `git submodule update --init --recursive`).

## Chạy công cụ

Tool EDA (iverilog, verilator, yosys, gtkwave, riscv gcc) nằm **trong container Docker**, không có trong shell WSL. Từ shell WSL, chạy qua `scripts/eda.sh`:

```sh
scripts/eda.sh status                    # container có chạy không, nếu không thì: scripts/eda.sh start
scripts/eda.sh check                     # lint + 2 bài mô phỏng, phải ra 2 dòng PASS và 0 %Warning
scripts/eda.sh run "make sim-accel"      # chạy lệnh bất kỳ trong container, tại thư mục repo
```

Nếu shell hiện tại đã ở trong container (có `iverilog` trong PATH), gọi thẳng `make <target>`. Danh sách target: `make help`.

Genus/Innovus/Conformal (`make synth-accel`, `make pnr-accel`, `make check-server`) chỉ chạy trên server trường, không chạy ở nhà.

## Quy tắc bắt buộc

- **Commit message bằng tiếng Anh**, dòng đầu ngắn, mệnh lệnh ("Add ...", "Fix ...").
- **Không thêm dòng `Co-Authored-By` hay `Claude-Session`** hay bất kỳ dòng ghi công Claude/AI nào vào commit hoặc PR. Tác giả là người đang dùng máy (theo `git config`).
- Trước khi commit thay đổi RTL hoặc testbench: `scripts/eda.sh check` phải PASS và lint 0 warning.
- Repo công khai: **không** đưa vào file của GPDK45 (`*.lib`, `*.lef`, `*.gds`, SRAM macro), file Cadence, slide hay PDF của môn. `.gitignore` đã chặn phần lớn, nhưng vẫn kiểm `git status` trước khi commit.
- RTL theo Verilog-2005, tổng hợp được (không `initial` trong RTL, không latch), reset tích cực mức thấp `rst_n`. Giữ ghi chú trong code bằng tiếng Việt như các file hiện có.
- Không sửa script Genus/Innovus để chạy được ở nhà. Flow nhà và flow trường tách riêng, chỉ dùng chung SDC.
- Tài liệu trong `docs/` viết tiếng Việt, câu ngắn.
- **Không dùng dấu `;` trong câu văn** (tài liệu, comment, commit message, PR, tin nhắn cho nhóm), vì người viết bình thường không dùng. Thay bằng "và"/"and", dấu phẩy, hoặc tách thành câu mới, chọn cách đọc tự nhiên nhất. Chỉ giữ `;` khi là cú pháp code (`;#` trong Tcl, `;` trong C/Verilog).

## Cấu trúc thư mục

| Thư mục | Nội dung |
| --- | --- |
| `rtl/` | RTL (`core`, `bus`, `mem`, `periph`, `accel`) |
| `tb/unit/`, `tb/soc/` | Testbench từng khối và toàn SoC, kết quả chạy ở `tb/unit/out/` (bị ignore) |
| `fw/` | Firmware C cho RV32I |
| `syn/`, `lec/`, `pnr/`, `sta/`, `power/` | Script Genus, Conformal, Innovus, STA, công suất (chạy ở trường) |
| `scripts/` | `eda.sh` (môi trường nhà), `check_server.sh` (server trường) |
| `docs/` | Hướng dẫn, ghi chú flow, runbook |
| `appendix/` | Báo cáo copy từ server để đưa vào report |
