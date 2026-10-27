# Thử nghiệm dự đoán nhánh cho rv32_core

Chủ: Nhân. Nhánh `feat/nhan-btb`, chưa merge. Chuẩn bị cho buổi review 8/11.
Quyết định ghi ở `docs/core_decisions.md` (D-041).

## 1. Tóm tắt

- Core hiện tại đoán không nhảy. Mỗi lệnh nhảy (nhánh nhảy, JAL, JALR) mất 1 chu kỳ. Ở Dhrystone và CoreMark đây là phần lớn số bubble.
- Đã thử hai phương án qua tham số `ENABLE_BTB` của `rv32_core`:
  - (a) `ENABLE_BTB=2`: đoán tĩnh, nhánh lùi và JAL coi là nhảy.
  - (b) `ENABLE_BTB=1`: BTB 8 hoặc 16 entry, bộ đếm 2 bit, tra ở IF.
- Hai phương án tăng hiệu năng 7 đến 11 %. BTB 8 entry thêm khoảng 4 400 µm² (Nangate45, +15 % core có RV32M). Phương án tĩnh gần như không tốn diện tích nhưng nối tổ hợp ngõ ra IMEM vào địa chỉ IMEM.
- **Đề xuất:** bật BTB 8 entry (`ENABLE_BTB=1`) cho bản nộp, chốt trước khi chạy Genus (STA-03 từ 9/11). Không dùng phương án tĩnh. Lý do ở mục 5.
- `ENABLE_BTB=0` giống hệt RTL trước đây về logic: Yosys chứng minh tương đương (mục 4.1).

## 2. Thiết kế

Pipeline 3 tầng. Lệnh lấy ở chu kỳ t chỉ có ở ngõ ra IMEM (vào EX) ở chu kỳ t+1. EX quyết định nhánh ngay chu kỳ đó, nên đoán sai vẫn chỉ mất 1 chu kỳ như cũ. Dự đoán đúng thì lệnh ở đích đã được lấy, không mất chu kỳ nào.

EX luôn tính hướng và đích thật, rồi so với dự đoán:

| Dự đoán | Thật | EX làm gì |
| --- | --- | --- |
| Không nhảy | Không nhảy | Không gì |
| Không nhảy | Nhảy | Chuyển hướng tới đích (như core cũ) |
| Nhảy | Nhảy | Không gì, lệnh ở đích đã vào IF |
| Nhảy | Không nhảy | Chuyển hướng về PC+4 |

Chỉ nhánh và JAL được đoán. Đích của chúng cố định theo PC nên EX chỉ cần so hướng, không cần so 30 bit đích. JALR không đoán (đích lấy từ thanh ghi).

### (a) Tĩnh, `ENABLE_BTB=2`

- Lệnh chỉ biết được ở EX. Muốn không mất chu kỳ thì đích (`ex_pc_q + imm`) phải đi **tổ hợp** từ EX ra `if_addr_o` ngay trong chu kỳ đó.
- Nếu đi qua flop như mọi chuyển hướng khác thì kết quả giống hệt core cũ, vì EX đã quyết định nhánh ở cùng chu kỳ. Nghĩa là đoán tĩnh ở pipeline này chỉ có lợi khi có đường tổ hợp.
- Đường mới: ngõ ra IMEM → giải mã → bộ cộng → mux → địa chỉ IMEM. Điều này phá quy tắc "`if_addr_o` ra thẳng từ flop" (mục 4.3 của `docs/spec/core.md`).

### (b) BTB, `ENABLE_BTB=1`

