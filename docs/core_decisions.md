# Nhật ký quyết định thiết kế core RV32I

Mỗi mục: bối cảnh, lựa chọn, lý do, phương án đã loại. Đánh số tăng dần, không xoá mục cũ. Nếu đổi ý thì thêm mục mới ghi "thay thế D-xxx".

Chép từ nhật ký của phần core khi tích hợp vào repo nhóm. Giữ nguyên số mục. D-001 (vị trí RTL accelerator Lab), D-005 (môi trường máy nhà) và D-013 (wrapper accelerator) không thuộc core nên không chép. "Mục x.y" là mục trong `docs/spec/core.md`.

---

## P1 – Khung dự án

### D-002. Hằng số dùng `` `define `` có tiền tố, không dùng `localparam`

- **Bối cảnh:** Hằng số của core phải nằm trong `rtl/core/rv32_defs.vh`, không viết số trần trong logic.
- **Lựa chọn:** Macro `` `define `` với tiền tố `RV_`, có include guard. File `.vh` không có `` `timescale `` hay `` `default_nettype `` vì được include vào giữa file `.v` (file `.v` đã có).
- **Lý do:** `localparam` trong file include bị khai báo lại ở mọi module, module chỉ dùng một phần sẽ sinh `UNUSEDPARAM` với `verilator -Wall` (vi phạm 0 warning). Macro không có vấn đề này, tiền tố tránh trùng tên toàn cục.
- **Đã loại:** SystemVerilog `package` (RTL phải là Verilog-2001), `localparam` kèm waiver (nhiều waiver vô nghĩa).

### D-003. Chiến lược lint

- **Bối cảnh:** Cần lint được ngay từ khi mới có các khối nhỏ, trước khi có `rv32_core`.
- **Lựa chọn:** `make lint-core` chạy `verilator --lint-only -Wall` cho **từng** module trong `rtl/core`, mỗi module làm top riêng, `rtl/core` làm `-y`. `rv32_core` được lint cùng toàn bộ phân cấp. Module có tham số `ENABLE_*` được lint với mọi giá trị khai báo trong `CORE_LINT_CFG_<module>` (hiện có `rv32_core` và `rv32_decoder` với `ENABLE_M=0/1`). Warning của Verilator là lỗi (mặc định), nên "pass" nghĩa là 0 warning.
- **Lý do:** Lint từng module bắt được cổng vào không dùng mà lint từ top có thể che khuất qua tham số.
- **Đã loại:** Chỉ lint top.

### D-004. Cấu hình tham số cho unit test

- **Lựa chọn:** `CORE_UNIT_CFG_<tb>` trong Makefile liệt kê các bộ tham số. Mỗi bộ biên dịch riêng bằng `iverilog -P<tb>.<P>=<V>`. Testbench được coi là pass khi log có dòng bắt đầu bằng `PASS` và không có dòng `FAIL`.
- **Lý do:** Một testbench dùng cho cả ENABLE_M=0 và 1, không nhân bản file.

---

## P2 – Khối cơ bản của core

### D-006. Mã hoá phép toán ALU = `{instr[30], funct3}`

- **Lựa chọn:** `RV_ALU_*` 4 bit, bit 3 là bit "alt" (SUB/SRA), bit 2:0 là funct3. ADD=0000, SUB=1000, SLL=0001, SLT=0010, SLTU=0011, XOR=0100, SRL=0101, SRA=1101, OR=0110, AND=0111.
- **Lý do:** Decoder gần như nối thẳng bit lệnh, logic giải mã tối thiểu. Riêng OP-IMM chỉ dùng `instr[30]` khi funct3=101 (ADDI có bit 30 là bit immediate, không được thành SUB).
- **Đã loại:** Mã one-hot (rộng hơn, không lợi về timing ở ALU 10 phép).

### D-007. ALU tính cả địa chỉ và đích nhảy, so sánh nhánh tách riêng

- **Lựa chọn:** ALU (phép ADD) tính địa chỉ load/store (rs1+imm), đích JALR (rs1+imm), đích JAL/branch (pc+imm), LUI (0+imm), AUIPC (pc+imm). Điều kiện nhánh do một bộ so sánh riêng trong `rv32_core`. Địa chỉ trả về rd của JAL/JALR là PC+4 (`RV_WB_PC4`), do core tính bằng bộ cộng hằng riêng. Bit 0 của đích JALR do core xoá.
- **Lý do:** Lệnh nhánh không dùng ALU cho việc khác nên dùng chung bộ cộng, tiết kiệm diện tích. Bộ so sánh riêng chạy song song với bộ cộng đích, không nối tiếp (đường găng 2 ở mục 4.5).
- **Đã loại:** Dùng ALU SUB để so sánh nhánh rồi thêm bộ cộng đích riêng (zero-detect sau bộ trừ làm dài đường găng, vẫn cần thêm bộ cộng).
- **Chi tiết ALU:** SUB, SLT, SLTU dùng chung một bộ trừ 33 bit. SLTU = bit mượn. SLT = bit mượn khi cùng dấu, ngược lại là dấu của a. Dịch chỉ dùng `b[4:0]`.

### D-008. Ngõ ra decoder

- **Lựa chọn:** Decoder xuất: trường thanh ghi, `funct3_o` (dùng chung cho điều kiện nhánh, kích thước/dấu load-store, phép CSR, phép M), `csr_addr_o`, `imm_type_o`, chọn toán hạng ALU (`RV_ALU_A_RS1/PC/ZERO`, `RV_ALU_B_RS2/IMM`), `wb_sel_o` (`ALU/PC4/LOAD/CSR`, kết quả M-unit được mux vào nhánh ALU ngay ở EX), cờ `branch/jal/jalr/load/store/md/csr/csr_we/ecall/ebreak/mret/wfi/fence_i`, `illegal_o`, `rd_we_o`.
- **`rd_we_o` đã bằng 0 khi rd = x0:** logic forward và ghi register file chỉ cần nhìn `rd_we`.
- **Khi `illegal_o=1`:** mọi cờ có tác dụng phụ bị ép 0 ngay trong decoder, core chỉ cần xử lý một tín hiệu.
- **FENCE:** thực thi như NOP nên không có cờ riêng (không illegal, không ghi gì).

### D-009. Phạm vi kiểm tra illegal trong decoder

- **Lựa chọn:** Decoder báo illegal cho: `instr[1:0] != 11` (không có C), opcode không hỗ trợ, funct3 dành riêng ở JALR, BRANCH, LOAD, STORE, MISC-MEM, SYSTEM (funct3=100), funct7 sai ở OP/OP-IMM (gồm SLLI/SRLI/SRAI có `shamt[5]=1`), lệnh M khi `ENABLE_M=0`. Ở SYSTEM funct3=000 chỉ chấp nhận đúng nguyên word ECALL, EBREAK, MRET, WFI (SRET, URET, DRET, SFENCE.VMA, ECALL có rd hoặc rs1 ≠ 0 đều illegal).
- **FENCE/FENCE.I:** chỉ kiểm tra funct3, bỏ qua rs1, rd, imm theo yêu cầu tương thích về sau của đặc tả Unprivileged (fence.tso và mọi tổ hợp pred/succ đều hợp lệ).
- **CSR:** sự tồn tại của địa chỉ CSR và việc ghi CSR chỉ đọc kiểm tra trong `rv32_csr` (P4) vì cần biết có ghi hay không. Decoder cung cấp `csr_we_o`: CSRRW/CSRRWI luôn ghi, CSRRS/CSRRC/CSRRSI/CSRRCI chỉ ghi khi trường rs1/uimm ≠ 0 (mục 4.7).

### D-010. Immediate generator

- **Lựa chọn:** `rv32_imm_gen` nhận `instr[31:7]` và `imm_type` từ decoder. Có 6 dạng I, S, B, U, J và Z (uimm CSR = trường rs1 mở rộng 0).
- **Lý do:** Không cần opcode (đã giải mã) nên cổng không có bit thừa (tránh `UNUSEDSIGNAL`). Dạng Z cho phép CSR*I dùng chung đường immediate.

### D-011. Register file

- **Lựa chọn:** 31 thanh ghi flop (x0 không lưu, đọc ra 0), mỗi thanh ghi có reset bất đồng bộ về 0 và enable ghi riêng (giải mã one-hot từ rd). Hai cổng đọc tổ hợp, không có bypass ghi→đọc bên trong.
- **Lý do:** Reset xác định cho GLS. Enable riêng từng thanh ghi để Genus gate clock theo nhóm. Bypass do mạng forward WB→EX của core lo (mục 4.5), thêm bypass trong regfile sẽ trùng chức năng và kéo dài đường găng 2.
- **Đã loại:** Mảng `reg` ghi trong vòng `for` có reset (một số phiên bản Verilator báo `BLKLOOPINIT`/`MULTIDRIVEN`), regfile dùng SRAM hoặc latch (cần macro, không reset được).

### D-012. Phương pháp kiểm tra đơn vị

- **ALU:** mô hình tham chiếu viết khác RTL (so sánh `$signed`, SRA bằng mặt nạ), vector biên viết tay kết quả, quét đủ 64 giá trị dịch trên các toán hạng biên, mọi cặp toán hạng biên, ngẫu nhiên có thiên vị về giá trị biên.
- **Imm gen:** kiểm tra theo chiều ngược. Mã hoá giá trị immediate vào lệnh theo bố cục bit trong đặc tả (các bit khác ngẫu nhiên) rồi so với ngõ ra. Có biên min/max từng dạng, walking-one, ngẫu nhiên.
- **Decoder:** mô hình độc lập là bảng MASK/MATCH của riscv-opcodes kèm tín hiệu điều khiển kỳ vọng theo tên lệnh. Mọi word không khớp bảng phải illegal. Kích thích gồm mọi lệnh với trường tự do ngẫu nhiên (thêm biến thể rd=x0, rs1=x0), các mã illegal và gần đúng viết tay, word ngẫu nhiên có opcode hợp lệ, word ngẫu nhiên hoàn toàn. Kiểm tra coverage mọi mục trong bảng. Chạy với ENABLE_M=0 và 1. Tín hiệu "không quan tâm" (imm_type, chọn ALU, wb_sel) chỉ so khi lệnh dùng tới.
- **Regfile:** mô hình mảng. Kiểm tra giá trị sau reset, x0 bỏ qua ghi, giá trị mới chỉ thấy sau cạnh clock (không bypass), ghi liên tiếp, lưu lượng ngẫu nhiên, reset bất đồng bộ giữa chu kỳ.
- **Kiểm tra độ nhạy:** đã cấy thử 9 lỗi vào bản sao RTL (ADDI thành SUB, csr_we luôn 1, bỏ che rd=x0, chấp nhận SLLI shamt[5], SLT sai dấu, SRA thành SRL, sai bit 11 immediate B, x0 ghi được, thêm bypass). Testbench bắt được cả 9.
- Mọi testbench nhận `+seed=`, `+n=`, `+timeout=` và in seed để tái lập.

---

## P3 – Core 3 tầng (chưa có CSR/trap)

### D-014. Điều khiển pipeline

- **Dừng:** `wb_wait` = WB giữ load/store chưa có `d_rsp_valid_i`. `ex_wait` = yêu cầu bus của EX chưa được nhận (`d_req_valid_o && !d_req_ready_i`). `pipe_stall = wb_wait | ex_wait` dừng IF và EX. WB chỉ giữ lệnh khi `wb_wait`, còn khi chỉ có `ex_wait` thì lệnh ở WB vẫn hoàn thành và WB nhận bubble. P7 thêm điều kiện chờ M-unit vào `ex_wait`.
- **Theo dõi lệnh ở EX:** `ex_fetch_q` = chu kỳ trước có lấy lệnh được cấp quyền (`if_req_o && if_gnt_i`), không dừng và không có chuyển hướng. Ngõ ra IMEM chỉ được coi là lệnh khi bit này bằng 1, nên lệnh sai đường (PC+4 sau nhánh nhảy) và chu kỳ IMEM bị bus dữ liệu chiếm đều thành bubble, không cần mux NOP trên đường lệnh.
- **Thanh ghi giữ:** chu kỳ đầu tiên dừng chốt `if_rdata_i`/`if_err_i` vào `ex_instr_hold_q`/`ex_ferr_hold_q`, `ex_hold_q`=1. EX đọc thanh ghi giữ đến hết dừng. `if_pc_q` không đổi trong lúc dừng, nên ở chu kỳ hết dừng IMEM đang đọc đúng lệnh kế tiếp. Lệnh lấy trong chu kỳ dừng bị bỏ và được lấy lại.
- **Dừng cả khi EX trống:** khi WB chờ mà EX là bubble, IF vẫn dừng. Cách này đơn giản hơn (một tín hiệu dừng chung) và chỉ mất tối đa 1 chu kỳ trong trường hợp này.
- **Chuyển hướng:** `ex_redirect = ex_go & ex_valid & ex_jump & ~ex_exc`, chỉ ở chu kỳ lệnh rời EX. Đích nhảy vào flop `if_pc_q`. Nhảy tới đúng PC+4 vẫn mất 1 chu kỳ (không so sánh đích để tiết kiệm logic trên đường găng 2).
- **`if_req_o` = 1 cố định ở P3.** Cho `if_req_o` phụ thuộc `pipe_stall` sẽ nối `d_req_ready_i` tổ hợp vào chân enable IMEM (đường dài qua sys_bus/APB). P4 xoá `if_req_o` khi ngủ WFI (tín hiệu đến từ flop).
- **Flop tầng WB** chỉ nạp khi có lệnh thật (`ex_go & ex_valid`). Đây là enable cho clock gating, và giá trị X từ ngõ ra IMEM lúc rảnh không lọt vào flop (GLS).
- **Forward WB→EX** lấy cả khi WB là load đang chờ. Lúc đó EX đang dừng, `d_req_valid_o` bị chặn bởi `wb_wait`, nhánh bị chặn bởi `ex_go`, nên giá trị cũ không gây tác dụng phụ.
- **Đã loại:** thanh ghi lệnh IF/EX (thêm 1 tầng, trái mục 4.3), phát lại `ex_pc` lên IMEM khi dừng thay cho thanh ghi giữ (địa chỉ IMEM sẽ đi qua mux tổ hợp từ `ready`).

### D-015. Yêu cầu bus dữ liệu từ core

- `d_addr_o` là địa chỉ byte đầy đủ (slave dùng `addr[31:2]` và `be`). `d_be_o` có nghĩa cả với lệnh đọc (theo kích thước), để `apb_bridge` từ chối truy cập byte/half bằng cách xem `be != 4'b1111`.
- Dữ liệu ghi được **lặp** ra mọi làn (`{4{rs2[7:0]}}`, `{2{rs2[15:0]}}`) thay vì dịch. Làn được `be` chọn luôn đúng, không cần bộ dịch. Mục 4.6 chỉ yêu cầu dữ liệu nằm đúng làn byte.
- `d_req_valid_o = ex_valid & (load|store) & ~ex_exc & ~wb_wait`: phụ thuộc tổ hợp vào `d_rsp_valid_i` (luật 3, phát yêu cầu mới ngay trong chu kỳ nhận phản hồi) nhưng không phụ thuộc vào `d_req_ready_i` (luật 5). Lệnh lệch địa chỉ không phát yêu cầu.
- Store hoàn thành ở WB khi có `rsp_valid` (để P4 bắt `err` thành store access fault). Load bị `err` không ghi rd.

