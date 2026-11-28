# Ước lượng CPI lõi 5 tầng (V2-01)

Ước lượng CPI của lõi 5 tầng (IF, ID, EX, MEM, WB) từ trace của lõi 3 tầng hiện tại. Đây là số liệu cho cổng C0 của V2. Ngày chạy: 28/11/2026.

## 1. Cách chạy

Chạy trong container (`scripts/eda.sh run "..."`):

```sh
make bench-core PLUSARGS=+trace
python3 scripts/cpi5_estimate.py tb/core/out/bench/*.bench.log
```

- `+trace` làm log của mỗi bài lớn tới 13–100 MB.
- Khi có `+trace`, Makefile in `[FAIL] coremark_*: CoreMark could not verify its result`. Đây là báo sai. Ký tự UART in xen vào giữa dòng trace nên `grep` không khớp. Dòng `PASS:` của mô phỏng vẫn đúng, CRC CoreMark vẫn ra `crclist 0xe714`, `seedcrc 0xe9f5`.
- Chạy lại không có `+trace` để có kết quả bench sạch.

## 2. Script đếm gì

`scripts/cpi5_estimate.py` đọc lệnh đã commit trong trace và dòng `BENCH` trong log.

- Chỉ đếm trong vùng BENCH, từ lần đọc `mcycle` của `bench_start` tới lần đọc `mcycle` của `bench_stop`. Số lệnh đếm được lệch `instret` của BENCH đúng 4 lệnh (các lệnh đọc CSR).
- Load-use cách 1: lệnh ngay sau load dùng `rd` của load.
- Load-use cách 2: lệnh cách load 2 lệnh dùng `rd`, lệnh ở giữa không dùng và không ghi đè `rd`.
- Số stall load-use tính bằng scoreboard, nên hai hazard liền nhau không bị cộng trùng.
- Số redirect lấy từ dòng `BENCH branch` (BTB hiện tại).

## 3. Giả định

| Mục | Giả định |
| --- | --- |
| Nhánh giải quyết ở EX | Mỗi redirect tốn 2 bubble thay vì 1, cộng 1 chu kỳ mỗi redirect |
| Nhánh giải quyết ở ID | Mỗi redirect vẫn tốn 1 bubble như hiện tại |
| Có forward load (FWD) | Dữ liệu load forward từ MEM/WB về EX. Load-use cách 1 tốn 1 bubble |
| Không forward load | Dùng kết quả load sau WB. Cách 1 tốn 2 bubble, cách 2 tốn 1 bubble |
| ALU | Forward đầy đủ, không stall |
| MUL, DIV | Giữ như lõi 3 tầng: MUL thêm 1 chu kỳ, DIV thêm 33 chu kỳ |
| BTB, truy cập IMEM | Giữ như lõi 3 tầng |

Các giả định này cần chốt với người làm lõi (Nhân) trước khi dùng số cho cổng C0.

## 4. Số đếm

| Bench | Lệnh (BENCH / đếm) | Load | Load-use cách 1 | Load-use cách 2 | MUL | MUL dùng ngay | Redirect |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CoreMark rv32i | 2 154 015 / 2 154 011 | 165 009 | 65 235 (3,03 %) | 27 413 | 0 | 0 | 222 489 |
| CoreMark rv32im | 854 541 / 854 537 | 164 097 | 65 235 (7,63 %) | 27 419 | 28 188 | 28 188 | 48 268 |
| Dhrystone rv32i | 282 521 / 282 517 | 62 000 | 13 000 (4,60 %) | 2 000 | 0 | 0 | 24 004 |
| Dhrystone rv32im | 267 521 / 267 517 | 62 000 | 13 000 (4,86 %) | 2 000 | 500 | 0 | 21 503 |

CoreMark 3 vòng lặp, `-O2`, `tb_core` không chèn stall.

## 5. CPI lõi 5 tầng

Số trong ngoặc là tần số tối thiểu (MHz) để lõi 5 tầng chạy nhanh hơn V1, lần lượt so với V1 ở 100 MHz (sign-off) và ở F_max 110,8 MHz. Công thức: f_min = f_V1 × chu kỳ_5tầng / chu kỳ_V1.