- Module `rtl/core/rv32_btb.v`. Ánh xạ trực tiếp, `BTB_ENTRIES` entry (8 hoặc 16), chỉ số `pc[IDX+1:2]`.
- Mỗi entry: valid, tag đầy đủ `pc[31:IDX+2]`, đích `[31:2]`, bộ đếm 2 bit bão hoà.
- Tra ở IF bằng `if_pc_q` (flop). Trúng và bit 1 của bộ đếm bằng 1 thì PC kế là đích, không thì PC+4. `if_addr_o` vẫn ra thẳng từ flop.
- Cập nhật ở EX khi nhánh hoặc JAL rời EX. Trúng thì đẩy bộ đếm về phía kết quả. Trượt mà nhảy thì cấp entry (JAL đếm 3, nhánh đếm 2).
- Tag đầy đủ nên trúng nghĩa là đúng lệnh đó. FENCE.I xoá hết valid, nên code bị sửa (bootloader) không bao giờ bị đoán theo bản cũ.
- Mọi flop có reset bất đồng bộ về 0, giống regfile.

### Tham số

| Tham số `rv32_core` | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `ENABLE_BTB` | 0 | 0 không đoán, 1 BTB, 2 tĩnh |
| `BTB_ENTRIES` | 8 | Số entry BTB, luỹ thừa của 2 |

Mặc định lấy từ macro `RV_ENABLE_BTB_DEFAULT`, `RV_BTB_ENTRIES_DEFAULT` trong `rtl/core/rv32_defs.vh`. Vì vậy có thể bật cho `soc_top` bằng `-D` mà không sửa `soc_top`.

## 3. Hiệu năng

Đo bằng `make bench-core` và `make bench-soc` (cách đo ở `docs/bench_core.md`, `docs/bench_soc.md`). "Đoán đúng" là tỉ lệ lệnh nhánh, JAL, JALR rời EX mà không phải chuyển hướng, đếm trong vùng đo. Core cũ "đoán không nhảy" nên tỉ lệ này thấp.

### tb_core (bộ nhớ không wait state)

| Benchmark | Đo | Base | (b) BTB 8 | (b) BTB 16 | (a) Tĩnh |
| --- | --- | ---: | ---: | ---: | ---: |
| Dhrystone rv32i | CPI | 1,163 | 1,084 | 1,081 | 1,048 |
| | DMIPS/MHz | 0,839 | 0,900 | 0,903 | 0,931 |
| | Đoán đúng | 28,0 % | 62,9 % | 64,4 % | 78,8 % |
| Dhrystone rv32im | CPI | 1,226 | 1,141 | 1,130 | 1,105 |
| | DMIPS/MHz | 0,839 | 0,902 | 0,911 | 0,931 |
| | Đoán đúng | 24,2 % | 63,3 % | 68,3 % | 80,0 % |
| CoreMark rv32i | CPI | 1,203 | 1,094 | 1,086 | 1,083 |
| | CoreMark/MHz | 1,114 | 1,224 | 1,233 | 1,236 |
| | Đoán đúng | 33,8 % | 69,3 % | 71,9 % | 72,8 % |
| CoreMark rv32im | CPI | 1,155 | 1,072 | 1,063 | 1,071 |
| | CoreMark/MHz | 2,764 | 2,978 | 3,003 | 2,979 |
| | Đoán đúng | 39,8 % | 79,8 % | 84,1 % | 80,1 % |

### soc_top (SRAM macro, bus, APB)

| Benchmark | Đo | Base | (b) BTB 8 | (b) BTB 16 | (a) Tĩnh |
| --- | --- | ---: | ---: | ---: | ---: |
| Dhrystone rv32i | CPI | 1,220 | 1,141 | 1,137 | 1,105 |
| | DMIPS/MHz | 0,800 | 0,856 | 0,858 | 0,884 |
| Dhrystone rv32im | CPI | 1,286 | 1,201 | 1,190 | 1,165 |
| | DMIPS/MHz | 0,800 | 0,857 | 0,865 | 0,884 |
| CoreMark rv32i | CPI | 1,204 | 1,096 | 1,088 | 1,085 |
| | CoreMark/MHz | 1,112 | 1,223 | 1,232 | 1,235 |
| CoreMark rv32im | CPI | 1,158 | 1,076 | 1,067 | 1,075 |
| | CoreMark/MHz | 2,755 | 2,967 | 2,992 | 2,969 |
| Nhân ma trận phần mềm rv32i (`accel_sw`) | CPI | 1,198 | 1,057 | 1,057 | 1,043 |

