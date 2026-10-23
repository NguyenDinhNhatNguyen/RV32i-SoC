# Chương X. Core RV32I (`rv32_core`)

**Bản nháp.** Mọi con số có ghi file nguồn trong repo. Ô ghi "chờ STA-04" là số phải lấy từ Genus và Innovus ở trường.

Quy ước dẫn nguồn:

- "Dx" là quyết định trong `docs/core_decisions.md`.
- "mục x.y" là mục trong `docs/spec/core.md`.
- D-036, D-037 và `docs/timing_core.md` hiện nằm trên nhánh `feat/nhan-ppa` (PR chưa merge). Khi merge thì bỏ ghi chú này.

## X.1 Mục tiêu và ISA

Mục tiêu:

- Core đúng chuẩn RISC-V, có bằng chứng tuân thủ chính thức (riscv-arch-test so với Spike).
- CPI thấp ở tần số đề bài yêu cầu (50 MHz, chu kỳ 20 ns trong SDC).
- Đi được tới GDS bằng flow Cadence của môn. RTL Verilog-2005, không latch, reset bất đồng bộ `rst_n` tích cực mức thấp.
- Hỗ trợ đo công suất lúc chờ ngắt (WFI ngủ thật để Genus gate clock).

ISA (mục 4.1, 4.7):

- RV32I, Zicsr, Zicntr, Zifencei. Chỉ machine mode.
- RV32M khi tham số `ENABLE_M=1`.
- FENCE là NOP. WFI cho core ngủ khi `ENABLE_WFI_SLEEP=1`, là NOP khi bằng 0.
- Load, store và nhảy lệch địa chỉ gây ngoại lệ, không xử lý bằng phần cứng.
- CSR M-mode: mstatus, misa, mie, mip, mtvec (direct), mepc, mcause, mtval, mscratch, mcycle(h), minstret(h), các bí danh chỉ đọc cycle, time, instret và nhóm ID.

Cổng của core (mục 4.10): cổng lấy lệnh `if_*` (đọc đồng bộ từ IMEM hoặc boot ROM), bus dữ liệu valid/ready `d_req_*`, `d_rsp_*`, 3 đường ngắt mức, `mtime_i[63:0]`, `core_sleep_o`. Tham số `ENABLE_M`, `ENABLE_WFI_SLEEP`, `RESET_PC` (mặc định 0x0001_0000, boot ROM).

## X.2 Vi kiến trúc 3 tầng

![Vi kiến trúc rv32_core](../figures/core_microarch.svg)

*Hình X.1. Vi kiến trúc `rv32_core`. Hình sinh từ `docs/figures/core_microarch.py` (D-034).*

| Tầng | Việc chính |
| --- | --- |
| IF | `if_pc_q` là flop, đưa thẳng ra chân địa chỉ IMEM. Chọn PC kế tiếp |
| EX | Nhận lệnh thẳng từ ngõ ra IMEM. Giải mã, đọc regfile, forward, ALU, so sánh nhánh, tính địa chỉ và kiểm tra lệch, phát yêu cầu bus dữ liệu, M-unit |
| WB | Nhận dữ liệu đọc, căn chỉnh và mở rộng dấu, ghi regfile, thực thi CSR, xử lý trap, MRET, FENCE.I, WFI |

Nguồn: mục 4.2.

Các điểm chính:

- **Không có thanh ghi lệnh IF/EX.** SRAM đọc đồng bộ nên chính ngõ ra IMEM đóng vai trò thanh ghi tầng. Khi dừng, lệnh được chốt vào `ex_instr_hold_q` (mục 4.3, D-014).
- **Forward WB → EX** cho mọi kết quả ghi rd, gồm cả dữ liệu load lấy thẳng từ bus sau căn chỉnh. Không có stall load-use (mục 4.5).
- **Chuyển hướng:** nhánh, JAL, JALR quyết định ở EX, phạt 1 chu kỳ. Trap, MRET, FENCE.I, WFI chuyển hướng từ WB, phạt 2 chu kỳ (mục 4.4, D-023).
- **Dừng:** `pipe_stall = wb_wait | ex_wait`, giữ IF và EX khi bus chậm hoặc M-unit chưa xong (D-014).
- **RV32M:** nhân 2 chu kỳ (EX dừng 1), chia restoring 1 bit mỗi chu kỳ (EX dừng 33) (mục 4.9, D-031).

## X.3 Các quyết định chính

Chọn 10 quyết định ảnh hưởng nhiều nhất tới CPI, timing và tính đúng. Danh sách đầy đủ ở `docs/core_decisions.md`.

