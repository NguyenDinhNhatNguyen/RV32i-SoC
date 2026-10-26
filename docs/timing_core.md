# Timing ước lượng của rv32_core (flow nhà, Nangate45)

**Các số ở đây chỉ để xem xu hướng.** Thư viện là Nangate45 (thư viện mở, 45 nm, góc typical 1,1 V, 25 °C), không phải GPDK45.
Không có đặt cell và đi dây. Trễ dây lấy theo wire load mặc định của Nangate45, clock lý tưởng.
Số chính thức (tần số, slack) lấy từ Genus và Innovus ở trường.

**Trạng thái:** đã xong việc 1, 2, 3. Quyết định ghi ở `docs/core_decisions.md` (D-036, D-037).

## Cách chạy

```sh
make sta-core-nangate       # rv32_core với ENABLE_M=0 và 1
```

- `scripts/get_nangate45.sh` tải liberty `NangateOpenCellLibrary_typical.lib` từ OpenROAD-flow-scripts vào `syn/run_yosys/lib/`. Thư mục này bị `.gitignore` chặn, không commit file `.lib`.
- `syn/yosys/synth_nangate.tcl`: Yosys 0.33 tổng hợp và map sang cell Nangate45.
- `syn/yosys/sta_nangate.tcl`: OpenSTA đọc netlist, in đường găng và F_max. Kết quả ở `syn/run_yosys/<nhãn>_ng/`.
- Script Genus trong `syn/scripts/` không bị đụng tới.

Cài OpenSTA ở nhà (không cần quyền root): dùng micromamba cài gói `openroad` của kênh `litex-hub`, trong gói có sẵn `sta` (OpenSTA 2.3.1).

```sh
micromamba create -p ~/.local/opt/openroad -c litex-hub -c conda-forge openroad
ln -s ~/.local/opt/openroad/bin/sta ~/.local/bin/sta
```

## Điểm cần biết về flow

- Script abc mặc định của Yosys 0.33 không chèn buffer và không đổi cỡ cell. Net fanout lớn (ví dụ `ex_hold_q` kéo 60 cell) có trễ vô lý, nên script thêm `buffer`, `upsize`, `dnsize`.
- Yosys 0.33 map bộ cộng, bộ trừ và bộ so sánh thành chuỗi ripple, còn Genus chọn bộ cộng nhanh. Script dùng `syn/yosys/lcu_kogge_stone.v` để map carry kiểu Kogge-Stone. Đã chứng minh tương đương với bản ripple bằng SAT của Yosys.
- Ràng buộc tối thiểu: clock 20 ns, trễ vào và ra bằng 0, false path từ `rst_n`. F_max lấy từ đường flop tới flop. Đường vào (từ `if_rdata_i`, `d_rsp_rdata_i`) và đường ra được báo riêng, vì trễ thật phụ thuộc SRAM macro và bus.
- Kết quả abc dao động theo mục tiêu trễ `-D`. Vì vậy số trước và sau được so trên cùng một dải `-D` (1500, 2000, 2500, 3000 ps).
- So chéo một lần bằng OpenROAD (đặt cell thô, `repair_design`): đường flop tới flop 2,4 đến 2,6 ns, gần số của flow wire load (2,5 đến 2,8 ns). Flow đơn giản đủ để xem xu hướng.

## Việc 1. Số liệu gốc (RTL trên main, trước khi tối ưu)

Chu kỳ nhỏ nhất của đường flop tới flop (ns), theo mục tiêu trễ của abc:

| Cấu hình | D=1500 | D=2000 | D=2500 | D=3000 |
| --- | ---: | ---: | ---: | ---: |
| ENABLE_M=0 | 2,281 | 2,529 | 2,529 | 2,529 |
| ENABLE_M=1 | 3,054 | 3,054 | 3,352 | 3,484 |

Ở D=2000: ENABLE_M=0 đạt khoảng 395 MHz, diện tích 17 112 µm². ENABLE_M=1 đạt khoảng 327 MHz, diện tích 28 039 µm². Đề bài chỉ cần 50 MHz nên còn dư nhiều, kể cả khi GPDK45 và đi dây làm chậm đi vài lần.

Đường găng của ENABLE_M=0 (đánh dấu `keep` trên các tín hiệu chính để đọc được tên):

`ex_hold_q` → mux lệnh → forward → `ex_rs2` → so sánh nhánh `ex_lt` → `ex_br_cond` → `ex_exc` → `ex_trap` → `d_req_valid_o` → `pipe_stall` → `ex_go` → enable của mọi thanh ghi pipeline.

Nghĩa là kết quả so sánh nhánh và bit thấp của ALU (bit 0 còn mux kết quả SLT, phải qua hết chuỗi carry) nằm trên đường quyết định phát yêu cầu bus và dừng pipeline, dù lệnh load/store không bao giờ là lệnh nhảy.