Tỉ lệ đoán đúng trên `soc_top` bằng đúng tb_core, vì dự đoán không phụ thuộc wait state.

Lợi so với base (CoreMark/MHz và DMIPS/MHz trên `soc_top`):

| | BTB 8 | BTB 16 | Tĩnh |
| --- | ---: | ---: | ---: |
| CoreMark rv32i | +10,0 % | +10,8 % | +11,1 % |
| CoreMark rv32im | +7,7 % | +8,6 % | +7,8 % |
| Dhrystone rv32i | +7,0 % | +7,3 % | +10,5 % |
| Dhrystone rv32im | +7,1 % | +8,1 % | +10,5 % |

Nhận xét:

- Hai phương án đều lấy lại phần lớn bubble do nhánh lặp. Phần còn lại chủ yếu là JALR (lệnh `ret`), không phương án nào đoán. Ví dụ Dhrystone rv32i với BTB 8: 24 503 lần chuyển hướng, trong đó 8 001 là JALR.
- Tĩnh thắng ở Dhrystone vì Dhrystone gọi nhiều hàm. Mọi JAL đều đoán đúng, còn BTB 8 entry bị các lệnh gọi đẩy nhau ra.
- BTB thắng ở CoreMark rv32im. Nhánh tiến hay nhảy (ví dụ `if` trong vòng lặp) BTB học được, còn đoán tĩnh luôn sai.
- Từ 8 lên 16 entry chỉ thêm khoảng 1 %.
- Speedup của accelerator giảm nhẹ (poll 25,1 → 24,3 lần ở rv32i), vì bản phần mềm nhanh lên.

## 4. Diện tích và timing

`make sta-core-nangate` (Yosys + OpenSTA, Nangate45, flow nhà, chỉ để xem xu hướng, xem `docs/timing_core.md`). Diện tích ở mục tiêu abc `-D 2000`. Chu kỳ nhỏ nhất của đường flop tới flop lấy khoảng min đến max khi quét `-D` = 1500, 2000, 2500, 3000 ps, vì abc dao động khoảng ±0,3 ns.

| Cấu hình | Diện tích (µm²) | Thêm | Flop tới flop (ns) | `if_rdata_i` → `if_addr_o` (ns) | flop → `if_addr_o` (ns) |
| --- | ---: | ---: | --- | ---: | ---: |
| ENABLE_M=0, base | 16 981 | | 2,46 đến 2,94 | không có | 0,12 |
| ENABLE_M=0, BTB 8 | 21 557 | +4 576 (+27 %) | 2,66 đến 3,32 | không có | 0,14 |
| ENABLE_M=0, tĩnh | 17 530 | +549 (+3 %) | 3,07 đến 3,67 | 1,89 | 2,51 |
| ENABLE_M=1, base | 28 339 | | 3,24 đến 3,68 | không có | 0,12 |
| ENABLE_M=1, BTB 8 | 32 652 | +4 313 (+15 %) | 3,28 đến 3,67 | không có | 0,14 |
| ENABLE_M=1, BTB 16 | 37 189 | +8 850 (+31 %) | 3,13 đến 3,49 | không có | 0,14 |
| ENABLE_M=1, tĩnh | 27 985 | khoảng 0 | 3,27 đến 3,73 | 1,89 | 2,51 |

Đo lại ngày 27/10 trong cùng một môi trường (WSL, Yosys 0.33 git sha1 2584903a060, OpenSTA 2.3.1, `make sta-core-nangate`, `-D 2000`), ra đúng các số ở `-D 2000` dùng cho bảng trên:

