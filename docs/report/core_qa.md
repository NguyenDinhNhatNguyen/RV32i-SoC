# Câu hỏi vấn đáp về core RV32I

Dùng để ôn trước buổi bảo vệ. Mỗi câu trả lời ngắn, kèm quyết định hoặc tài liệu để đọc thêm.
"Dx" là mục trong `docs/core_decisions.md`, "mục x.y" là mục trong `docs/spec/core.md`. Chương báo cáo đầy đủ ở `docs/report/core.md`. D-036, D-037 và `docs/timing_core.md` hiện nằm trên nhánh `feat/nhan-ppa`.

## Pipeline

**1. Vì sao chọn 3 tầng mà không phải 5 tầng?**
SRAM đọc đồng bộ đã chốt lệnh ở ngõ ra, nên ngõ ra IMEM đóng vai trò thanh ghi IF/EX. Gộp ID, EX, MEM vào một tầng cho phạt nhánh chỉ 1 chu kỳ và không cần stall load-use. Ở 50 MHz chu kỳ 20 ns đủ dài cho đường dài nhất. Ước lượng ở nhà cho khoảng 2,5 ns với ENABLE_M=0 (`docs/timing_core.md`). Xem D-014, mục 4.2, 4.3.

**2. Vì sao không có stall load-use?**
Dữ liệu load đi thẳng từ ngõ ra bus qua khối căn chỉnh rồi forward về EX trong cùng chu kỳ (mục 4.5). Đổi lại đường forward dài hơn, nhưng vẫn dư nhiều so với 20 ns. `+strict_timing` của tb_core chứng minh load liên tiếp và load-use đều 0 bubble (D-017).

**3. Lệnh ở EX lấy từ đâu khi pipeline dừng?**
Chu kỳ đầu tiên dừng, lệnh ở ngõ ra IMEM được chốt vào `ex_instr_hold_q` và EX đọc thanh ghi giữ cho tới hết dừng. `if_pc_q` không đổi nên khi hết dừng IMEM đang đọc đúng lệnh kế tiếp (D-014, mục 4.3).

**4. Phạt nhánh bao nhiêu chu kỳ? Có dự đoán nhánh không?**
Đoán luôn không nhảy. Nhảy thật mất 1 chu kỳ, kể cả nhảy tới PC+4, vì không so sánh đích để giữ đường găng ngắn. Trap, MRET, FENCE.I, WFI chuyển hướng từ WB nên mất 2 chu kỳ (D-014, D-023).

**5. Vì sao địa chỉ IMEM lấy từ flop `if_pc_q`?**
Để quyết định nhảy và tín hiệu dừng không đi tổ hợp vào chân địa chỉ SRAM. Địa chỉ ra từ flop thì đường vào macro ngắn và dễ đạt setup của macro (mục 4.3, D-014).

**6. `if_req_o` có phụ thuộc tín hiệu dừng không?**
Không. Nếu phụ thuộc `pipe_stall` thì `d_req_ready_i` sẽ đi tổ hợp tới chân enable IMEM qua sys_bus và APB. `if_req_o` chỉ bằng 0 khi ngủ WFI, và lấy từ flop `sleep_q` (D-014, D-025).

**7. Đường găng nằm ở đâu?**
Theo flow nhà, ENABLE_M=0 có đường găng là so sánh nhánh → `ex_trap` → `d_req_valid_o` → `pipe_stall` → `ex_go` → enable thanh ghi pipeline. ENABLE_M=1 có đường găng ở bộ nhân. Đã thử rút ngắn đường ENABLE_M=0, nhanh hơn khoảng 5%, nhưng không giữ vì chỉ hơn mức nhiễu của abc một chút (D-036, `docs/timing_core.md`). Số của Genus: chờ STA-04.

## ALU, regfile, decoder

**8. Vì sao ALU tính cả địa chỉ và đích nhảy, còn so sánh nhánh thì tách riêng?**
Lệnh nhánh không cần ALU cho việc khác nên dùng chung bộ cộng, tiết kiệm một bộ cộng 32 bit. Bộ so sánh riêng chạy song song với bộ cộng đích, nếu dùng ALU SUB rồi zero-detect thì hai việc nối tiếp nhau (D-007).

**9. Vì sao regfile làm bằng flop mà không dùng SRAM?**
Cần 2 cổng đọc và 1 cổng ghi trong cùng chu kỳ, macro SRAM của môn chỉ có 1 cổng đọc/ghi (`docs/macro_notes.md`). Flop có reset xác định cho GLS và có enable riêng từng thanh ghi để Genus gate clock theo nhóm. Không làm bypass bên trong vì mạng forward WB → EX đã lo (D-011).

