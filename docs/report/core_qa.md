# Câu hỏi vấn đáp về core RV32I

Dùng để ôn trước buổi bảo vệ. Mỗi câu trả lời ngắn, kèm quyết định hoặc tài liệu để đọc thêm.
"Dx" là mục trong `docs/core_decisions.md`, "mục x.y" là mục trong `docs/spec/core.md`. Chương báo cáo đầy đủ ở `docs/report/core.md`. D-041 và `docs/btb_eval.md` đã merge vào main.

## Pipeline

**1. Vì sao chọn 3 tầng mà không phải 5 tầng?**
SRAM đọc đồng bộ đã chốt lệnh ở ngõ ra, nên ngõ ra IMEM đóng vai trò thanh ghi IF/EX. Gộp ID, EX, MEM vào một tầng cho phạt nhánh chỉ 1 chu kỳ và không cần stall load-use. Ở 50 MHz chu kỳ 20 ns đủ dài cho đường dài nhất. Ước lượng ở nhà cho khoảng 2,5 đến 2,9 ns với ENABLE_M=0 (`docs/timing_core.md`, `docs/btb_eval.md`). Xem D-014, mục 4.2, 4.3.

**2. Vì sao không có stall load-use?**
Dữ liệu load đi thẳng từ ngõ ra bus qua khối căn chỉnh rồi forward về EX trong cùng chu kỳ (mục 4.5). Đổi lại đường forward dài hơn, nhưng vẫn dư nhiều so với 20 ns. `+strict_timing` của tb_core chứng minh load liên tiếp và load-use đều 0 bubble (D-017).

**3. Lệnh ở EX lấy từ đâu khi pipeline dừng?**
Chu kỳ đầu tiên dừng, lệnh ở ngõ ra IMEM được chốt vào `ex_instr_hold_q` và EX đọc thanh ghi giữ cho tới hết dừng. `if_pc_q` không đổi nên khi hết dừng IMEM đang đọc đúng lệnh kế tiếp (D-014, mục 4.3).

**4. Phạt nhánh bao nhiêu chu kỳ? Có dự đoán nhánh không?**
RTL trên main mặc định dùng BTB 8 entry (`ENABLE_BTB=1`), với `ENABLE_BTB=0` thì đoán luôn không nhảy. BTB và đoán tĩnh đã thử, đề xuất giữ BTB 8 entry cho bản nộp, xem câu 33 đến 37. Nhảy thật mất 1 chu kỳ, kể cả nhảy tới PC+4, vì không so sánh đích để giữ đường găng ngắn. Trap, MRET, FENCE.I, WFI chuyển hướng từ WB nên mất 2 chu kỳ (D-014, D-023).

**5. Vì sao địa chỉ IMEM lấy từ flop `if_pc_q`?**
Để quyết định nhảy và tín hiệu dừng không đi tổ hợp vào chân địa chỉ SRAM. Địa chỉ ra từ flop thì đường vào macro ngắn và dễ đạt setup của macro (mục 4.3, D-014).

**6. `if_req_o` có phụ thuộc tín hiệu dừng không?**
Không. Nếu phụ thuộc `pipe_stall` thì `d_req_ready_i` sẽ đi tổ hợp tới chân enable IMEM qua sys_bus và APB. `if_req_o` chỉ bằng 0 khi ngủ WFI, và lấy từ flop `sleep_q` (D-014, D-025).

**7. Đường găng nằm ở đâu?**
Theo flow nhà, ENABLE_M=0 có đường găng là so sánh nhánh → `ex_trap` → `d_req_valid_o` → `pipe_stall` → `ex_go` → enable thanh ghi pipeline. ENABLE_M=1 có đường găng ở bộ nhân. Đã thử rút ngắn đường ENABLE_M=0, nhanh hơn khoảng 5%, nhưng không giữ vì chỉ hơn mức nhiễu của abc một chút (D-036, `docs/timing_core.md`). Genus `soc_top` ngày 29/10 (GPDK45) cho đường găng 17,57 ns từ CLK của macro IMEM qua ALU tới `if_pc_q[31]`, slack +2,18 ns ở 20 ns, F_max khoảng 57 MHz (`docs/sta_results.md`). Đây là số khi Genus chỉ cần đạt 20 ns. Lần quét chu kỳ 30–31/10 (`docs/sta_results.md` mục 4) cho F_max sau tổng hợp khoảng 200 MHz: 5 ns đạt, 4 ns thiếu 0,69 ns. Đường găng vẫn từ macro qua so sánh nhánh tới `if_pc_q`, riêng ở 8 ns là bộ nhân `u_muldiv`. Đều là số sau tổng hợp, chưa có delay dây.

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