| Cấu hình | ENABLE_M=0 | ENABLE_M=1 |
| --- | --- | --- |
| Base (`ENABLE_BTB=0`) | 2,852 ns, 16 981 µm² | 3,235 ns, 28 339 µm² |
| BTB 8 | 2,852 ns, 21 557 µm² | 3,276 ns, 32 652 µm² |
| BTB 16 | | 3,129 ns, 37 189 µm² |
| Tĩnh | 3,067 ns, 17 530 µm² | 3,274 ns, 27 985 µm² |
| Main sau D-038 (không có tham số BTB) | 2,856 ns, 16 929 µm² | 3,113 ns, 27 876 µm² |

Base ở nhánh này tương đương logic với main (mục 4.1) nhưng mã nguồn khác cấu trúc, nên abc cho ENABLE_M=1 chậm hơn 3,9% và diện tích lệch dưới 2%, cỡ mức nhiễu. Bảng so sánh các phương án dùng base cùng nhánh. Chi tiết ở `docs/timing_core.md` trên main.

- BTB 8 entry có khoảng 480 flop (8 × (1 + 27 + 30 + 2)). Phần lớn diện tích thêm là flop của tag và đích.
- BTB: đường flop tới flop ở ENABLE_M=1 không đổi (cùng khoảng dao động). Ở ENABLE_M=0 chậm hơn 0 đến 0,4 ns tuỳ `-D`, cỡ vùng dao động của abc. Netlist không giữ tên net nên chưa đọc được đường găng đi qua đâu. Đường tra BTB (`if_pc_q` → so tag 27 bit → mux PC kế) về lý thuyết ngắn hơn đường cũ (giữ lệnh, forward, so sánh nhánh, `ex_go`).
- Phương án tĩnh: đường flop tới flop chậm hơn 0,2 đến 0,7 ns ở ENABLE_M=0. Quan trọng hơn là đường mới từ IMEM về IMEM. Trên `soc_top` đường này là: SRAM clock → Q, cộng 1,9 ns trong core, cộng mux của `imem_port`, rồi tới setup địa chỉ SRAM. Ở 50 MHz (20 ns) vẫn đủ, nhưng nó gắn timing của SRAM macro với logic core. Floorplan và SDC phải tính đường này.
- Ở 50 MHz mọi cấu hình đều còn dư nhiều. Timing không phải lý do để chọn hay bỏ.

### 4.1 `ENABLE_BTB=0` giống RTL cũ

Yosys `equiv_make`, `equiv_simple -seq 2`, `equiv_induct -seq 2` so `rv32_core` mới (`ENABLE_BTB=0`) với bản trên `main`: 4 512 điểm (ENABLE_M=0) và 5 247 điểm (ENABLE_M=1) đều được chứng minh. So với `ENABLE_BTB=2` thì có 32 điểm không chứng minh được, tức phép kiểm có tác dụng.

## 5. Đề xuất

**Bật BTB 8 entry (`ENABLE_BTB=1`, `BTB_ENTRIES=8`) cho bản nộp. Chốt ở buổi review 8/11, trước khi chạy Genus (STA-03 từ 9/11).**

- Dự đoán nhánh là một điểm cộng nhóm đã chọn (`docs/spec/requirements.md`, mở rộng lõi), cùng nhóm với tối ưu CPI. BTB 8 entry tăng CoreMark/MHz và DMIPS/MHz 7 đến 10 % trên `soc_top`.
- Flow SoC ở trường (Genus, LEC, Innovus) chưa chạy lần nào. Chốt BTB trước STA-03 thì cấu hình có BTB là cấu hình chạy flow đầu tiên, không tốn thêm vòng flow nào. Nếu để sau STA-03 mới bật thì phải chạy lại cả flow.
- BTB 8 entry thêm khoảng 4 400 µm² (+15 % core có RV32M, flow nhà), khoảng 480 flop. So với cả SoC (SRAM macro, accelerator) thì nhỏ. Timing ở 50 MHz còn dư nhiều, `if_addr_o` vẫn ra từ flop nên không đổi quy tắc thiết kế của core.
- BTB đã kiểm chứng đủ: `tb_rv32_btb` so với mô hình, toàn bộ test PASS với `ENABLE_BTB=1` (mục 7). `ENABLE_BTB=0` vẫn giống hệt RTL cũ (mục 4.1), nên nếu review không đồng ý thì chỉ cần đổi lại một define.
- BTB 16 entry tốn gấp đôi diện tích BTB 8 để lời thêm khoảng 1 %. Không đáng.
- Phương án tĩnh rẻ về diện tích và nhanh nhất ở Dhrystone. Nhưng nó nối tổ hợp ngõ ra IMEM vào địa chỉ IMEM, phá quy tắc thiết kế của core và làm khó floorplan, SDC. Không dùng.
- Muốn thêm hiệu năng sau này thì bước rẻ nhất là ngăn xếp địa chỉ trả về (RAS) 2 đến 4 entry cho `ret`. JALR đang chiếm khoảng 1/3 số lần đoán sai còn lại ở Dhrystone.

