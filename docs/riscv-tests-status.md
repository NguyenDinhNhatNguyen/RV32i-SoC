# Kết quả riscv-tests và test assembly của core

Cập nhật sau mỗi phase của core. Bảng riscv-tests sinh bằng `python3 scripts/isa_status.py` sau `make isa-core`.

- riscv-tests: submodule `fw/riscv-tests`, ghim commit `3df703cd52d5` (19/10/2026), env `p` (submodule con `env` ở `6de71edb142b`). Lấy về: `git submodule update --init --recursive fw/riscv-tests`.
- Link bằng `fw/common/link_isa.ld` (mọi section ở IMEM, xem D-029).
- Cấu hình tb_core: `M<ENABLE_M>W<ENABLE_WFI_SLEEP>`. Mỗi ô là số chế độ đạt trên 4 chế độ (nominal có `+strict_timing`, stall1, stall2, stall3).

## Phase P4 (CSR, trap, ngắt, WFI)

Tổng: rv32ui-p 41/41 test áp dụng được, rv32mi-p 14/14 test áp dụng được, 440/440 lần chạy đạt. rv32um chạy từ P7.

### riscv-tests

| Test | M0W0 | M1W1 | Kết quả |
| --- | --- | --- | --- |
| rv32ui-p-add | 4/4 | 4/4 | PASS |
| rv32ui-p-addi | 4/4 | 4/4 | PASS |
| rv32ui-p-and | 4/4 | 4/4 | PASS |
| rv32ui-p-andi | 4/4 | 4/4 | PASS |
| rv32ui-p-auipc | 4/4 | 4/4 | PASS |
| rv32ui-p-beq | 4/4 | 4/4 | PASS |
| rv32ui-p-bge | 4/4 | 4/4 | PASS |
| rv32ui-p-bgeu | 4/4 | 4/4 | PASS |
| rv32ui-p-blt | 4/4 | 4/4 | PASS |
| rv32ui-p-bltu | 4/4 | 4/4 | PASS |
| rv32ui-p-bne | 4/4 | 4/4 | PASS |
| rv32ui-p-fence_i | 4/4 | 4/4 | PASS |
| rv32ui-p-jal | 4/4 | 4/4 | PASS |
| rv32ui-p-jalr | 4/4 | 4/4 | PASS |
| rv32ui-p-lb | 4/4 | 4/4 | PASS |
| rv32ui-p-lbu | 4/4 | 4/4 | PASS |
| rv32ui-p-ld_st | 4/4 | 4/4 | PASS |
| rv32ui-p-lh | 4/4 | 4/4 | PASS |
| rv32ui-p-lhu | 4/4 | 4/4 | PASS |
| rv32ui-p-lui | 4/4 | 4/4 | PASS |
| rv32ui-p-lw | 4/4 | 4/4 | PASS |
| rv32ui-p-or | 4/4 | 4/4 | PASS |
| rv32ui-p-ori | 4/4 | 4/4 | PASS |
| rv32ui-p-sb | 4/4 | 4/4 | PASS |
| rv32ui-p-sh | 4/4 | 4/4 | PASS |
| rv32ui-p-simple | 4/4 | 4/4 | PASS |
| rv32ui-p-sll | 4/4 | 4/4 | PASS |
| rv32ui-p-slli | 4/4 | 4/4 | PASS |
| rv32ui-p-slt | 4/4 | 4/4 | PASS |
| rv32ui-p-slti | 4/4 | 4/4 | PASS |
| rv32ui-p-sltiu | 4/4 | 4/4 | PASS |
| rv32ui-p-sltu | 4/4 | 4/4 | PASS |
| rv32ui-p-sra | 4/4 | 4/4 | PASS |
| rv32ui-p-srai | 4/4 | 4/4 | PASS |
| rv32ui-p-srl | 4/4 | 4/4 | PASS |
| rv32ui-p-srli | 4/4 | 4/4 | PASS |
| rv32ui-p-st_ld | 4/4 | 4/4 | PASS |
| rv32ui-p-sub | 4/4 | 4/4 | PASS |
| rv32ui-p-sw | 4/4 | 4/4 | PASS |
| rv32ui-p-xor | 4/4 | 4/4 | PASS |
| rv32ui-p-xori | 4/4 | 4/4 | PASS |
| rv32mi-p-csr | 4/4 | 4/4 | PASS |
| rv32mi-p-illegal | 4/4 | 4/4 | PASS |
| rv32mi-p-instret_overflow | 4/4 | 4/4 | PASS |
| rv32mi-p-lh-misaligned | 4/4 | 4/4 | PASS |
| rv32mi-p-lw-misaligned | 4/4 | 4/4 | PASS |
| rv32mi-p-ma_addr | 4/4 | 4/4 | PASS |
| rv32mi-p-ma_fetch | 4/4 | 4/4 | PASS |
| rv32mi-p-mcsr | 4/4 | 4/4 | PASS |
| rv32mi-p-sbreak | 4/4 | 4/4 | PASS |
| rv32mi-p-scall | 4/4 | 4/4 | PASS |
| rv32mi-p-sh-misaligned | 4/4 | 4/4 | PASS |
| rv32mi-p-shamt | 4/4 | 4/4 | PASS |
| rv32mi-p-sw-misaligned | 4/4 | 4/4 | PASS |
| rv32mi-p-zicntr | 4/4 | 4/4 | PASS |