| # | Quyết định | Lý do | Phương án đã loại |
| --- | --- | --- | --- |
| 1 | **3 tầng, không có thanh ghi IF/EX** (D-014, mục 4.3) | Tận dụng SRAM đọc đồng bộ làm thanh ghi tầng. Phạt nhánh chỉ 1 chu kỳ. Địa chỉ IMEM ra từ flop nên đường địa chỉ ngắn | Thêm tầng IF/EX (thêm 1 chu kỳ phạt nhánh). Phát lại PC khi dừng (địa chỉ IMEM đi tổ hợp từ `ready`) |
| 2 | **Forward dữ liệu load thẳng từ bus, không stall load-use** (mục 4.5, D-014) | CPI thấp hơn. 50 MHz cho đủ thời gian đi qua căn chỉnh load và mux forward | Stall 1 chu kỳ sau load |
| 3 | **ALU dùng chung cho địa chỉ và đích nhảy, bộ so sánh nhánh riêng** (D-007) | Tiết kiệm một bộ cộng. So sánh chạy song song với cộng đích, không nối tiếp | Dùng ALU SUB để so sánh rồi thêm bộ cộng đích (zero-detect kéo dài đường găng) |
| 4 | **Regfile bằng flop, enable riêng từng thanh ghi, không bypass bên trong** (D-011) | Reset xác định cho GLS. Genus gate clock theo nhóm. Bypass đã có ở mạng forward | Regfile bằng SRAM hoặc latch (cần macro, không reset được) |
| 5 | **Bus valid/ready, `d_req_valid_o` không phụ thuộc `ready`** (D-015, mục 5.1) | Đúng luật 5 của bus. Cho phát yêu cầu mới ngay chu kỳ nhận phản hồi nên load liên tiếp mỗi chu kỳ | Bus kiểu req/gnt có `valid` phụ thuộc `gnt` |
| 6 | **Ngoại lệ gắn cờ ở EX, xử lý ở WB, kiểm tra CSR ở EX** (D-016, D-021) | Một đường ngoại lệ chung. WB không thêm nguồn trap nên `d_req_valid_o` không phụ thuộc giải mã CSR | Kiểm tra CSR ở WB (kéo dài `wb_redirect` → `d_req_valid_o`) |
| 7 | **Ngoại lệ chính xác: chuyển hướng từ WB chặn tổ hợp yêu cầu bus của EX** (D-023, mục 4.8) | Lệnh sau lệnh trap không ghi bộ nhớ. Không vi phạm luật bus 1 vì lúc đó EX chưa có yêu cầu đang chờ | Cho lệnh sau trap chạy rồi khôi phục (không làm được với store) |
| 8 | **Ngắt nhận ở EX, chặn khi WB đang ghi mstatus hoặc mie, không ngắt yêu cầu đang wait state** (D-024) | Bật hoặc tắt ngắt có hiệu lực đúng từ lệnh kế tiếp. Giữ luật bus 1 | Chốt quyết định ngắt vào flop (chậm 1 chu kỳ). Nhận ngắt ở WB (mất chính xác với store) |
| 9 | **WFI ngủ thật bằng cách tắt enable** (D-025, mục 4.11) | `if_req_o = 0` từ flop, mọi flop pipeline giữ nguyên để Genus gate clock. Phục vụ phần so sánh công suất polling và WFI | WFI là NOP (vẫn hỗ trợ khi `ENABLE_WFI_SLEEP=0`) |
| 10 | **Nhân 2 chu kỳ bằng thanh ghi trung gian, chia 1 bit mỗi chu kỳ** (D-031) | Mỗi chu kỳ chỉ có nửa bộ nhân, không cần multicycle path trong SDC. Chia đơn giản, đủ cho 50 MHz | Nhân 33 × 33 một chu kỳ (cần multicycle path). Chia radix-4 (tốn bảng chọn thương) |

Hai quyết định nhỏ hơn nhưng đáng nêu trong báo cáo:

- **D-035:** mtval của EBREAK = PC, để khớp Spike trong riscv-arch-test (`docs/riscof.md`).
- **D-037:** nửa cao của `mcycle` và `minstret` có enable riêng, khoảng 58 flop ít nhận clock hơn mỗi chu kỳ (ước lượng tay, `docs/timing_core.md`).

## X.4 Phương pháp kiểm chứng

Kiểm chứng theo 5 lớp, từ khối nhỏ tới bằng chứng tuân thủ chính thức.

### Unit test từng khối (`make unit-core`)