**10. Decoder xử lý lệnh illegal thế nào?**
Mọi cờ có tác dụng phụ bị ép về 0 khi `illegal_o=1`, nên core chỉ cần xét một tín hiệu. Decoder kiểm opcode, funct3, funct7, các mã SYSTEM, lệnh M khi ENABLE_M=0. Riêng CSR không tồn tại hoặc ghi vào CSR chỉ đọc do `rv32_csr` kiểm ở EX (D-008, D-009, D-021).

## Ngoại lệ, ngắt, CSR

**11. Ngoại lệ chính xác được bảo đảm thế nào?**
Ngoại lệ gắn cờ ở EX, trap thực hiện ở WB. Trong chu kỳ WB chuyển hướng, `d_req_valid_o` của lệnh ở EX bị chặn tổ hợp, lệnh ở EX và lệnh đang lấy bị huỷ. Vì vậy không lệnh nào sau lệnh trap ghi được bộ nhớ hay regfile (mục 4.8, D-023).

**12. Chặn yêu cầu bus như vậy có phạm luật bus 1 (giữ yêu cầu khi `ready=0`) không?**
Không. `wb_redirect` chỉ xảy ra ở chu kỳ đầu lệnh ở WB hoặc chu kỳ có phản hồi của chính nó. Trước đó yêu cầu của EX đã bị chặn bởi `wb_wait`, nên chưa có yêu cầu nào đang ở wait state khi bị huỷ (D-023).

**13. Thứ tự ưu tiên ngoại lệ là gì?**
Theo đặc tả Privileged: instruction access fault > illegal > EBREAK > ECALL > nhảy lệch > load lệch > store lệch (D-016). Lỗi bus của load hoặc store thành access fault ở WB (mục 4.8).

**14. Ngắt được nhận ở tầng nào?**
Ở EX. Lệnh hợp lệ ở EX bị đánh dấu "bị ngắt": không thực thi, không phát yêu cầu bus, tới WB thì nhận trap với mepc = PC của nó. Ưu tiên MEI > MSI > MTI. Mã ngắt được chốt khi lệnh rời EX vì đường ngắt có thể hạ trước khi lệnh tới WB (mục 4.8, D-024).

**15. Vì sao không nhận ngắt khi WB đang ghi mstatus hoặc mie?**
EX đọc CSR từ flop nên ở chu kỳ đó còn thấy giá trị cũ. Nếu không chặn thì lệnh ngay sau `csrci mstatus, MIE` vẫn có thể bị ngắt (D-024).

**16. Lệnh đang chờ `ready` có bị ngắt không?**
Không. Luật bus 1 bắt master giữ nguyên yêu cầu đã hiện ra, nên lệnh đó phải hoàn thành, ngắt được nhận ở lệnh sau (`ex_req_wait_q`, D-024). Nhưng phép chia đang chạy thì vẫn bị ngắt và chạy lại sau MRET, để độ trễ ngắt không cộng thêm 33 chu kỳ (D-032).

**17. Vì sao lệnh CSR thực thi ở WB?**
Đọc CSR ở EX thì lệnh CSR đang ghi ở WB cùng chu kỳ cần bypass riêng, và bộ đếm đổi mỗi chu kỳ. Thực thi ở WB thì giá trị cũ đi vào `wb_rd_data` và được forward như kết quả ALU (mục 4.7, D-021).

**18. mtval của EBREAK là gì, vì sao?**
PC của lệnh EBREAK. Đặc tả cho cả 0 lẫn PC. Spike ghi PC, nên khi ghi 0 thì test `privilege/ebreak` của riscv-arch-test lệch signature (D-035, `docs/riscof.md`).

**19. Bộ đếm `mcycle`, `minstret` làm thế nào, và có gì liên quan tới clock gating?**
64 bit, ghi nửa nào thì thay cho lần tăng trong chu kỳ đó (D-026). Nửa cao có enable riêng, chỉ nạp khi bị ghi hoặc nửa thấp tràn. Nhờ vậy Genus gate được clock của 64 flop nửa cao gần như mọi chu kỳ (D-037).

## WFI và công suất