## 6. Cách chạy

```sh
make bench-core BTB=1              # BTB 8 entry
make bench-soc BTB=1 BTB_N=16      # BTB 16 entry trên soc_top
make fw-core BTB=2                 # phương án tĩnh
make sta-core-nangate              # diện tích và timing mọi cấu hình
```

- `BTB` và `BTB_N` đổi mặc định của `rv32_core` qua `-D` cho mọi bản dịch Icarus và Verilator (`tb_core`, `tb_soc`, `tb_boot`, `lint-soc`).
- File `.vvp` không ghi lại cấu hình. Khi `BTB`/`BTB_N` khác lần chạy trước (lưu ở `tb/core/out/btb.cfg`), Makefile xoá mọi `.vvp` trong `tb/core/out`, `tb/soc/out`, `tb/boot/out`. Đừng chạy hai cấu hình cùng lúc trên một bản checkout.
- Log có thêm dòng `BENCH branch` (tb_core) và `BENCH soc region <k> branch` (`scripts/bench_soc_mon.v`): số nhánh, số nhảy, JAL, JALR, số lần chuyển hướng và tỉ lệ đoán đúng.
- Bật cho `soc_top` trong flow Cadence (nếu nhóm quyết): thêm define `RV_ENABLE_BTB_DEFAULT=1` khi đọc RTL trong Genus. Không cần sửa `soc_top`.

## 7. Kiểm chứng

- `tb/unit/tb_rv32_btb.v`: so `rv32_btb` với mô hình entry (cấp phát, bộ đếm bão hoà, thay entry cùng chỉ số, flush, reset giữa chu kỳ), 8 và 16 entry. Cấy 3 lỗi (bộ đếm khi cấp phát, cấp phát cả khi không nhảy, so tag 4 bit) thì đều FAIL.
- `tb_core` với `+strict_timing` kiểm đúng số bubble: 1 sau mỗi lần EX chuyển hướng, 0 khi đoán đúng. Bench chạy ở chế độ này nên số chu kỳ trong bảng đã được kiểm.
- Toàn bộ test với từng chế độ (26/10/2026, 0 `%Warning`):

| Test | `BTB=0` | `BTB=1` | `BTB=2` |
| --- | --- | --- | --- |
| `lint-core`, `lint-bus`, `lint-soc` | PASS | PASS | PASS |
| `unit-core` | 11/11 | 11/11 | 11/11 |
| `unit-bus` | 8/8 | 8/8 | 8/8 |
| `isa-core` | 472/472 | 472/472 | 472/472 |
| `arch-core` (RISCOF, so với Spike) | 55/55, 63/63 | 55/55, 63/63 | 55/55, 63/63 |
| `fw-core` | 112/112 | 112/112 | 112/112 |
| `fw-soc` | 127/127 | 127/127 | 127/127 |
| `fw-bus` | 124/124 | 124/124 | 124/124 |
| `sim-boot` | 7/7 | 7/7 | 7/7 |
| `bench-core`, `bench-soc` | PASS | PASS (8 và 16 entry) | PASS |

`sim-boot` với BTB kiểm cả việc xoá BTB bằng FENCE.I: bootloader chạy từ ROM, ghi IMEM, `fence.i` rồi nhảy.