**15. Khi WB đang ghi mstatus hoặc mie thì kiểm tra ngắt ở EX dùng giá trị nào?**
Giá trị sau lần ghi đó. EX đọc CSR từ flop nên ở chu kỳ đó còn thấy giá trị cũ. Bản đầu chặn hẳn ngắt trong chu kỳ này (D-024). Bản hiện tại forward 4 bit MIE, MSIE, MTIE, MEIE từ WB, nên tắt và bật ngắt đều có hiệu lực ngay lệnh kế (D-038, câu 31).

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
Thức khi `(mip & mie) != 0`, không xét mstatus.MIE, đúng đặc tả. MIE=1 thì lệnh PC+4 bị ngắt với mepc = PC(WFI)+4. MIE=0 thì chạy tiếp lệnh sau WFI (D-025). Nếu ngắt đã chờ sẵn lúc WFI tới WB thì core không ngủ chu kỳ nào (D-038).

**22. Có số liệu nào cho thấy WFI có ích?**
Test `wfi` ở chế độ nominal: với W1 core ngủ 801 trên 1003 chu kỳ và chỉ chạy 177 lệnh. Với W0 (chờ bằng vòng lặp) chạy 625 lệnh trong 954 chu kỳ (`docs/riscv-tests-status.md`). Công suất polling so với WFI: [CHỜ GENUS].

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
Unit test 9/9, test assembly 112/112 (7 bài × 4 cấu hình × 4 chế độ), riscv-tests 472/472 lần chạy, riscv-arch-test so với Spike 55/55 và 63/63, cộng cấy lỗi để kiểm độ nhạy (D-033, `docs/riscv-tests-status.md`, `docs/riscof.md`).

**28. Chế độ stall ngẫu nhiên để làm gì?**
Ba bộ tham số (stall1..3) cho bus từ chối lấy lệnh, `d_req_ready=0` và trễ phản hồi ngẫu nhiên. Lỗi thanh ghi giữ lệnh và chuyển hướng khi đang dừng chỉ lộ ở chế độ này, không lộ ở chế độ nominal (D-019, `Makefile` `CORE_PLUS_stall*`).

**29. Làm sao biết testbench đủ mạnh?**
Cấy lỗi vào bản sao RTL rồi chạy lại. Tổng 66 lỗi qua 4 giai đoạn, bắt được mọi lỗi không tương đương trừ 1. Lỗi đó (lệnh M bị ngắt vẫn giữ M-unit) chỉ làm ngắt chờ phép chia xong, kết quả vẫn đúng (D-012, D-019, D-030, D-033).

**30. Vì sao loại 3 test của riscv-tests và 41 test `pmp32`?**
`ma_data` cần load/store lệch chạy đúng, core chọn trap theo mục 4.1. `breakpoint` cần debug trigger, `pmpaddr` và `pmp32` cần PMP và S/U-mode, core chỉ có M-mode (`docs/riscv-tests-status.md`, `docs/riscof.md`).

## Ngắt và WFI (bổ sung)

**31. Lỗi ngắt nào được tìm ra nhờ `accel_bench`?**
Bản đầu chặn ngắt khi WB đang ghi mstatus. Vòng chờ không race của `accel_bench` (`csrc MIE`, kiểm cờ, `wfi`, `csrs MIE`) vì vậy không bao giờ vào handler: lệnh ngay sau `csrs mstatus` là `csrc mstatus` của vòng sau, và lệnh đó không ngắt được. Bản `irq` treo. Sửa bằng forward MIE và mie từ WB, thêm test `wfi_pending.S` (FAIL trước khi sửa, PASS sau khi sửa) (D-038, báo cáo mục X.4).