### D-016. Lệnh chưa thực thi ở P3 và ngoại lệ

- **Bối cảnh:** P3 chưa có CSR/trap, đặc tả cho phép lệnh SYSTEM làm dừng mô phỏng.
- **Lựa chọn:** EX phát hiện ngoại lệ theo thứ tự ưu tiên của đặc tả Privileged (instruction access fault > illegal > EBREAK > ECALL > instruction misaligned (đích nhảy có bit 1) > load misaligned > store misaligned) và gắn `wb_exc_q`/`wb_cause_q`. Lệnh CSR, MRET, WFI, FENCE.I, RV32M gắn `wb_unsup_q`. Lệnh bị gắn cờ không ghi rd, không phát yêu cầu bus, không chuyển hướng. `tb_core` dừng (FAIL) khi lệnh như vậy tới WB.
- **Lý do:** P4 chỉ cần thêm phần xử lý ở WB (CSR, trap, chuyển hướng từ WB), đường phát hiện ở EX đã có và đã được kiểm tra.
- **Cổng chưa có ở P3:** `irq_*_i`, `mtime_i`, `core_sleep_o` và tham số `ENABLE_WFI_SLEEP` thêm ở P4 cùng logic dùng chúng (cổng hoặc tham số không dùng sẽ sinh `UNUSED*` với `-Wall`).
- **Waiver lint:** các tín hiệu chỉ dùng từ P4 (`ex_csr_addr`, `ex_csr_we`, `wb_pc_q`, `wb_instr_q`, `wb_exc_q`, `wb_cause_q`, `wb_unsup_q`, `wb_retire`) được gom vào `wire unused_p4`. Verilator mặc định bỏ qua tín hiệu có tên chứa `unused`, nên đây là waiver duy nhất. Waiver có comment lý do trong RTL và bị xoá dần khi P4 dùng tới.