| Bench | CPI V1 | Nhánh ID, FWD | Nhánh ID, không FWD | Nhánh EX, FWD | Nhánh EX, không FWD |
| --- | --- | --- | --- | --- | --- |
| CoreMark rv32i | 1,103 | 1,134 (103 / 114) | 1,175 (107 / 118) | 1,237 (112 / 124) | 1,278 (116 / 128) |
| CoreMark rv32im | 1,089 | 1,166 (107 / 119) | 1,271 (117 / 129) | 1,222 (112 / 124) | 1,327 (122 / 135) |
| Dhrystone rv32i | 1,085 | 1,131 (104 / 115) | 1,184 (109 / 121) | 1,216 (112 / 124) | 1,269 (117 / 130) |
| Dhrystone rv32im | 1,144 | 1,193 (104 / 116) | 1,249 (109 / 121) | 1,273 (111 / 123) | 1,329 (116 / 129) |

### 5.1 Nếu bộ nhân 3 chu kỳ (bảng kiến trúc V2, 28/11)

Bảng trên giả định MUL thêm 1 chu kỳ như lõi 3 tầng. Bảng kiến trúc V2 ghi bộ nhân 3 chu kỳ, tức thêm 2 chu kỳ mỗi lệnh MUL. Cộng thêm 1 chu kỳ cho mỗi lệnh MUL ở mục 4 (tính, chưa đo):

| Bench | CPI V1 | Nhánh ID, FWD | Nhánh ID, không FWD | Nhánh EX, FWD | Nhánh EX, không FWD |
| --- | --- | --- | --- | --- | --- |
| CoreMark rv32im | 1,089 | 1,199 (110 / 122) | 1,304 (120 / 133) | 1,255 (115 / 128) | 1,360 (125 / 138) |
| Dhrystone rv32im | 1,144 | 1,195 (104 / 116) | 1,251 (109 / 121) | 1,275 (111 / 123) | 1,331 (116 / 129) |

Bản rv32i không có MUL nên không đổi. Với phương án đề xuất (nhánh ở EX, có FWD), CoreMark rv32im tăng từ 1,222 lên 1,255. Kết luận qua cổng C0 vẫn giữ. Số bộ nhân cần chốt với Nhân.

## 6. Kết luận

- CPI lõi 5 tầng nằm trong khoảng 1,13 đến 1,33.
- Trường hợp xấu nhất (nhánh ở EX, không FWD) cần trên 122 MHz để hơn V1 sign-off, trên 135 MHz để hơn V1 ở F_max. Mục tiêu V2 là 150 MHz, nên phần CPI qua cổng C0.
- Đề xuất nhánh ở EX, có FWD. So sánh nhánh ở ID làm dài đường găng, ngược mục tiêu tăng tần số. Phương án này cần trên khoảng 112 MHz (124 MHz nếu so F_max).
- Nếu MUL chạy pipeline qua EX và MEM thì bỏ được 1 chu kỳ mỗi lệnh MUL, nhưng lệnh dùng ngay kết quả MUL tốn 1 bubble. Với CoreMark rv32im, 28 188 lệnh MUL đều bị dùng ngay, nên hai phần bù nhau.
- Cột so sánh dùng V1 đúng như đã làm layout (100 MHz sign-off và F_max 110,8 MHz). Nếu V2-08 cho thấy lõi cũ tổng hợp chặt hơn đạt tần số cao hơn, ví dụ khoảng 150 MHz, thì với tỉ lệ CPI 1,222 / 1,089 V2 cần khoảng 168 MHz mới hơn (tính). Cổng G2 cần chốt so với mốc nào.
- Rủi ro chính của V2 là tần số sau layout (V2-08), không phải CPI. File `.lib` của SRAM macro chỉ có góc typical.

## 7. Giới hạn

- `scripts/cpi5_estimate.py` ở mục 1 chưa có trong repo (28/11), nên chưa chạy lại được.
- Đây là ước lượng từ trace, chưa đo trên RTL 5 tầng.
- Chưa tính stall SB/SH trên `soc_top` (3 647 chu kỳ ở CoreMark). Stall này có ở cả V1 và V2 nên gần như không đổi tỉ lệ.
- Số redirect giả định BTB giữ nguyên. Nếu BTB đổi thì phải chạy lại.