**32. Forward MIE có làm chậm core không? Có an toàn không?**
Đường thêm chỉ là vài cổng bắt đầu từ flop của WB (`wb_result_q`, `wb_instr_q`). Flow nhà: ENABLE_M=0 2,856 ns (trước 2,855), ENABLE_M=1 3,113 ns (trước 3,007, sát mức nhiễu ±3%), đường găng vẫn ở bộ nhân. An toàn vì lệnh CSR đã tới WB thì chắc chắn hoàn thành, lệnh CSR lỗi đã bị gắn cờ từ EX (D-038).

## Dự đoán nhánh

**33. Đã thử những phương án dự đoán nhánh nào?**
Tham số `ENABLE_BTB`: 0 không đoán, 1 BTB 8 hoặc 16 entry với bộ đếm 2 bit tra ở IF, 2 đoán tĩnh nhánh lùi và JAL nhảy. Cả ba quyết định nhánh ở EX, đoán sai vẫn chỉ mất 1 chu kỳ (D-041, `docs/btb_eval.md`).

**34. Tại sao không chọn đoán tĩnh, dù nó nhanh nhất ở Dhrystone?**
Lệnh chỉ biết được khi đã ở EX, đúng chu kỳ EX quyết định nhánh. Muốn có lợi thì đích phải đi tổ hợp từ ngõ ra IMEM qua giải mã, bộ cộng về `if_addr_o` (1,89 ns ở flow nhà). Đi qua flop thì kết quả giống hệt core gốc. Đường IMEM → IMEM phá quy tắc "`if_addr_o` ra từ flop" và gắn timing của macro SRAM với logic core (D-041).

**35. BTB lợi bao nhiêu và tốn bao nhiêu?**
BTB 8 entry: CoreMark/MHz rv32im 2,755 → 2,967 (+7,7%), DMIPS/MHz 0,800 → 0,856 (+7,0%) trên `soc_top`, đoán đúng 39,8% → 79,8% ở CoreMark rv32im. Diện tích thêm khoảng 4 400 µm² ở Nangate45 (+15% core có RV32M), khoảng 480 flop. Timing không đổi rõ (`docs/btb_eval.md` mục 3, 4).

**36. Bản nộp có bật BTB không? Vì sao?**
Đề xuất bật BTB 8 entry, chốt ở review 8/11 trước khi chạy Genus (STA-03 từ 9/11). Dự đoán nhánh là điểm cộng nhóm đã chọn, lợi 7 đến 10%, và lần chạy Genus `soc_top` đầu tiên (29/10) đã dùng BTB 8 entry và đạt 20 ns, nên chốt sớm thì không tốn thêm vòng flow. 16 entry tốn gấp đôi để lời thêm 1%, phương án tĩnh tạo đường IMEM → IMEM, nên không dùng (D-041).

**37. Tại sao BTB chỉ cần so hướng ở EX mà không so đích?**
BTB lưu tag đầy đủ, nên trúng nghĩa là đúng lệnh đó. Chỉ nhánh và JAL được đoán, đích của chúng cố định theo PC. FENCE.I xoá hết BTB, nên code bị sửa (bootloader nạp chương trình mới) không bị đoán theo bản cũ (D-041).

## Hiệu năng trên SoC và accelerator

**38. Tại sao SB/SH thêm chu kỳ trên `soc_top`?**
Macro SRAM của GPDK45 không có chân ghi theo byte. `sram_wrap` phải đọc word, sửa byte rồi ghi lại, mất thêm 1 chu kỳ (luật bus 6). Đây là wait state duy nhất của bộ nhớ. Đọc và ghi word không thêm chu kỳ (`docs/bench_soc.md`).