### D-017. `tb_core`

- **Bộ nhớ:** IMEM và DMEM là `sram_1rw_model`. IMEM dùng chung cho cổng lệnh và bus dữ liệu giống `imem_port`: yêu cầu dữ liệu vào IMEM (kể cả đang wait state) làm `if_gnt=0`. Lấy lệnh ngoài IMEM → `if_err`. Dữ liệu: IMEM, DMEM, UART DATA (in ký tự ngay), còn lại trả `err`.
- **Bus chậm giả lập:** `+if_stall=%` (không cấp quyền lấy lệnh), `+d_stall=%` (`d_req_ready=0`), `+rsp_delay=N` (phản hồi trễ thêm 0..N chu kỳ, dữ liệu SRAM được chốt ở chu kỳ sau khi nhận). Quyết định ngẫu nhiên đổi ở cạnh xuống, seed cố định.
- **Kiểm tra giao thức:** yêu cầu phải giữ nguyên khi `ready=0` (luật 1), không có yêu cầu thứ hai khi còn phản hồi chờ (luật 3), không X trên `valid`, địa chỉ hay dữ liệu ghi, không ghi X vào rd, load/store chỉ hoàn thành đúng chu kỳ có `rsp_valid`.
- **`+strict_timing`** (chạy không stall): giữa hai lệnh hoàn thành liên tiếp phải có đúng 1 bubble sau lệnh nhảy thật (lấy từ `ex_redirect`, nên nhảy tới PC+4 vẫn tính), đúng 1 bubble sau truy cập dữ liệu vào IMEM, còn lại 0. Như vậy chứng minh không có stall load-use, load liên tiếp mỗi chu kỳ, phạt nhánh đúng 1 chu kỳ.
- **Kết thúc:** store vào `tohost` hoàn thành ở WB. In số chu kỳ, số lệnh, CPI. `+trace` in vết theo định dạng commit log của Spike (`core 0: 3 pc (instr) xN value`), lấy bằng tham chiếu phân cấp.
- `make fw-core`: mỗi test × `ENABLE_M` = 0/1 × 4 chế độ (nominal có strict timing, 3 bộ stall với seed khác nhau).

### D-018. Build phần mềm cho test assembly

- `fw/common/link.ld` theo đúng bố cục mục 10.1 (firmware C dùng lại được, thêm crt0). `.data` có địa chỉ nạp = địa chỉ chạy trong DMEM, tb nạp thẳng `dmem.hex`.
- `scripts/elf2hex.py` tự đọc ELF32 (không cần pyelftools), đặt section theo VMA, lấy base và kích thước vùng từ `tb/core/core_tb_map.vh` (D-020), ghi đủ cả vùng (độn 0) để `$readmemh` không cảnh báo, in `tohost=<hex>`.
- `tb/models/sram_1rw_model.v`: nội dung khởi tạo 0 trước khi nạp file (giống phần cứng sau bootloader/crt0 hơn là X lan truyền vào nhánh). Khi ghi, `rdata_o` giữ giá trị cũ. Tên plusarg nạp file là tham số `INIT_PLUSARG`.
- Test assembly dùng macro kiểu riscv-tests (`fw/tests/asm/test_macros.h`). Giá trị kỳ vọng của phần sinh tự động trong `smoke.S` được tính bằng mô hình Python độc lập lúc viết test, ghi thẳng vào file.

### D-019. Bằng chứng kiểm tra P3

- `smoke.S` (khoảng 550 lệnh kiểm tra: mọi lệnh RV32I trừ SYSTEM/FENCE.I với toán hạng biên, địa chỉ trả về và đích JAL/JALR, x0, truy cập dữ liệu vào IMEM) và `hazard.S` (forward ALU/load vào rs1, rs2 hoặc cả hai, ưu tiên giá trị mới nhất, x0 không forward, load→load địa chỉ, load→store dữ liệu và địa chỉ, store→load cùng địa chỉ, nhánh/JALR dùng kết quả load, lệnh sai đường không có tác dụng, chuỗi nhảy liên tiếp, vòng lặp danh sách liên kết).
- Cấy 17 lỗi vào bản sao core (bỏ forward rs1/rs2, forward cả khi rd_we=0, không huỷ lệnh sai đường, bỏ thanh ghi giữ, phát yêu cầu khi đang chờ phản hồi, WB không xoá khi `ex_wait`, BGE thành BGEU, JALR giữ bit 0, link = pc, chuyển hướng khi đang dừng, PC tăng khi không được cấp quyền, ghi rd khi chưa có phản hồi, LH mở rộng 0, SB không lặp làn, SH sai làn, dịch load sai) và 5 lỗi vào `rv32_lsu_align`. `make fw-core` và `tb_rv32_lsu_align` bắt được cả 22. Lỗi chỉ lộ khi bus chậm (thanh ghi giữ, chuyển hướng khi dừng) chỉ bị bắt ở chế độ stall, đúng như mong đợi.

---

## Tích hợp vào repo nhóm

### D-020. Vị trí file và bản đồ địa chỉ cho tb_core

- **Bối cảnh:** Phần core được chuyển sang repo nhóm (nhánh `feat/nhan-core`). Repo nhóm có cấu trúc riêng (`fw/` thay cho `sw/`, testbench và mô hình mô phỏng nằm trong `tb/`). Bản cũ lấy vùng địa chỉ từ `rtl/soc/soc_defs.vh`, file này chứa cả bản đồ thanh ghi ngoại vi và accelerator. Bản đồ thanh ghi accelerator trong đó khác với `rtl/accel/accel_wrapper.v` và `fw/accel.h` của nhóm.
- **Lựa chọn:**
  - `rtl/core/*` giữ nguyên. Unit test ở `tb/unit/tb_rv32_*.v`, `tb_core` và header của nó ở `tb/core/`, `sram_1rw_model` ở `tb/models/`, test assembly ở `fw/tests/asm/`, `link.ld` ở `fw/common/`, `elf2hex.py` ở `scripts/`.
  - Không chép `soc_defs.vh`. Thay bằng `tb/core/core_tb_map.vh` chỉ gồm những gì `tb_core` và `elf2hex.py` cần: base và kích thước IMEM, DMEM, địa chỉ UART DATA. Macro có tiền tố `CORE_TB_` để không trùng với header SoC sau này.
  - Target Makefile có tiền tố riêng (`lint-core`, `unit-core`, `fw-core`, `clean-core`), biến có tiền tố `CORE_`, chỉ thêm vào cuối Makefile và thêm dòng vào `make help`, không đổi target có sẵn. Recipe của core cần bash nên `SHELL` chỉ đặt riêng cho các target này.
  - Kết quả mô phỏng ở `tb/unit/out/core` và `tb/core/out`, đã nằm trong mẫu `tb/**/out/` của `.gitignore`.
  - Comment trong code chuyển sang tiếng Việt theo quy ước repo. Logic RTL và testbench không đổi, trừ việc đổi tên macro địa chỉ trong `tb_core`.
- **Lý do:** Bản đồ địa chỉ đầy đủ của SoC thuộc phần bus/bộ nhớ (Phát) và accelerator (Nguyên). Chép nguyên `soc_defs.vh` sẽ tạo một nguồn thứ hai mâu thuẫn với RTL accelerator của nhóm. Khi có header SoC chung, `core_tb_map.vh` chỉ cần khớp hoặc trỏ sang đó.
- **Đã loại:** Chép nguyên `rtl/soc/soc_defs.vh` (mâu thuẫn bản đồ accelerator, lấn phần của người khác), đặt vùng địa chỉ trong `rtl/core` (core không phụ thuộc bản đồ địa chỉ, chỉ có `RESET_PC`).

---

## P4 – CSR, trap, ngắt, WFI

### D-021. Khối `rv32_csr` với cổng kiểm tra ở EX và cổng đọc/ghi ở WB