- Testbench `tb/unit/tb_rv32_*.v` cho ALU, imm_gen, decoder, regfile, lsu_align, csr, muldiv. Decoder và csr chạy với `ENABLE_M=0` và 1 (`Makefile`, `CORE_UNIT_CFG_*`). Tổng 9/9 bài đạt (D-033).
- Mỗi testbench có mô hình tham chiếu viết khác RTL (D-012). Ví dụ decoder so với bảng MASK/MATCH của riscv-opcodes, mọi word không khớp bảng phải illegal. `tb_rv32_csr` quét đủ 4096 địa chỉ CSR (D-029). `tb_rv32_muldiv` chạy 144 cặp biên × 8 phép và 20 000 phép ngẫu nhiên, kiểm cả số chu kỳ (D-033).

### Test assembly trên `tb_core` (`make fw-core`)

- 6 bài trong `fw/tests/asm/`: `smoke`, `hazard`, `trap`, `irq`, `wfi`, `muldiv` (`docs/riscv-tests-status.md`).
- Chạy với 4 cấu hình `M<ENABLE_M>W<ENABLE_WFI_SLEEP>`, mỗi cấu hình 4 chế độ. Tổng 96/96 (D-033).
- `tb_core` kiểm giao thức bus: yêu cầu giữ nguyên khi `ready=0`, không có yêu cầu thứ hai khi còn phản hồi chờ, không X trên valid, địa chỉ, dữ liệu ghi và rd (D-017).
- Chế độ nominal bật `+strict_timing`: tb tự tính số bubble đúng (1 sau nhánh nhảy, 2 sau chuyển hướng WB, 1 sau truy cập dữ liệu vào IMEM, 1 cho MUL, 33 cho DIV) và báo lỗi nếu lệch. Đây là bằng chứng không có stall load-use và load liên tiếp mỗi chu kỳ (D-017, D-028, D-033).

### Chế độ stall ngẫu nhiên

Ba bộ tham số trong `Makefile` (`CORE_PLUS_stall*`):

| Chế độ | Seed | Không cấp quyền lấy lệnh | `d_req_ready = 0` | Trễ phản hồi thêm |
| --- | ---: | ---: | ---: | ---: |
| stall1 | 1 | 25% | 30% | 0..3 chu kỳ |
| stall2 | 2 | 50% | 50% | 0..5 chu kỳ |
| stall3 | 3 | 10% | 70% | 0..1 chu kỳ |

Lỗi chỉ lộ khi bus chậm (thanh ghi giữ lệnh, chuyển hướng khi đang dừng) chỉ bị bắt ở các chế độ này (D-019).

### riscv-tests (`make isa-core`)

- Submodule `fw/riscv-tests` ghim commit `3df703cd52d5`, env `p`, không sửa file nào (D-029).
- Đạt rv32ui-p 41/41, rv32mi-p 14/14, rv32um-p 8/8. Tổng 472/472 lần chạy (cấu hình M0W0 và M1W1, 4 chế độ) (`docs/riscv-tests-status.md`).
- Loại 3 test có lý do: `rv32ui-p-ma_data` (cần load/store lệch chạy đúng), `rv32mi-p-breakpoint` (cần debug trigger), `rv32mi-p-pmpaddr` (cần PMP).

### riscv-arch-test so với Spike (`make arch-core`)

- riscv-arch-test 3.10.0 qua RISCOF 1.25.3, tham chiếu Spike 1.1.1-dev (`docs/riscof.md`).

| Cấu hình | Số test | Passed | Failed |
| --- | ---: | ---: | ---: |
| M0W1 (ENABLE_M=0) | 55 | 55 | 0 |
| M1W1 (ENABLE_M=1) | 63 | 63 | 0 |

- Lần chạy đầu lệch 2 test. `privilege/ebreak` do mtval (sửa RTL, D-035). `privilege/misalign-jal-01` chỉ do khác địa chỉ nạp (dời IMEM của tb_core lên 0x8000_0000, không đụng RTL).
- 41 test `pmp32` bị lọc vì cần S/U-mode và PMP, RISCOF không loại được bằng ISA yaml (`docs/riscof.md`).

### Cấy lỗi (kiểm độ nhạy của testbench)

Cấy lỗi vào bản sao RTL rồi chạy lại bộ test, xem test có bắt được không.