### Test bị loại

| Test | Lý do |
| --- | --- |
| rv32ui-p-ma_data | Cần load/store lệch địa chỉ chạy đúng (bằng phần cứng hoặc trình xử lý trap giả lập). Core gây ngoại lệ lệch địa chỉ theo mục 4.1, env `p` không có trình giả lập nên test dừng ở trap mcause 4 ngay lệnh đầu tiên. Các test rv32mi `ma_addr`, `lh/lw/sh/sw-misaligned` kiểm tra đúng hành vi trap này và đều đạt |
| rv32mi-p-breakpoint | Cần debug trigger (`tselect`, `tdata1`). Core không có Sdtrig nên `csrw tselect` là illegal và test 2 báo lỗi |
| rv32mi-p-pmpaddr | Cần PMP (`pmpcfg0`, `pmpaddr0`). Core không có PMP |

### Test assembly (`make fw-core`)

| Test | M0W0 | M0W1 | M1W0 | M1W1 | Nội dung |
| --- | --- | --- | --- | --- | --- |
| smoke | 4/4 | 4/4 | 4/4 | 4/4 | Mọi lệnh RV32I với toán hạng biên (P3) |
| hazard | 4/4 | 4/4 | 4/4 | 4/4 | Forward, load-use, nhánh, thanh ghi giữ (P3) |
| trap | 4/4 | 4/4 | 4/4 | 4/4 | Giá trị reset và mặt nạ CSR, CSR không tồn tại và ghi CSR chỉ đọc, mọi ngoại lệ đồng bộ (mcause, mepc, mtval, rd và bộ nhớ không đổi), mstatus khi trap và MRET, mcycle, minstret, time |
| irq | 4/4 | 4/4 | 4/4 | 4/4 | mip theo cổng, MIE và mie chặn ngắt, ưu tiên MEI > MSI > MTI, ngắt chính xác (90 thời điểm ngắt khác nhau trong đoạn tính toán), không nhận ngắt sau lệnh tắt MIE / mie |
| wfi | 4/4 | 4/4 | 4/4 | 4/4 | WFI với MIE = 0 và MIE = 1, nguồn bị tắt trong mie không đánh thức, ngắt chờ sẵn thì không ngủ, số chu kỳ ngủ, mepc = PC(WFI)+4 |

Số chu kỳ ngủ của `wfi` (nominal): với W1 core ngủ 801 trên 1003 chu kỳ và chỉ chạy 177 lệnh. Với W0 (WFI là NOP, chờ bằng vòng lặp) cùng test chạy 625 lệnh trong 954 chu kỳ.