- **Bối cảnh:** Mục 4.7 cho lệnh CSR thực thi ở WB. D-009 để việc kiểm tra địa chỉ CSR cho `rv32_csr`.
- **Lựa chọn:** `rv32_csr` có hai cổng. Cổng kiểm tra (tổ hợp) nhận `ex_csr_addr` và `ex_csr_we` từ decoder, báo CSR không tồn tại hoặc ghi vào vùng chỉ đọc `addr[11:10]=11`. Lỗi này gộp vào illegal của EX nên đi chung đường ngoại lệ với mọi lỗi khác. Cổng đọc/ghi dùng địa chỉ `wb_instr_q[31:20]`, đọc giá trị cũ và ghi theo RW/RS/RC ở WB. Giá trị cũ đi vào `wb_rd_data` nên được forward sang EX như kết quả ALU.
- **Lý do:** Phát hiện ở EX giữ đúng mô hình "ngoại lệ gắn cờ ở EX, xử lý ở WB" của D-016. WB không cần thêm điều kiện trap, nên `d_req_valid_o` không phụ thuộc kết quả giải mã CSR.
- **Đã loại:** Kiểm tra ở WB (thêm một nguồn trap ở WB, kéo dài đường `wb_redirect` → `d_req_valid_o`), đọc CSR ở EX (lệnh CSR ghi ở WB cùng chu kỳ sẽ cần bypass riêng, bộ đếm đổi mỗi chu kỳ).
- **Theo dõi timing:** Đường forward giờ có thêm mux đọc CSR (khoảng 23 nguồn) từ flop `wb_instr_q`. Ngắn hơn đường găng 1 (DMEM clk→Q → căn chỉnh) nhưng cần xem khi tổng hợp.

### D-022. Giá trị mang sang WB và mtval

- **Lựa chọn:** `wb_result_q` chở thêm thông tin, không thêm flop 32 bit mới.
  - Lệnh CSR: toán hạng ghi (`funct3[2] ? uimm : rs1`).
  - JAL/JALR bị ngoại lệ: đích nhảy đã xoá bit 0 thay cho PC+4.
  - Load/store và nhánh: kết quả ALU (địa chỉ, đích).
- **mtval:** illegal = mã lệnh (`wb_instr_q`), instruction access fault = PC, lệch địa chỉ và access fault của load/store = `wb_result_q`, ECALL, EBREAK và ngắt = 0. Đúng mục 4.8. EBREAK đổi thành PC ở D-035.
- **mcause** lưu bit 31 và 5 bit mã (WLRL, chỉ cần giữ giá trị hợp lệ 0..11). **mtvec** reset về 0, chế độ direct. **mepc** và **mtvec** không lưu bit 1:0.
- CSR ngoài bảng mục 4.7 (mstatush, mcounteren, mcountinhibit, PMP, debug, CSR của S/U) là illegal. riscv-tests env `p` chịu được điều này vì luôn đặt `mtvec` trước khi chạm các CSR đó.

### D-023. Chuyển hướng từ WB

- **Lựa chọn:** `wb_redirect = trap | MRET | FENCE.I | WFI (khi ENABLE_WFI_SLEEP=1)`, chỉ ở chu kỳ lệnh rời WB. Đích: `mtvec` (trap), `mepc` (MRET), PC+4 (FENCE.I, WFI). Ưu tiên hơn `ex_redirect` ở `if_pc_q`. Lệnh ở EX bị huỷ (`wb_valid_q` không nạp), lệnh đang lấy bị huỷ (`ex_fetch_q`), `d_req_valid_o` bị chặn tổ hợp bởi `wb_redirect`.
- **Không vi phạm luật bus 1:** `wb_redirect` chỉ xảy ra ở chu kỳ đầu lệnh ở WB, hoặc ở chu kỳ có phản hồi của chính nó. Trước đó yêu cầu của EX đã bị chặn bởi `wb_wait`, nên chưa có yêu cầu nào của EX đang ở wait state khi bị huỷ.
- **Hệ quả:** `d_req_valid_o` phụ thuộc tổ hợp vào `d_rsp_err_i` (lỗi bus thành trap). Đã có phụ thuộc vào `d_rsp_valid_i` từ P3, luật 5 chỉ cấm phụ thuộc `ready`.
- **Phạt:** 2 chu kỳ trống sau lệnh chuyển hướng từ WB. tb_core kiểm tra đúng con số này ở chế độ nominal (D-028).
- **FENCE.I:** Trong tb và SoC, ghi IMEM đi qua cùng cổng với lấy lệnh nên lệnh lấy sau lệnh store luôn thấy giá trị mới. Chuyển hướng vẫn làm đúng đặc tả và là điều kiện an toàn khi có nguồn ghi IMEM khác.
- `minstret` tăng khi lệnh rời WB mà không trap. Lệnh bị trap (kể cả bị ngắt) không tính.

### D-024. Ngắt

- **Lựa chọn:** `ex_irq = ex_valid & MIE & (mip & mie != 0) & ~wb_irq_block & ~ex_req_wait_q`. Lệnh bị ngắt không thực thi, không phát yêu cầu bus, không chuyển hướng, không ghi rd. Mã ngắt (MEI > MSI > MTI) được chốt vào `wb_cause_q` lúc lệnh rời EX vì đường ngắt có thể hạ trước khi lệnh tới WB.
- **`wb_irq_block`:** WB đang ghi mstatus hoặc mie. EX đọc giá trị CSR từ flop nên ở chu kỳ đó còn thấy giá trị cũ. Chặn để lệnh ngay sau `csrci mstatus, MIE` không bị ngắt. Khi bật MIE, ngắt được nhận chậm nhất ở lệnh thứ hai sau lệnh bật (test `irq` kiểm tra). **Thay bằng forward ở D-038.**
- **`ex_req_wait_q`:** Chu kỳ trước yêu cầu bus của lệnh ở EX đã hiện ra mà chưa được nhận. Không ngắt lệnh này nữa vì luật bus 1 bắt master giữ nguyên yêu cầu. Lệnh hoàn thành rồi ngắt được nhận ở lệnh sau.
- **Đã loại:** Chốt quyết định ngắt vào flop (chậm 1 chu kỳ so với lệnh ghi mstatus/mie, phải thêm logic bù), nhận ngắt ở WB (phải huỷ lệnh đã thực thi ở WB, mất tính chính xác với store).
- Đường ngắt đi tổ hợp vào `d_req_valid_o`. Cổng ngắt của SoC lấy từ flop của Timer, UART, GPIO nên không thành đường dài.

### D-025. WFI ngủ

- **Lựa chọn:** `ENABLE_WFI_SLEEP` mặc định 1. WFI ở WB chuyển hướng tới PC+4 và đặt `sleep_q`. `if_req_o = ~sleep_q` lấy từ flop. Thức khi `(mip & mie) != 0`, không xét `mstatus.MIE`. Lúc ngủ EX và WB trống nên flop pipeline, regfile giữ nguyên (enable bằng 0). `mcycle` và `mtime` vẫn chạy.
- Sau khi thức, lệnh PC+4 được lấy lại. Nếu MIE=1 lệnh đó bị ngắt với mepc = PC(WFI)+4. Nếu MIE=0 chạy tiếp.
- Ngủ tối thiểu 1 chu kỳ kể cả khi ngắt đã chờ sẵn (không đưa ngắt tổ hợp vào `sleep_q`/`if_req_o`). Từ lúc ngắt lên tới lúc lệnh PC+4 tới WB mất 3 chu kỳ.
- `ENABLE_WFI_SLEEP=0`: WFI là NOP, không chuyển hướng.

### D-026. Bộ đếm

- `mcycle`, `minstret` 64 bit. Lệnh ghi nửa thấp hoặc nửa cao thay cho lần tăng trong chu kỳ đó (đặc tả Zicntr, riscv-tests `instret_overflow` kiểm tra cả nửa cao). Ghi nửa thấp không đổi nửa cao.
- `cycle`, `instret` và nửa cao là bí danh chỉ đọc. `time`, `timeh` đọc thẳng `mtime_i`.

### D-027. Cổng mới và waiver lint