**39. Vì sao Dhrystone chậm 4,9% trên `soc_top` mà CoreMark chỉ 0,1 đến 0,3%?**
Dhrystone có 33 lệnh ghi byte mỗi lần chạy, 31 lệnh ở `strcpy` chép từng byte. 33 × 500 = 16 500 chu kỳ, đúng bằng phần chênh mà module theo dõi đếm được. CoreMark gần như chỉ ghi word. DMIPS/MHz giảm từ 0,839 xuống 0,800 (`docs/bench_soc.md`).

**40. Tại sao speedup của accelerator với rv32im chỉ 1,7 lần mà rv32i tới 25 lần?**
Bản rv32i nhân bằng hàm mềm, khoảng 140 chu kỳ mỗi phép nhân–cộng. Bản rv32im dùng MUL, chỉ còn khoảng 9,5 chu kỳ. Accelerator tốn khoảng 5,6 chu kỳ mỗi phép nhân–cộng, gần hết là phí APB, nên chỉ nhanh hơn 1,69 lần (`docs/bench_soc.md`).

**41. Phí APB lớn cỡ nào? Làm sao giảm?**
Mỗi khối 4 × 4 mất 235 chu kỳ, accelerator chỉ tính 12. Khoảng 95% là chuyển dữ liệu qua APB, riêng đọc 16 word C chiếm 70%. Bỏ hết phí APB thì giới hạn trên khoảng 51 lần. Hướng giảm: đọc nhiều phần tử C mỗi lần đọc, hoặc DMA chép C về DMEM (`docs/bench_soc.md`).

**42. Bản irq chậm hơn poll thì dùng irq làm gì?**
Irq chậm hơn khoảng 37 chu kỳ mỗi khối (vào trap, handler, `mret`, thức sau WFI). Đổi lại core ngủ trong lúc accelerator tính, flop pipeline không nhận clock khi Genus gate clock, và core có thể làm việc khác. Phần lợi công suất: [CHỜ GENUS].

## Bootloader

**43. Bootloader hoạt động thế nào và chọn chế độ ra sao?**
ROM 1 KB ở reset vector. Chân strap `gpio_i[0]` = 0 thì nhảy ngay về IMEM, = 1 thì chờ MAGIC qua UART tối đa 1 s. Mỗi segment là một gói SYNC, addr, len, entry, data, CRC-32, gói cuối mang địa chỉ nhảy. ROM dùng 143 / 256 word (D-039, D-040, `docs/boot.md`).

**44. Bootloader xử lý lỗi thế nào?**
Header sai (ngoài IMEM/DMEM, vượt cuối vùng, lệch, entry sai) thì NAK ngay, chưa ghi bộ nhớ. CRC sai thì NAK sau dữ liệu, gói lỗi không bao giờ được chạy, PC gửi lại từ SYNC. Byte rác trước MAGIC hoặc SYNC bị bỏ qua. Đọc GPIO lỗi bus thì trap về nhánh chạy IMEM (D-039, D-040).

**45. Nạp chương trình mất bao lâu?**
Ở 115200 baud mỗi byte 86,8 µs, mỗi gói thêm 17 byte. `hello` (24 word) mất 9,9 ms, chương trình C 4 segment mất 39 ms, đầy IMEM 16 KB mất 1,42 s. Bootloader xử lý mỗi byte khoảng 100 chu kỳ, nhanh hơn nhiều so với 4 320 chu kỳ của một byte trên dây (`docs/boot.md` mục 6).

## PPA

**46. EPI tính thế nào?**
EPI = P / (f / CPI) = P × CPI / f. P là công suất trung bình khi chạy CoreMark (Genus hoặc Innovus đọc VCD/SAIF), f = 50 MHz, CPI lấy trên `soc_top` (1,158 với rv32im). Ví dụ P = 1 mW cho khoảng 23 pJ/lệnh. Số thật: [CHỜ GENUS].

**47. Vì sao số timing ở nhà chỉ là xu hướng?**
Dùng Nangate45 chứ không phải GPDK45, không đặt cell và đi dây, abc dao động ±3%. Chỉ đổi `abc -fast` thành `abc` đã làm ENABLE_M=0 chậm 10,9% dù RTL không đổi. Số chính thức (F_max, area, GE, power, EPI) chờ Genus và Innovus (`docs/timing_core.md`).