| Giai đoạn | Số lỗi cấy | Bị bắt | Nguồn |
| --- | ---: | ---: | --- |
| P2, khối cơ bản | 9 | 9 | D-012 |
| P3, pipeline và `rv32_lsu_align` | 22 | 22 | D-019 |
| P4, CSR, trap, ngắt, WFI | 24 (2 tương đương logic) | 22/22 lỗi không tương đương | D-030 |
| P7, RV32M | 11 | 10 | D-033 |

Lỗi P7 không bị bắt là "lệnh M bị ngắt vẫn giữ M-unit". Lỗi này chỉ làm ngắt chờ phép chia xong, kết quả vẫn đúng (D-033). Ở P4 có 2 lỗi chỉ bị bắt sau khi thêm kiểm tra mới vào tb_core (D-030).

### Kiểm tra tương đương hình thức (flow nhà)

Thay đổi bộ đếm của D-037 được chứng minh tương đương với bản cũ bằng Yosys `equiv_induct`, 0 điểm không chứng minh được, cả `ENABLE_M=0` và 1 (`docs/timing_core.md`).

## X.5 Kết quả benchmark

Đo trên `tb_core`, bộ nhớ không wait state, GCC 13.2 `-O2`, số chu kỳ và số lệnh lấy từ `mcycle` và `minstret` trong vùng đo (`docs/bench_core.md`, commit core 2193cd1).

| Benchmark | Cấu hình | Chu kỳ | Lệnh | CPI | Hiệu năng |
| --- | --- | ---: | ---: | ---: | --- |
| Dhrystone, 500 lần | rv32i, ENABLE_M=0 | 339 028 | 291 528 | 1,163 | 0,839 DMIPS/MHz |
| Dhrystone, 500 lần | rv32im, ENABLE_M=1 | 339 028 | 276 528 | 1,226 | 0,839 DMIPS/MHz |
| CoreMark, 3 vòng | rv32i, ENABLE_M=0 | 2 693 735 | 2 239 763 | 1,203 | 1,114 CoreMark/MHz |
| CoreMark, 3 vòng | rv32im, ENABLE_M=1 | 1 085 261 | 939 989 | 1,155 | 2,764 CoreMark/MHz |

Nhận xét:

- CPI từ 1,155 tới 1,226. Phần trên 1 đến từ phạt nhánh 1 chu kỳ, chuyển hướng WB 2 chu kỳ và dừng chờ M-unit ở bản rv32im. Không có stall load-use.
- RV32M làm CoreMark nhanh gấp khoảng 2,5 lần vì phần ma trận nhân nhiều (`docs/bench_core.md`).
- Dhrystone ra cùng số chu kỳ ở hai cấu hình là trùng hợp. Bản rv32im ít lệnh hơn nhưng dừng chờ DIV 33 chu kỳ (`docs/bench_core.md`).
- WFI (test `wfi`, nominal): với W1 core ngủ 801 trên 1003 chu kỳ và chỉ chạy 177 lệnh. Với W0 cùng test chạy 625 lệnh trong 954 chu kỳ (`docs/riscv-tests-status.md`).

So sánh sơ bộ với PicoRV32 cùng script Yosys (`docs/yosys_compare.md`):

| Core | Cấu hình | Cell (Yosys) | Flip-flop | DMIPS/MHz |
| --- | --- | ---: | ---: | ---: |
| rv32_core | ENABLE_M=0 | 11 017 | 1 469 | 0,839 |
| rv32_core | ENABLE_M=1 | 19 595 | 1 673 | 0,839 |
| PicoRV32 | IM | 19 156 | 2 238 | 0,516 (README PicoRV32, không đo lại) |

Bảng này chưa công bằng: hai core khác tính năng CSR và giao diện bộ nhớ (`docs/yosys_compare.md`).

Số đo trên SoC thật (wait state của bus, truy cập dữ liệu vào IMEM): chờ STA-04.

## X.6 Timing, diện tích, công suất

### Xu hướng ở nhà (Yosys, Nangate45, OpenSTA)

**Chỉ để xem xu hướng.** Thư viện Nangate45 (thư viện mở 45 nm), không phải GPDK45, không có đặt cell và đi dây (`docs/timing_core.md`).

Chu kỳ nhỏ nhất của đường flop tới flop, RTL trên main, quét 4 mục tiêu trễ của abc:

| Cấu hình | D=1500 | D=2000 | D=2500 | D=3000 | Diện tích ở D=2000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| ENABLE_M=0 | 2,281 ns | 2,529 ns | 2,529 ns | 2,529 ns | 17 112 µm² |
| ENABLE_M=1 | 3,054 ns | 3,054 ns | 3,352 ns | 3,484 ns | 28 039 µm² |