- Thêm `irq_software_i`, `irq_timer_i`, `irq_external_i`, `mtime_i[63:0]`, `core_sleep_o` và tham số `ENABLE_WFI_SLEEP`. Xoá waiver `unused_p4` của D-016 vì mọi tín hiệu đều đã dùng.
- Waiver duy nhất còn lại là `unused_p7 = wb_unsup_q`, cờ "lệnh RV32M chưa thực thi" chỉ tb_core đọc. P7 xoá.
- `lint-core` chạy `rv32_core` với đủ 4 tổ hợp `ENABLE_M` × `ENABLE_WFI_SLEEP`, `rv32_csr` với `ENABLE_M=0/1`.
- `irq_cause_o` viết bằng `assign` thay cho `always @(*)`: Icarus không chạy `always @(*)` ở thời điểm 0 nếu đầu vào không đổi, ngõ ra sẽ là X trong mô phỏng dù logic đúng.

### D-028. tb_core cho P4

- **Cấu hình:** tên `M<ENABLE_M>W<ENABLE_WFI_SLEEP>`. `fw-core` chạy đủ 4 cấu hình × 4 chế độ.
- **Khối điều khiển của tb** ở `CORE_TB_CTRL_BASE` (0x2FFF_0000, chỉ có trong tb): ghi mức 3 đường ngắt kèm số chu kỳ chờ, đọc số chu kỳ ngủ, đọc cấu hình. `mtime_i` tăng mỗi chu kỳ.
- **Trap hợp lệ** khi chương trình đã cài `mtvec`. Trap lúc `mtvec` còn bằng 0 (giá trị reset) là FAIL, để test P3 không có trình xử lý vẫn dừng ngay khi gặp ngoại lệ.
- **Kiểm tra mới:** lệnh nhận trap không được truy cập bus (trừ khi chính truy cập đó lỗi), lúc ngủ không lấy lệnh, không truy cập bus và WB trống.
- **Strict timing:** thêm 2 chu kỳ sau chuyển hướng từ WB và cộng số chu kỳ ngủ. tb tự suy ra chuyển hướng từ mã lệnh (MRET, FENCE.I, WFI) và cờ trap, không lấy `wb_redirect` của core, để bắt lỗi thiếu chuyển hướng.
- **Chạy song song:** `scripts/core_run.sh` chạy một lần mô phỏng, Makefile gọi qua `xargs -P` (biến `CORE_JOBS`). Kết quả ở `tb/core/out/<target>.summary`.
- Dòng PASS in thêm số chu kỳ ngủ khi khác 0.

### D-029. riscv-tests

- **Submodule** `fw/riscv-tests` ghim commit `3df703cd52d5`, chạy env `p` gốc, không sửa file nào của submodule.
- **`fw/common/link_isa.ld`:** mọi section ở IMEM. `rv32ui-p-fence_i` ghi lệnh vào `.data` rồi nhảy tới đó, mà core chỉ lấy lệnh từ IMEM/boot ROM (mục 4.3). Đặt `.data` ở DMEM thì test này nhận instruction access fault. Load/store vào IMEM vẫn đi qua bus dữ liệu, DMEM đã được `smoke` và `hazard` phủ.
- **`make isa-core`:** danh sách test lấy từ thư mục `isa/rv32ui`, `isa/rv32mi`, `isa/rv32um` trừ `CORE_ISA_SKIP`. Chạy cấu hình M0W0 và M1W1 (mỗi tham số có cả hai giá trị), 4 chế độ. rv32um chỉ chạy khi ENABLE_M=1.
- **Loại có lý do:** `rv32ui-p-ma_data` (cần load/store lệch chạy đúng, trái mục 4.1), `rv32mi-p-breakpoint` (cần debug trigger), `rv32mi-p-pmpaddr` (cần PMP). Chi tiết trong `docs/riscv-tests-status.md`.
- **`tb_rv32_csr`:** quét đủ 4096 địa chỉ × đọc/ghi ở cổng kiểm tra so với bảng mục 4.7 viết lại bằng số, giá trị reset, ưu tiên ngắt.

### D-030. Bằng chứng kiểm tra P4

- `make isa-core` 440/440, `make fw-core` 80/80 (5 test × 4 cấu hình × 4 chế độ), `make unit-core` 8/8, `make lint-core` 0 warning.
- Cấy 24 lỗi vào bản sao RTL (không chặn ngắt khi ghi mstatus/mie, ngắt bỏ yêu cầu đang wait state, lệnh bị ngắt vẫn phát yêu cầu bus, chuyển hướng WB không chặn yêu cầu bus, không huỷ lệnh ở EX, không huỷ lệnh đang lấy, FENCE.I không chuyển hướng, WFI không ngủ, chỉ thức khi MIE=1, `if_req_o` không xoá khi ngủ, lệnh trap vẫn tăng minstret, load lỗi bus vẫn ghi rd, mtval lệch địa chỉ bằng 0, mtval nhảy lệch sai, tắt kiểm tra CSR, cho ghi CSR chỉ đọc, sai ưu tiên ngắt, MRET không đặt MPIE, ghi minstreth không thay lần tăng, mcycle không nhớ sang nửa cao, RC thành RS, mất bit 31 của mcause khi ngắt, cùng 2 lỗi tương đương về logic). 22 lỗi không tương đương đều bị bắt. Lệnh bị ngắt phát yêu cầu bus và FENCE.I không chuyển hướng chỉ bị bắt sau khi thêm hai kiểm tra của D-028.

---

## P7 – RV32M

### D-031. Khối `rv32_muldiv`

- **Vị trí:** ở EX, toán hạng là `ex_rs1`, `ex_rs2` sau forward. Kết quả mux vào `ex_result` (như ghi chú của D-008), đi qua `wb_result_q` và được forward như kết quả ALU. `ENABLE_M=0` thì không tạo khối (generate), decoder đã báo illegal cho lệnh M.
- **Nhân 2 chu kỳ:** toán hạng mở rộng thành 33 bit có dấu theo phép. Chu kỳ 1 tính hai tích riêng `A × B[15:0]` (49 bit) và `A × B[32:16]` (48 bit thấp) rồi chốt vào thanh ghi. Chu kỳ 2 cộng thành tích 64 bit. Mỗi chu kỳ chỉ có nửa bộ nhân, không cần multicycle path (mục 4.9). EX dừng đúng 1 chu kỳ.
- **Chia 1 bit/chu kỳ:** restoring trên giá trị tuyệt đối, 1 chu kỳ nạp, 32 bước, chu kỳ cuối sửa dấu. EX dừng 33 chu kỳ. Chia cho 0 và tràn `-2^31 / -1` cho đúng kết quả đặc tả mà không cần nhánh riêng: thương không dấu toàn bit 1 và không đổi dấu khi số chia bằng 0, `|-2^31| / 1 = 2^31` đổi dấu vẫn là `-2^31`, số dư 0.
- **Giao tiếp:** `req_i = ex_valid & ex_md & ~ex_trap & ~wb_redirect`. Phép bắt đầu khi `req_i & ~busy & ~hold_i`, với `hold_i = wb_wait` vì lúc WB còn chờ phản hồi thì toán hạng forward từ load chưa có. `req_i = 0` (lệnh bị huỷ, nhận trap hay bị ngắt) đưa khối về rảnh. Khối rảnh lại sau chu kỳ `done & go`.
- **Đã loại:** nhân 33 × 33 trong một chu kỳ (đường dài gấp đôi, phải khai multicycle path trong SDC, trái mục 4.9), chia radix-4 (nhanh gấp đôi nhưng tốn bảng chọn thương, không cần ở 50 MHz), bộ chia không khôi phục (tiết kiệm một mux nhưng cần bước sửa số dư cuối).
- **Theo dõi timing:** chu kỳ 1 của phép nhân là forward mux → bộ nhân 33 × 17 → flop. Giá trị tuyệt đối của phép chia là forward mux → bộ trừ 32 bit → flop. Chu kỳ 2 là bộ cộng 64 bit → mux `ex_result` → `wb_result_q`. Cần xem lại khi tổng hợp core.

### D-032. Ngắt khi M-unit đang chạy

