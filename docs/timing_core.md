# Timing ước lượng của rv32_core (flow nhà, Nangate45)

**Các số ở đây chỉ để xem xu hướng.** Thư viện là Nangate45 (thư viện mở, 45 nm, góc typical 1,1 V, 25 °C), không phải GPDK45.
Không có đặt cell và đi dây. Trễ dây lấy theo wire load mặc định của Nangate45, clock lý tưởng.
Số chính thức (tần số, slack) lấy từ Genus và Innovus ở trường.

**Trạng thái: đang làm (WIP).** Việc 1 có số liệu gốc. Việc 2 mới đo xong ENABLE_M=0. Việc 3, 4 chưa xong.

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

## Việc 2. Tối ưu đường găng (đang làm)

Thay đổi đang thử trong `rtl/core/rv32_core.v` (chưa commit, chưa chạy hết regression):

1. `ex_addr_lo`: hai bit thấp địa chỉ load/store và đích nhảy tính bằng bộ cộng 2 bit trên toán hạng ALU, không lấy từ `ex_alu_res[1:0]`. Các lệnh này luôn dùng phép ADD nên giá trị bằng nhau.
2. `ex_ok`: `d_req_valid_o`, `md_req`, `ex_redirect` dùng ngoại lệ theo nhóm lệnh thay cho `ex_trap`. Decoder ép mọi cờ về 0 khi illegal và mỗi lệnh chỉ bật một cờ, nên load/store chỉ còn lỗi lấy lệnh và lệch địa chỉ, lệnh M chỉ còn lỗi lấy lệnh, lệnh nhảy chỉ còn lỗi lấy lệnh và đích lệch.

Kiểm tra tương đương hình thức với RTL gốc (Yosys `equiv_make`, `equiv_simple`, `equiv_induct`), cả ENABLE_M=0 và 1: mọi flop và ngõ ra đều chứng minh được, chỉ trừ 2 bit `u_lsu_align.req_addr_lo_i`. Hai bit này chỉ khác khi lệnh không phải ADD, lúc đó `d_req_valid_o = 0` và WB không phải load nên không ai dùng.

Số liệu sau tối ưu (ns):

| Cấu hình | D=1500 | D=2000 | D=2500 | D=3000 |
| --- | ---: | ---: | ---: | ---: |
| ENABLE_M=0 | 2,179 | 2,392 | 2,392 | 2,392 |
| ENABLE_M=1 | chưa đo | chưa đo | chưa đo | chưa đo |

ENABLE_M=0 nhanh hơn khoảng 4 đến 5% ở mọi D. Đường găng mới là đường dữ liệu tự nhiên: regfile → ALU → `wb_result_q` và `d_addr_o`.

## Việc 3. Clock gating (đang làm)

Thống kê trên RTL gốc, ENABLE_M=1 (Yosys `opt_dff`, đếm flop có chân enable): 1 679 trên 1 682 flop có enable (99,8%). Ba flop không có enable là `ex_fetch_q`, `ex_hold_q`, `ex_req_wait_q` (mỗi cái 1 bit, không đáng gate).

Tuy vậy, enable của `mcycle` bật mỗi chu kỳ và của `minstret` bật mỗi lệnh. Nửa cao 32 bit của hai bộ đếm chỉ đổi khi nửa thấp tràn, nhưng hiện dùng chung enable với nửa thấp nên Genus không tiết kiệm được gì. Định tách enable riêng cho nửa cao.

## Việc 4. Nhật ký quyết định

Chưa ghi vào `docs/core_decisions.md`. Dự kiến D-036 (đường quyết định ở EX) và D-037 (enable nửa cao bộ đếm).

## Bước tiếp theo

1. Đo ENABLE_M=1 sau tối ưu trên cùng dải D.
2. Chạy hết regression (lint-core, unit-core, fw-core, isa-core, bench-core, arch-core, lint-bus, unit-bus, fw-bus, accel). So số chu kỳ của bench-core với bản gốc để chắc CPI không đổi.
3. Chỉ giữ thay đổi RTL nếu cải thiện rõ hơn mức dao động của abc.
4. Làm việc 3, ghi D-036, D-037.

Bản sao RTL thử nghiệm, kết quả quét và log regression gốc ở `syn/run_timing/` (bị ignore, chỉ có trên máy này).