Nguồn: `docs/timing_core.md`, việc 1.

- ENABLE_M=0 khoảng 395 MHz, ENABLE_M=1 khoảng 327 MHz. Đề bài cần 50 MHz nên còn dư nhiều.
- Đường găng ENABLE_M=0: so sánh nhánh và bit thấp ALU → `ex_exc` → `ex_trap` → `d_req_valid_o` → `pipe_stall` → `ex_go` → enable mọi thanh ghi pipeline. Đường găng ENABLE_M=1 nằm ở bộ nhân và `wb_result_q`.
- Đã thử rút ngắn đường ENABLE_M=0, được khoảng 5%, chỉ hơn mức dao động của abc (±3%) một chút nên không giữ thay đổi RTL (D-036).
- Clock gating: 99,8% flop có enable theo Yosys (`docs/timing_core.md`, việc 3).
- Yosys không ràng buộc thời gian: đường dài nhất 58 cell ở cả hai cấu hình (`docs/yosys_compare.md`).

### Số chính thức (Genus, Innovus, GPDK45)

Dự kiến điền bằng `scripts/ppa_table.py` từ report trong `appendix/`.

| Chỉ số | ENABLE_M=0 | ENABLE_M=1 |
| --- | --- | --- |
| Diện tích sau tổng hợp (µm², kGE) | chờ STA-04 | chờ STA-04 |
| Slack setup sau tổng hợp ở 20 ns | chờ STA-04 | chờ STA-04 |
| Slack setup, hold sau route | chờ STA-04 | chờ STA-04 |
| F_max ước lượng | chờ STA-04 | chờ STA-04 |
| Mật độ sau đặt cell | chờ STA-04 | chờ STA-04 |
| Số ICG, tỉ lệ flop được gate | chờ STA-04 | chờ STA-04 |
| Công suất (mW) ở 50 MHz, CoreMark | chờ STA-04 | chờ STA-04 |
| EPI (pJ/lệnh) = P × CPI / f | chờ STA-04 | chờ STA-04 |
| Công suất chờ ngắt: polling so với WFI | chờ STA-04 | chờ STA-04 |
| LEC RTL ↔ netlist | chờ STA-04 | chờ STA-04 |

## X.7 Giới hạn đã biết

- **Không hỗ trợ truy cập lệch bằng phần cứng.** Load, store lệch gây trap (mục 4.1). Vì vậy `rv32ui-p-ma_data` bị loại (`docs/riscv-tests-status.md`).
- **Chỉ M-mode.** Không có S/U-mode, PMP, debug trigger. Loại `rv32mi-p-breakpoint`, `rv32mi-p-pmpaddr` và 41 test `pmp32` (`docs/riscof.md`).
- **CSR ngoài bảng mục 4.7 là illegal** (mstatush, mcounteren, mcountinhibit...) (D-022).
- **Ngắt lặp quá nhanh làm phép chia không bao giờ xong.** Ngắt được nhận giữa phép chia và phép chạy lại sau MRET. Nếu ngắt tới nhanh hơn khoảng 34 chu kỳ cộng thời gian trình xử lý thì phép chia không kết thúc. Ngắt của Timer, UART, GPIO chậm hơn nhiều nên chấp nhận (D-032).
- **Nhảy tới đúng PC+4 vẫn mất 1 chu kỳ**, vì không so sánh đích để giữ đường găng ngắn (D-014).
- **Khi WB chờ mà EX trống, IF vẫn dừng**, mất tối đa 1 chu kỳ (D-014).
- **CPI chỉ đúng với bộ nhớ không wait state.** Trên SoC, SB/SH vào SRAM có 1 wait state (mục 5.1 luật 6) và truy cập dữ liệu vào IMEM chiếm cổng lấy lệnh (`docs/bench_core.md`).
- **CoreMark bản rv32i chỉ dư khoảng 1,4 KB IMEM** ở cấu hình 16 KB của tb_core (`docs/bench_core.md`).
- **Tràn nửa thấp của `minstret`** chỉ được kiểm bằng chứng minh hình thức, không có test mô phỏng (cần 2^32 lệnh). Tràn của `mcycle` có test (`trap.S` test 83, 84) (`docs/timing_core.md`).
- **`wb_instr_q` (32 bit) nạp mỗi lệnh** dù chỉ cần cho lệnh CSR và mtval của illegal. Chưa chặn vì `tb_core` dùng nó để in vết (`docs/timing_core.md`, D-037).
- **Số timing ở nhà chỉ là xu hướng.** Số chính thức: chờ STA-04.