- `ex_req_wait_q` (D-024) chỉ chốt wait state của bus (`ex_bus_wait`), không chốt thời gian chờ M-unit. Phép chia đang chạy vẫn bị ngắt: lệnh nhận trap với mepc = PC của nó, phép bị bỏ và chạy lại từ đầu sau MRET. Độ trễ ngắt không cộng thêm 33 chu kỳ.
- Bản đầu của P7 dùng `ex_wait` cho `ex_req_wait_q` nên ngắt phải chờ phép chia xong. Test `muldiv` vẫn đạt (chỉ chậm hơn), lỗi được phát hiện khi đếm mepc của các lần ngắt trong vết.
- Hệ quả: ngắt lặp lại nhanh hơn khoảng 34 chu kỳ cộng thời gian của trình xử lý sẽ làm phép chia không bao giờ xong. Ngắt của SoC (Timer, UART, GPIO) chậm hơn nhiều nên chấp nhận.
- `ex_hold_q` không chốt lệnh ở chu kỳ `wb_redirect`. Trong thiết kế hiện tại `pipe_stall` luôn bằng 0 ở chu kỳ đó, điều kiện thêm vào để bất biến này không phụ thuộc vào việc `md_req` có chặn `wb_redirect` hay không.
- Xoá cờ `wb_unsup_q` và waiver `unused_p7`. Waiver duy nhất còn lại trong `rtl/core` là `unused_ok` của regfile (bit enable của x0, có từ P2).

### D-033. Bằng chứng kiểm tra P7

- `make isa-core` 472/472 (thêm rv32um 8 test × 4 chế độ, nominal có strict timing). `make fw-core` 96/96 (6 test × 4 cấu hình × 4 chế độ). `make unit-core` 9/9 (thêm `tb_rv32_muldiv`). `make lint-core` 0 warning.
- tb_core strict timing cộng 1 chu kỳ cho MUL* và 33 cho DIV/REM, suy ra từ mã lệnh. Lệnh M bị ngắt giữa chừng không xét.
- `tb_rv32_muldiv`: 144 cặp toán hạng biên × 8 phép, 20000 phép ngẫu nhiên có thiên vị, số chu kỳ chính xác (2 và 34), `hold_i`, `go_i = 0` giữ kết quả, phép bị huỷ giữa chừng. Mô hình tham chiếu dùng phép nhân/chia 64 bit của Verilog.
- Cấy 11 lỗi: MULHSU coi rs2 có dấu, chia cho 0 đổi dấu thương, dấu số dư theo số chia, dịch tích riêng sai, 31 bước chia, không về rảnh khi bị huỷ, bắt đầu khi WB chờ load, lệnh M bị ngắt vẫn giữ M-unit, `go_i` bị bỏ qua, không chọn kết quả M, thiếu dừng của phép nhân. Test hệ thống bắt 8 lỗi. Hai lỗi về `go_i` và về huỷ được `tb_rv32_muldiv` bắt (trong core `go_i = 0` không xảy ra khi khối đã xong). Lỗi "lệnh M bị ngắt vẫn giữ M-unit" chỉ làm ngắt chờ phép chia xong, kết quả vẫn đúng, nên không test nào bắt được (giống lỗi đã gặp ở D-032).

### D-035. mtval của EBREAK = PC

- **Lựa chọn:** EBREAK ghi mtval = PC của chính lệnh EBREAK (`wb_pc_q`), giống instruction access fault. Thay quy ước "EBREAK = 0" của D-022.
- **Lý do:** Đặc tả privileged cho phép cả 0 lẫn PC. Spike và Sail ghi PC, trap handler của riscv-arch-test 3.10.0 mặc định cũng coi tval của breakpoint là địa chỉ trong vùng code. Với mtval = 0, test `privilege/ebreak` lệch signature và handler bỏ dở test (docs/riscof.md). Phần cứng chỉ thêm một nhãn vào nhánh chọn PC sẵn có của mux mtval.
- **Đã loại:** giữ mtval = 0 và xoá bit breakpoint trong `SET_REL_TVAL_MSK` của `model_test.h`. Test chạy hết nhưng vẫn lệch một word so với Spike, không có bằng chứng tuân thủ sạch.
- Kiểm tra: `trap.S` test 31 so mtval với địa chỉ lệnh EBREAK. Không unit test nào kiểm mtval vì mux nằm trong `rv32_core`.

---

## PPA – Timing và clock gating (flow nhà)

### D-036. Không tối ưu đường quyết định ở EX khi chưa có số của Genus

- **Bối cảnh:** Timing ước lượng bằng Yosys và OpenSTA với Nangate45 (`docs/timing_core.md`). Đường găng ENABLE_M=0 đi từ so sánh nhánh và bit thấp của ALU qua `ex_exc`, `ex_trap`, `d_req_valid_o`, `pipe_stall` tới `ex_go`, rồi tới enable của mọi thanh ghi pipeline. Đường găng ENABLE_M=1 nằm ở bộ nhân và đường regfile → ALU → `wb_result_q`.
- **Đã thử:** bộ cộng 2 bit riêng cho bit thấp địa chỉ (`ex_addr_lo`), và `d_req_valid_o`, `md_req`, `ex_redirect` dùng ngoại lệ theo nhóm lệnh (`ex_ok`) thay cho `ex_trap`. Bản thử tương đương hình thức với RTL gốc (trừ 2 bit vào `rv32_lsu_align` khi lệnh không phải ADD, không ai dùng), pass đủ regression, CPI không đổi.
- **Lựa chọn:** không giữ thay đổi RTL, chỉ giữ số liệu.
- **Lý do:** ENABLE_M=0 nhanh hơn khoảng 5%, ENABLE_M=1 không cải thiện. Mức dao động của abc khi sửa RTL nhỏ là khoảng ±3%, nên lợi ích chưa rõ. Đề bài chỉ cần 50 MHz và core đã dư nhiều lần. Giữ RTL đơn giản hơn, ít rủi ro hơn cho phần tích hợp. Quyết định tự chọn theo hướng an toàn khi nhóm chưa xem.
- **Đã loại:** giữ bản thử chỉ vì M0 nhanh hơn một chút (thêm điều kiện dựa vào tính chất của decoder, người sửa decoder sau này phải nhớ). Sửa đường bộ nhân (đã chia 2 chu kỳ theo D-031).
- Patch bản thử: `syn/run_timing/opt2_decision_path.patch` trên máy của Nhân (bị ignore). Áp lại nếu Genus báo vi phạm setup trên đường này.

### D-037. Nửa cao của `mcycle` và `minstret` có enable riêng

- **Bối cảnh:** 99,8% flop của core đã có enable theo Yosys. Nhưng nửa cao 32 bit của hai bộ đếm dùng chung enable với nửa thấp, tức bật mọi chu kỳ (`mcycle`) hoặc mỗi lệnh (`minstret`), nên Genus gate clock cũng không chặn được gì.
- **Lựa chọn:** mỗi nửa 32 bit có always riêng. Nửa cao chỉ nạp khi bị ghi hoặc khi nửa thấp toàn bit 1 và đang tăng. Thứ tự ưu tiên giữ như cũ: ghi nửa nào thì nửa đó lấy giá trị ghi, nửa kia giữ nguyên, không tăng.
- **Lý do:** khoảng 58 flop ít nhận clock hơn mỗi chu kỳ (ước lượng với CPI 1,2), không đổi giá trị đọc ra, không đổi timing (lệch trong mức nhiễu).
- **Đã loại:** chặn hẳn bộ đếm khi không đọc (sai đặc tả, có `mcountinhibit` mới được). Tách thành thanh ghi `_lo_q`, `_hi_q` riêng (Genus thấy cùng cấu trúc, chỉ thêm tên mới khi xem sóng). Chặn `wb_instr_q` khi lệnh không cần (`tb_core` dùng `wb_instr_q` để in vết lệnh và nhận ra lệnh M, MRET, FENCE.I, nên phải sửa cả testbench, để nhóm xem lại).
- **Kiểm tra:** tương đương hình thức với bộ đếm cũ (Yosys `equiv_induct`, 0 điểm không chứng minh được, cả ENABLE_M=0 và 1). Regression đủ, số chu kỳ bench không đổi. `trap.S` test 83, 84 kiểm nhớ sang nửa cao của `mcycle`.

### D-038. Forward MIE và mie cho kiểm tra ngắt, WFI không ngủ khi đã có ngắt chờ