**20. WFI làm gì khi `ENABLE_WFI_SLEEP=1`?**
WFI ở WB chuyển hướng tới PC+4 và đặt `sleep_q`. Khi ngủ `if_req_o=0`, mọi flop pipeline và regfile giữ nguyên nhờ tắt enable để Genus gate clock. `mcycle` và `mtime` vẫn chạy (mục 4.11, D-025).

**21. Core thức dậy khi nào? Nếu MIE=0 thì sao?**
Thức khi `(mip & mie) != 0`, không xét mstatus.MIE, đúng đặc tả. MIE=1 thì lệnh PC+4 bị ngắt với mepc = PC(WFI)+4. MIE=0 thì chạy tiếp lệnh sau WFI (D-025).

**22. Có số liệu nào cho thấy WFI có ích?**
Test `wfi` ở chế độ nominal: với W1 core ngủ 801 trên 1003 chu kỳ và chỉ chạy 177 lệnh. Với W0 (chờ bằng vòng lặp) chạy 625 lệnh trong 954 chu kỳ (`docs/riscv-tests-status.md`). Công suất polling so với WFI: chờ STA-04.

## RV32M

**23. Vì sao nhân 2 chu kỳ mà không 1 chu kỳ?**
Nhân 33 × 33 trong một chu kỳ dài gấp đôi và phải khai multicycle path trong SDC, trái mục 4.9. Chia thành hai tích riêng 33 × 17, chốt vào thanh ghi, chu kỳ sau cộng lại. Mỗi chu kỳ chỉ có nửa bộ nhân (D-031).

**24. Bộ chia xử lý chia cho 0 và tràn thế nào?**
Restoring 1 bit mỗi chu kỳ trên giá trị tuyệt đối. Chia cho 0 cho thương toàn bit 1 và không đổi dấu. `-2^31 / -1` cho `|-2^31| / 1 = 2^31`, đổi dấu vẫn là `-2^31`, số dư 0. Đúng đặc tả mà không cần nhánh riêng (D-031, mục 4.9).

## Bus

**25. Vì sao dùng bus valid/ready, và luật nào quan trọng nhất với core?**
Valid/ready cho slave chèn wait state (SB/SH vào SRAM, APB) mà master không cần biết trước (mục 5.1). Luật 5 cấm `req_valid` phụ thuộc tổ hợp vào `req_ready`, để không có vòng tổ hợp qua bus. `d_req_valid_o` chỉ phụ thuộc `d_rsp_valid_i` (luật 3, phát yêu cầu mới ngay chu kỳ nhận phản hồi) và `d_rsp_err_i` (D-015, D-023).

**26. Dữ liệu ghi byte và half được đặt vào làn nào?**
Lặp ra mọi làn (`{4{rs2[7:0]}}`, `{2{rs2[15:0]}}`) thay vì dịch. Làn được `be` chọn luôn đúng, không cần bộ dịch (D-015).

## Kiểm chứng

**27. Kiểm chứng core gồm những gì?**
Unit test 9/9, test assembly 96/96 (6 bài × 4 cấu hình × 4 chế độ), riscv-tests 472/472 lần chạy, riscv-arch-test so với Spike 55/55 và 63/63, cộng cấy lỗi để kiểm độ nhạy (D-033, `docs/riscv-tests-status.md`, `docs/riscof.md`).

**28. Chế độ stall ngẫu nhiên để làm gì?**
Ba bộ tham số (stall1..3) cho bus từ chối lấy lệnh, `d_req_ready=0` và trễ phản hồi ngẫu nhiên. Lỗi thanh ghi giữ lệnh và chuyển hướng khi đang dừng chỉ lộ ở chế độ này, không lộ ở chế độ nominal (D-019, `Makefile` `CORE_PLUS_stall*`).

**29. Làm sao biết testbench đủ mạnh?**
Cấy lỗi vào bản sao RTL rồi chạy lại. Tổng 66 lỗi qua 4 giai đoạn, bắt được mọi lỗi không tương đương trừ 1. Lỗi đó (lệnh M bị ngắt vẫn giữ M-unit) chỉ làm ngắt chờ phép chia xong, kết quả vẫn đúng (D-012, D-019, D-030, D-033).

**30. Vì sao loại 3 test của riscv-tests và 41 test `pmp32`?**
`ma_data` cần load/store lệch chạy đúng, core chọn trap theo mục 4.1. `breakpoint` cần debug trigger, `pmpaddr` và `pmp32` cần PMP và S/U-mode, core chỉ có M-mode (`docs/riscv-tests-status.md`, `docs/riscof.md`).