Đường găng của ENABLE_M=1 đi vào bộ nhân (`p_lo_q`, `p_hi_q`) và `wb_result_q`. Bộ nhân đã chia 2 chu kỳ theo thiết kế nên không sửa.

## Việc 2. Thử tối ưu đường găng (không giữ thay đổi RTL)

Hai thay đổi đã thử trong `rtl/core/rv32_core.v`:

1. `ex_addr_lo`: hai bit thấp địa chỉ load/store và đích nhảy tính bằng bộ cộng 2 bit trên toán hạng ALU, không lấy từ `ex_alu_res[1:0]`. Các lệnh này luôn dùng phép ADD nên giá trị bằng nhau.
2. `ex_ok`: `d_req_valid_o`, `md_req`, `ex_redirect` dùng ngoại lệ theo nhóm lệnh thay cho `ex_trap`. Decoder ép mọi cờ về 0 khi illegal và mỗi lệnh chỉ bật một cờ, nên load/store chỉ còn lỗi lấy lệnh và lệch địa chỉ, lệnh M chỉ còn lỗi lấy lệnh, lệnh nhảy chỉ còn lỗi lấy lệnh và đích lệch.

Kiểm tra bản thử:

- Tương đương hình thức với RTL gốc (Yosys `equiv_make`, `equiv_simple`, `equiv_induct`), cả ENABLE_M=0 và 1: mọi flop và ngõ ra đều chứng minh được, chỉ trừ 2 bit `u_lsu_align.req_addr_lo_i`. Hai bit này chỉ khác khi lệnh không phải ADD, lúc đó `d_req_valid_o = 0` và WB không phải load nên không ai dùng.
- Regression đủ 12 target pass. Số chu kỳ của `make bench-core` giống hệt bản gốc (CPI không đổi).

Chu kỳ nhỏ nhất của đường flop tới flop (ns), gốc → bản thử:

| Cấu hình | D=1500 | D=2000 | D=2500 | D=3000 |
| --- | ---: | ---: | ---: | ---: |
| ENABLE_M=0 | 2,281 → 2,179 (−4,5%) | 2,529 → 2,392 (−5,4%) | 2,529 → 2,392 (−5,4%) | 2,529 → 2,392 (−5,4%) |
| ENABLE_M=1 | 3,054 → 3,027 (−0,9%) | 3,054 → 3,027 (−0,9%) | 3,352 → 3,396 (+1,3%) | 3,484 → 3,594 (+3,2%) |

Mức dao động của abc: khi chỉ thêm `ex_addr_lo` (một thay đổi nhỏ), M0 nhanh hơn 2,3% còn M1 chậm đi 3,3%. Vậy nhiễu khoảng ±3%.

**Kết luận:** ENABLE_M=0 nhanh hơn khoảng 5%, chỉ hơn mức nhiễu một chút. ENABLE_M=1 không cải thiện vì đường găng nằm ở bộ nhân và đường regfile → ALU → `wb_result_q`. Theo tiêu chí "chỉ giữ khi cải thiện rõ hơn mức dao động", **không giữ thay đổi RTL**, chỉ giữ số liệu (D-036). Đề bài cần 50 MHz (20 ns), core đã dư nhiều lần.

Patch bản thử lưu ở `syn/run_timing/opt2_decision_path.patch` (bị ignore, chỉ có trên máy này). Nếu sau này Genus báo vi phạm setup trên đường `ex_trap` → `ex_go` thì áp lại patch này.

## Việc 3. Clock gating

Genus chèn clock gating cho nhóm flop có enable rõ trong RTL (dạng `else if (en) q <= d`). Thống kê bằng Yosys `opt_dff` (đếm flop có chân enable):

| Cấu hình | Flop | Có enable, trước | Có enable, sau |
| --- | ---: | ---: | ---: |
| ENABLE_M=0 | 1 478 | 1 475 (99,8%) | 1 475 (99,8%) |
| ENABLE_M=1 | 1 682 | 1 679 (99,8%) | 1 679 (99,8%) |

Ba flop không có enable là `ex_fetch_q`, `ex_hold_q`, `ex_req_wait_q`. Mỗi cái 1 bit và đổi gần như mọi chu kỳ, nên không đáng gate (Genus mặc định cũng không gate nhóm dưới 3 flop).

Tỉ lệ không đổi vì vấn đề không nằm ở chỗ thiếu enable mà ở enable gần như luôn bật:

- Trước: nửa cao 32 bit của `mcycle` có enable `~wr_mcycle`, tức bật mọi chu kỳ. Nửa cao của `minstret` bật mỗi lệnh hoàn thành. Clock của 64 flop này gần như không bao giờ bị chặn, dù giá trị chỉ đổi khi nửa thấp tràn (khoảng 86 giây một lần ở 50 MHz).
- Sau (`rtl/core/rv32_csr.v`): mỗi nửa 32 bit có always riêng. Nửa cao chỉ nạp khi bị ghi (`mcycleh`, `minstreth`) hoặc khi nửa thấp toàn bit 1 và đang tăng.

Ước lượng số flop bộ đếm nhận clock mỗi chu kỳ, với CPI 1,2 của CoreMark (`minstret` tăng ở khoảng 83% số chu kỳ):

| | `mcycle` | `minstret` | Tổng |
| --- | ---: | ---: | ---: |
| Trước | 64 | 64 × 0,83 = 53 | 117 |
| Sau | 32 | 32 × 0,83 = 27 | 59 |

Khoảng 58 flop ít nhận clock hơn mỗi chu kỳ, khoảng 4% số flop của core. Đây là ước lượng tay, số công suất thật lấy từ Genus hoặc Innovus với SAIF ở trường.

Kiểm tra:

- Tương đương hình thức với bản cũ (Yosys `equiv_make`, `equiv_simple`, `equiv_induct`), cả ENABLE_M=0 và 1: mọi flop và ngõ ra chứng minh được, 0 điểm không chứng minh được.
- Regression đủ 12 target pass, lint 0 warning. Số chu kỳ của `make bench-core` giống hệt bản gốc.
- `fw/tests/asm/trap.S` (test 83, 84) đã kiểm nhớ từ nửa thấp sang nửa cao của `mcycle`. Tràn của `minstret` không có test mô phỏng (cần 2^32 lệnh), chỉ dựa vào chứng minh hình thức.

Timing và diện tích sau thay đổi (ns, µm², D=2000): ENABLE_M=0 2,575 và 17 032, ENABLE_M=1 3,067 và 28 559. Lệch so với gốc trong mức nhiễu của abc (±3%).

Các nhóm khác đã có enable hợp lý: regfile (enable riêng từng thanh ghi), `ex_instr_hold_q` (chỉ nạp khi dừng), thanh ghi WB (`ex_go & ex_valid`), CSR ít ghi (`mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`), M-unit (tích riêng chỉ nạp khi bắt đầu phép nhân, thanh ghi chia chỉ nạp khi đang chia). `wb_instr_q` (32 bit) nạp mỗi lệnh dù chỉ cần cho lệnh CSR và mtval của illegal. Chưa đổi vì `tb_core` dùng `wb_instr_q` để in vết lệnh và nhận ra lệnh M, MRET, FENCE.I, nên phải sửa cả testbench. Nhóm cần xem lại trước.

## Đổi `abc -fast` thành `abc` (26/10)

Yosys trong Docker IIC-OSIC-TOOLS 2026.10 không nhận `abc -fast`. Dòng 43 của `syn/yosys/synth_nangate.tcl` đổi thành `abc`. Bước này chỉ map logic generic, sau đó `abc -liberty` map lại sang cell Nangate45. Từ nay `make sta-core-nangate` dừng với lỗi và in 20 dòng cuối của `yosys.log` hoặc `sta.log` nếu một bước hỏng.

Số mới (D=2000, Yosys 0.33, cùng RTL với mục 3):

| Cấu hình | `abc -fast` (mục 3) | `abc` | Chênh |
| --- | --- | --- | --- |
| ENABLE_M=0 | 2,575 ns, 17 032 µm² | 2,855 ns (350 MHz), 16 995 µm² | +10,9% chu kỳ, −0,2% diện tích |
| ENABLE_M=1 | 3,067 ns, 28 559 µm² | 3,007 ns (333 MHz), 28 463 µm² | −2,0% chu kỳ, −0,3% diện tích |

Chênh lệch chỉ do bỏ `-fast`. Đã chạy lại M0 với `abc -fast` trên cùng RTL và ra đúng 2,575 ns, 17 032 µm². Bước `abc` generic cho ra cấu trúc logic khác, nên `abc -liberty` sau đó tối ưu ra kết quả khác. M0 lệch quá mức nhiễu ±3% của mục 2, M1 vẫn trong mức nhiễu. Các bảng ở mục 1 và 2 được đo với `abc -fast`, chỉ so được với nhau, không so với số mới. Core vẫn dư nhiều so với 50 MHz.

## Còn lại

- Ở trường: chạy Genus với clock gating bật, so số ICG và công suất trước và sau D-037.
- Nếu Genus báo vi phạm setup trên đường `ex_trap` → `ex_go`, áp lại patch của việc 2.

Bản sao RTL thử nghiệm, kết quả quét và log regression gốc ở `syn/run_timing/` (bị ignore, chỉ có trên máy này).