- **Bối cảnh:** EVA-01 (`fw/bench/accel_bench.c`) chờ ngắt bằng vòng không race: `csrc MIE`, kiểm cờ, `wfi`, `csrs MIE`, lặp lại. Vòng này không bao giờ nhận ngắt. Nguyên nhân là `wb_irq_block` của D-024: lệnh ngay sau `csrs mstatus` (ở đây là `csrc mstatus` của vòng sau) không được ngắt, nên MIE chỉ bằng 1 trong đúng một lệnh không ngắt được. WFI không ngủ mãi: khi ngắt đã chờ, `sleep_q` bật 1 chu kỳ rồi tắt (ưu tiên của `wb_wfi` cao hơn điều kiện thức), nên chỉ ngủ thừa 1 chu kỳ. Đặc tả Privileged cho phép nhận ngắt trễ, nhưng phần mềm (vòng chờ trên, `local_irq_enable` rồi tắt ngay của hệ điều hành) cần cửa sổ một lệnh này.
- **Lựa chọn:** bỏ `wb_irq_block`. `rv32_csr` nhận `fwd_i` (WB giữ lệnh ghi CSR, chỉ từ flop) và tính 4 bit MIE, MSIE, MTIE, MEIE sau lần ghi đó từ `op_i` và `wdata_i` (là `wb_result_q`), không đi qua mux `rdata_o`. `irq_take_o` và `irq_cause_o` dùng các bit này. `irq_pending_o` (thức WFI) vẫn dùng thanh ghi. WFI chỉ đặt `sleep_q` khi `(mip & mie) == 0`.
- **Kết quả:** tắt ngắt vẫn có hiệu lực ngay lệnh kế (như cũ). Bật ngắt cũng có hiệu lực ngay lệnh kế. `csrsi mstatus` ngay trước WFI với ngắt chờ sẵn thì trap ở WFI (mepc = PC(WFI)). MIE=0 và ngắt chờ sẵn thì WFI đi tiếp như NOP, 0 chu kỳ ngủ. Đúng cho cả `ENABLE_WFI_SLEEP=0` và 1.
- **Lý do:** lệnh CSR ghi ở WB thì sẽ hoàn thành (lệnh CSR lỗi đã bị gắn cờ ở EX, khi đó WB chuyển hướng và huỷ EX), nên dùng trước giá trị mới là an toàn. Đường thêm chỉ là vài cổng bắt đầu từ flop của WB (`wb_result_q`, `wb_instr_q`). `make sta-core-nangate` sau khi sửa (Yosys 0.33, OpenSTA 2.3.1, `-D 2000`, đo lại trong WSL ngày 27/10 ra cùng số): M0 2,856 ns (trước 2,855), M1 3,113 ns (trước 3,007, +3,5%, sát mức nhiễu ±3% của abc). Diện tích M0 16 929 µm² (trước 16 995), M1 27 876 µm² (trước 28 463) (`docs/timing_core.md`). Đường găng M1 là `ex_hold_q` → `u_muldiv.cnt_q`, không bắt đầu từ logic forward.
- **Đã loại:** giữ `wb_irq_block` và bắt firmware chèn `nop` sau `csrs mstatus` (dễ quên, phần mềm chuẩn không làm). Chốt quyết định ngắt vào flop (như D-024 đã loại).
- **Kiểm tra:** `fw/tests/asm/wfi_pending.S` (FAIL trước khi sửa: W=1 ngủ 1 chu kỳ ở test 2, W=0 và W=1 sai mepc ở test 8), `tb_rv32_csr` thêm kiểm tra forward (xoá, bật MIE, ghi mie, cause theo mie mới, không forward từ CSR khác). `irq.S` vẫn kiểm lệnh sau `csrci mstatus` không bị ngắt. Bỏ `nop` né lỗi trong `accel_bench.c`.

---

## P8 – Bootloader UART

### D-039. Bootloader UART trong boot ROM, chọn bằng chân strap `gpio_i[0]`

- **Bối cảnh:** Boot ROM 1 KB (256 word) ở 0x0001_0000 là reset vector. Chỉ cổng lấy lệnh đọc được ROM. IMEM ghi được từ cổng dữ liệu, nên không cần sửa `soc_top`. Hằng số trong ROM giống nhau cho mọi mô phỏng, mà `tb_soc` (không được sửa) chạy mọi test qua ROM với timeout 200 000 chu kỳ. Icarus chạy `soc_top` khoảng 5 000 chu kỳ mỗi giây (đo lại 27/10, `docs/bench_soc.md`), nên timeout 100 000 chu kỳ đã cộng khoảng 20 s vào mỗi test của `fw-soc`.
- **Lựa chọn:**
  - Assembly thuần, chỉ dùng thanh ghi, không stack, không DMEM. 127 / 256 word.
  - Chân strap `gpio_i[0]`: 0 thì nhảy ngay về 0x0 như ROM base, 1 thì boot qua UART với timeout 1 s (50 000 000 chu kỳ ở 50 MHz, đo bằng `mcycle`). `mtvec` trỏ về nhánh nhảy IMEM trong lúc chạy, nên lỗi bus khi đọc GPIO (build không có GPIO như `tb_core_bus`) cũng nhảy về IMEM. Trước khi nhảy xoá `mtvec` và các thanh ghi đã dùng.
  - Giao thức MAGIC (lặp tới khi có READY), SYNC, addr, len, data, CRC-32. ACK/NAK sau header và sau CRC. Header sai thì NAK trước khi ghi IMEM. Sau NAK chờ SYNC lại, không timeout.
  - Tham số build (`BOOT_CLK_HZ`, `BOOT_BAUD`, `BOOT_TIMEOUT`) qua `make boot-gen`, IMEM lấy từ `soc_map.vh`. `make sim-boot` dùng thêm một ROM mô phỏng từ cùng mã nguồn (timeout 20 000 chu kỳ, BAUDDIV 1), include trước `rtl/mem` qua `-I`. ROM đã commit vẫn chạy test strap 0 và một lần nạp ở 115200 baud.
- **Lý do:** strap giữ test cũ nhanh như trước (thêm khoảng 35 chu kỳ) mà silicon vẫn có cửa sổ chờ đủ dài cho người nhấn reset. Giống chân BOOT0 của nhiều vi điều khiển. Cực tính 0 = chạy IMEM là bắt buộc, vì `tb_soc` có `PAD_IN[0] = 0` và `tb_core_bus` đọc GPIO bị lỗi bus. CRC-32 bắt lỗi tốt hơn tổng byte, chỉ tốn 9 lệnh và khớp `zlib.crc32` ở phía PC. NAK ngay sau header để PC không gửi cả gói vô ích. MAGIC lặp lại có khoảng nghỉ để bộ thu UART đồng bộ lại nếu reset nhả giữa một byte.
- **Đã loại:**
  - Timeout ngắn cố định trong ROM (100 000 chu kỳ = 2 ms): `fw-soc` chậm khoảng 20 s mỗi test, còn trên board thì cửa sổ quá ngắn cho người dùng.
  - `` `ifdef `` trong `boot_rom_init.vh` để mô phỏng dùng timeout khác: mô phỏng khác silicon và phá định dạng file.
  - Sửa `tb_soc` để gửi gì đó hoặc tăng timeout: ngoài phạm vi được sửa.
  - Đọc `.data`/`.rodata` từ ROM: cổng dữ liệu không đọc được ROM, nên mọi hằng số dùng `li`.
  - Cho phép nạp vào DMEM: đề bài yêu cầu NAK mọi địa chỉ ngoài IMEM. Chương trình có `.data` trong DMEM cần bản sau.
- **Kiểm tra:** `make sim-boot` 6 test PASS (nạp, CRC sai, 4 kiểu địa chỉ sai, timeout, strap 0, nạp ở baud thật). Cấy lỗi bỏ kiểm tra addr + len thì `badaddr` FAIL. Với ROM mới: `lint-core`, `unit-core`, `fw-core`, `isa-core`, `fw-soc` 127/127, `fw-bus` 124/124, `bench-soc`, `lint-soc`, `lint-bus` PASS. `unit-bus` FAIL ở `tb_imem_port` vì testbench này so với nội dung ROM base, cần Phát sửa (xem `docs/boot.md` mục 8).

### D-040. Bootloader nạp cả DMEM, chương trình nhiều segment

- **Bối cảnh:** D-039 chỉ cho ghi IMEM, nên chương trình C có `.rodata`, `.data` trong DMEM (theo `fw/common/link.ld`) không nạp được. Yêu cầu mới: cho ghi cả DMEM.
- **Lựa chọn:**
  - Header thêm trường entry (4 byte, có trong CRC). `0xFFFF_FFFF` nghĩa là còn segment sau, bootloader ACK rồi chờ SYNC kế. Giá trị khác là gói cuối, phải chia hết cho 4 và nằm trong IMEM, sau ACK thì nhảy tới đó.
  - Mỗi segment phải nằm trọn trong IMEM hoặc trọn trong DMEM (`SOC_DMEM_BASE`, `SOC_DMEM_SIZE` từ `soc_map.vh`, kiểm cả trong `gen_boot_rom.py`). Mọi địa chỉ khác và đoạn vượt cuối vùng bị NAK trước khi ghi.
  - `uart_pack.py` đọc ELF: mỗi section có nội dung là một gói, theo thứ tự địa chỉ, gói cuối mang entry của ELF. File `.bin` vẫn dùng được (một gói, entry = addr).
- **Lý do:** gói cũ chỉ đổi thêm 4 byte nên host model và `uart_pack.py` giữ nguyên cấu trúc. Entry nằm trong header nên được kiểm trước khi ghi, và gói lỗi vẫn không bao giờ được chạy. Không gửi `.bss` vì crt0 đã xoá.
- **Đã loại:**
  - Gói kết thúc riêng (chỉ có entry): thêm một loại gói và một nhánh trong ROM.
  - Gộp section liền nhau thành segment `PT_LOAD`: khoảng trống giữa section (như căn 64 byte của `.tohost`) phải gửi số 0 vô ích.
  - Cho entry nằm trong DMEM: core chỉ lấy lệnh từ IMEM và boot ROM.
- **Kiểm tra:** ROM 143 / 256 word. `make sim-boot` 7 test PASS, thêm `celf` (C, 4 segment) và 4 kiểu NAK mới trong `badaddr`.

### D-041. Dự đoán nhánh bằng BTB 8 entry, đề xuất bật cho bản nộp

- **Bối cảnh:** mỗi lệnh nhảy mất 1 chu kỳ. Cần số liệu cho buổi review 8/11 để quyết có thêm dự đoán nhánh không. Số liệu đầy đủ ở `docs/btb_eval.md`.
- **Lựa chọn:**
  - Tham số `ENABLE_BTB` của `rv32_core`: 0 không đoán, 1 BTB (`rv32_btb`, `BTB_ENTRIES` mặc định 8, là mặc định của `ENABLE_BTB`, chờ review 8/11), 2 đoán tĩnh nhánh lùi nhảy. Mặc định lấy từ macro trong `rv32_defs.vh` để bật được cho `soc_top` bằng `-D`, không sửa `soc_top`.
  - EX vẫn quyết định nhánh và chỉ chuyển hướng khi đoán sai, phạt 1 chu kỳ như cũ. Chỉ đoán nhánh và JAL. BTB dùng tag đầy đủ và bị xoá khi FENCE.I, nên EX chỉ so hướng, không so đích.
  - BTB tra ở IF bằng `if_pc_q`, nên `if_addr_o` vẫn ra từ flop.
- **Lý do:** tham số có giá trị 0 giữ nguyên bản đã kiểm chứng (Yosys chứng minh tương đương với RTL cũ). Đo thật cả hai phương án thay vì chọn theo cảm tính. Kết quả: lợi 7 đến 11 %, BTB 8 entry thêm khoảng 4 400 µm² (Nangate45).
- **Đề xuất cho bản nộp:** bật BTB 8 entry, chốt ở review 8/11 trước khi chạy Genus (STA-03 từ 9/11). Dự đoán nhánh là điểm cộng nhóm đã chọn (`docs/spec/requirements.md`). Flow SoC chưa chạy lần nào, nên chốt trước STA-03 thì không tốn thêm vòng flow. BTB 16 entry và phương án tĩnh không dùng (`docs/btb_eval.md` mục 5).
- **Đã loại:**
  - Đoán tĩnh qua flop: lệnh chỉ biết ở EX, cùng chu kỳ EX quyết định nhánh, nên không lợi chu kỳ nào. Bản tĩnh có lợi (`ENABLE_BTB=2`) phải đưa đích tổ hợp ra `if_addr_o`, tạo đường IMEM → IMEM. Giữ lại chỉ để so sánh.
  - Tag rút gọn để giảm diện tích: hai PC cùng tag rút gọn sẽ trúng nhầm, EX phải so cả đích 30 bit và kiểm loại lệnh, thêm logic trên đường găng.
  - Đoán JALR, RAS: để sau nếu nhóm bật dự đoán.
- **Kiểm tra:** `tb_rv32_btb` so với mô hình (8 và 16 entry, cấy lỗi thì FAIL). Toàn bộ lint, unit, isa, arch, fw-core, fw-soc, fw-bus, sim-boot PASS với `BTB=0`, 1 và 2. Bảng ở `docs/btb_eval.md` mục 7.

## Flow ở trường

### D-042. Sign-off core trên server: LEC và GLS

- **Bối cảnh:** lần chạy đầu `make synth-core`, `make lec-core`, `make gls-core` trên server ngày 30/10. Server không có git, nên các sửa ở đó được làm lại trong repo. Chi tiết ở `docs/genus_core.md` mục 6 và 7.
- **Genus giữ mọi flop** (`syn/scripts/synth_core.tcl`, ngay trước `syn_generic`): tắt `optimize_merge_flops`, `optimize_merge_latches`, `optimize_constant_0_flops`, `optimize_constant_1_flops`, `delete_unloaded_seqs`. Mỗi lệnh bọc trong `catch` vì tên attribute có thể khác giữa các bản Genus. Lý do: Genus gộp flop trùng và bỏ flop hằng, nên key point của LEC không khớp 1:1 với RTL.
- **Conformal** (`lec/core_rtl2gate.do`):
  - Conformal 24.1 báo lỗi với `-incdir` trong `read design`. Thay bằng `add search path rtl/core -design -golden` đặt trước `read design -golden`.
  - Thêm các flatten option `-seq_constant`, `-seq_constant_x_to 0`, `-nodff_to_dlat_zero`, `-nodff_to_dlat_feedback`, `-hier_seq_merge`, cùng `-gated_clock` đã có.
  - Không dùng `set analyze option -auto` vì cần license Conformal_Ultra, server không có.
- **Bỏ `.note.gnu.build-id`** trong `fw/common/link_isa.ld` và `fw/boot/boot.ld` bằng `/DISCARD/`. riscv gcc của Vitis trên server tự gắn section này. Linker script không có chỗ cho nó, nên linker đặt nó ở địa chỉ 0, trước `_start`. File hex khi đó bắt đầu bằng `00000004 00000014 00000003 00554e47` thay vì lệnh `j`, core chạy từ rác và mọi bài GLS đều timeout. gcc ở nhà không gắn build-id, nên hex ở nhà không đổi (đã so md5).
- **Hai sửa trong `scripts/gls_core.sh`:**
  - Mảng `timing` rỗng khi có SDF. Bash 4.2 trên server với `set -u` báo unbound variable ở `"${timing[@]}"`, nên đổi thành `${timing[@]+"${timing[@]}"}`.
  - File `.tohost` được đọc sau `cd "$OUT"`, nên đường dẫn tương đối bị sai. Đổi thành `$REPO/$HEX_DIR`.
- **Kết quả:**
  - LEC (Conformal 24.1, không Ultra): 2199 Equivalent, 0 Non-equivalent, 68 Abort. Các điểm abort là DFF thuộc khối nhân và chia 32×32, không chứng minh được khi thiếu analyze datapath của Ultra. Mapping đủ: 2163 DFF ở golden bằng ở revised, cộng 58 latch ICG unreachable. Chạy khoảng 53 phút.
  - GLS (Xcelium 24.03): 49/49 PASS (rv32ui và rv32um) trên netlist Genus kèm SDF, clock 20 ns. GLS kiểm chức năng của khối nhân và chia mà LEC để abort.
- **Đã loại:** sửa riêng file trên server rồi chép tay về (dễ lệch với repo). Bật `analyze datapath` (không có license).

---

## Tài liệu

### D-034. Sơ đồ vi kiến trúc sinh bằng script

- **Lựa chọn:** `docs/figures/core_microarch.svg` sinh từ `docs/figures/core_microarch.py` (Python thuần, toạ độ viết tay). Mô tả hình ở `docs/spec/core.md` mục 4.2. Màu theo loại đường: dữ liệu, forward, chuyển hướng PC, cổng của core, dừng.
- **Lý do:** Không cần cài tool vẽ trên máy nhóm. Sửa khi RTL đổi là sửa vài dòng rồi chạy lại, diff đọc được trong git. SVG hiển thị thẳng trên GitHub và chèn được vào báo cáo.
- **Đã loại:** draw.io (file nguồn XML khó review, phải cài app), vẽ tay trong Inkscape (sửa lại tốn công, SVG xuất ra khó diff).
- Hình chỉ vẽ các khối và đường chính. Tín hiệu chi tiết vẫn lấy từ RTL và mục 4.
