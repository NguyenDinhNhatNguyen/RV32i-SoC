# Công suất soc_top trước và sau layout (PWR-01, PWR-02)

Chủ: Hiếu, cùng Phúc. Xuất SAIF (hoặc VCD) cho từng testcase từ GLS của netlist `soc_top` (VER-07), rồi tính công suất trước layout bằng Genus cho từng testcase và cho toggle rate mặc định. SAIF của task này dùng lại cho PWR-02 (công suất sau layout, Nguyên).

**Trạng thái (26/11):** xong. Cả 8 testcase PASS ở mức cổng và có SAIF. Genus gán được activity cho 100% flop và net. Bảng công suất ở mục 5.

## 1. Cách làm

1. `make gls-soc-saif`: GLS bằng Xcelium trên netlist Genus STA-04, zero delay, clock 10 ns. Mỗi testcase ghi ra một file SAIF của `tb_soc.dut`.
2. `make power-soc`: mỗi trường hợp chạy Genus một lần (`syn/scripts/power_soc.tcl`). Script đọc netlist, thư viện slow và macro SRAM, `soc.sdc` với chu kỳ 10 ns, file activity, rồi chạy `report_power`.
3. Trường hợp `default` không đọc activity. Genus dùng toggle rate và xác suất mặc định của tool (giá trị ghi trong `default/activity.txt`). Đây là cách đã dùng cho số công suất của STA-04.

Cửa sổ đo của SAIF bắt đầu khi reset nhả (`running = 1`) và kết thúc ở lệnh ghi `tohost`. Đây cũng là cửa sổ đếm chu kỳ. Năng lượng của một testcase = công suất tổng × số chu kỳ × 10 ns.

Chỉ có góc slow (1,0 V, 125 °C), vì PDK không có thư viện typical. Kết quả cùng góc với report power của Genus trong STA-04.

## 2. Testcase

Tất cả chạy trên cấu hình M1W1 của netlist (`PWR_TESTS` trong Makefile). Số lệnh (instret) lấy từ mô phỏng RTL, để EVA-03 tính EPI.

| Testcase | Nội dung | Chu kỳ (RTL) | Instret (RTL) |
|----------|----------|-------------:|--------------:|
| `soc` | UART, GPIO, timer, ngắt | 2459 | 1604 |
| `dma` | DMA chép bộ nhớ qua APB | 12540 | 8963 |
| `i2c` | I2C với slave mô phỏng | 1504 | 1066 |
| `spi_pwm` | SPI loopback, PWM | 2607 | 1934 |
| `soc_fw_rv32im` | Firmware C (VER-04), có accelerator | 247981 | 217079 |
| `coremark_rv32im` | CoreMark | 1040708 | 922375 |
| `dhrystone_rv32im` | Dhrystone | 378276 | 305018 |
| `accel_bench_rv32im` | Nhân ma trận bằng accelerator và bằng phần mềm | 162596 | 117726 |

## 3. Ở nhà: chuẩn bị file hex

```bash
scripts/eda.sh run "make fw-soc fw-soc-c bench-soc"
scripts/eda.sh run "make gls-soc-pack"
scp tb/soc/out/gls_images.tgz s23521043@192.168.26.26:~/RV32i-SoC-main/
```

`gls-soc-pack` đã gói thêm ảnh hex của 3 benchmark rv32im (222 file).

## 4. Trên server

```bash
cd ~/RV32i-SoC-main && git pull && tar xzf gls_images.tgz
NET=~/RV32i-SoC/syn/out_soc/soc_top_netlist.v
NETLIST=$NET make gls-soc-saif
NETLIST=$NET make power-soc
cat syn/out_soc/power/summary.md
```

- `gls-soc-saif` phải in `gls-soc: 8 passed, 0 failed`. SAIF ở `syn/out_soc/gls_pwr/saif/`.
- `power-soc` in công suất tổng của từng trường hợp. Bảng ở `syn/out_soc/power/summary.md`. Report đầy đủ ở `syn/out_soc/power/<testcase>/` (`power.rpt`, `power_hier.rpt` theo module, `activity.txt`, `genus.log`).
- Kiểm tra trong `genus.log` tỉ lệ net được gán activity từ SAIF. Tỉ lệ thấp nghĩa là tên trong SAIF không khớp netlist (xem mục 7).
- Chạy một testcase: `NETLIST=$NET make gls-soc-saif PWR_TESTS=soc`, rồi `NETLIST=$NET T="default soc" make power-soc`.

Lưu kết quả cho repo (chỉ file text do nhóm tạo):

```bash
mkdir -p appendix/power_soc_pre
cp syn/out_soc/power/summary.md appendix/power_soc_pre/
for d in syn/out_soc/power/*/; do t=$(basename $d); mkdir -p appendix/power_soc_pre/$t; cp $d/power.rpt $d/power_hier.rpt $d/activity.txt appendix/power_soc_pre/$t/ 2>/dev/null; done
cp syn/out_soc/gls_pwr/summary.txt appendix/power_soc_pre/gls_summary.txt
```

File SAIF lớn, không đưa lên repo. Giữ trên server ở `syn/out_soc/gls_pwr/saif/` cho PWR-02.

## 5. Kết quả (26/11)

Netlist Genus STA-04, góc slow, clock 10 ns. Công suất tính bằng mW. Năng lượng = công suất tổng × chu kỳ × 10 ns. EPI (năng lượng mỗi lệnh) = năng lượng / instret của RTL (mục 2).

| Testcase | Chu kỳ (GLS) | Leakage | Internal | Switching | Tổng (mW) | Năng lượng (µJ) | EPI (pJ/lệnh) |
|----------|-------------:|--------:|---------:|----------:|----------:|----------------:|--------------:|
| `default` (toggle mặc định) | - | 0,0109 | 0,5463 | 0,1787 | 0,7359 | - | - |
| `soc` | 2458 | 0,0173 | 0,2230 | 0,0656 | 0,3060 | 0,0075 | 4,69 |
| `dma` | 12539 | 0,0189 | 0,2685 | 0,0952 | 0,3826 | 0,0480 | 5,35 |
| `i2c` | 1503 | 0,0180 | 0,2337 | 0,0696 | 0,3214 | 0,0048 | 4,53 |
| `spi_pwm` | 2606 | 0,0181 | 0,2600 | 0,0803 | 0,3584 | 0,0093 | 4,83 |
| `soc_fw_rv32im` | 247980 | 0,0183 | 0,3287 | 0,1306 | 0,4776 | 1,1844 | 5,46 |
| `coremark_rv32im` | 1040707 | 0,0197 | 0,3126 | 0,1235 | 0,4557 | 4,7425 | 5,14 |
| `dhrystone_rv32im` | 378275 | 0,0205 | 0,2824 | 0,1060 | 0,4090 | 1,5471 | 5,07 |
| `accel_bench_rv32im` | 162595 | 0,0192 | 0,2965 | 0,1088 | 0,4245 | 0,6902 | 5,86 |

Chu kỳ GLS ít hơn RTL 1 chu kỳ, vì ở zero delay tb bắt lệnh ghi `tohost` ở cạnh xuống (`docs/gls_soc.md` mục 8.1).

Nhận xét:

- Với activity thật, công suất là 0,31 đến 0,48 mW. Con số này thấp hơn trường hợp `default` (0,74 mW) 35 đến 58%. Toggle mặc định của Genus vì vậy cho số bi quan. Dùng số SAIF cho bảng PPA (EVA-03).
- Internal chiếm khoảng 69 đến 73% tổng. Switching chiếm 21 đến 27%, leakage dưới 6%.
- Các test ngoại vi ngắn (`soc`, `i2c`) có công suất thấp nhất, vì lõi chờ ngoại vi nhiều. Các chương trình tính toán (`soc_fw`, CoreMark) có công suất cao nhất, khoảng 0,46 đến 0,48 mW.
- EPI khoảng 4,5 đến 5,9 pJ/lệnh. CoreMark là 5,14 pJ/lệnh. `accel_bench` cao nhất vì có thêm accelerator hoạt động.
- Số `default` 0,736 mW ở 10 ns khớp với 0,817 mW của STA-04 ở 9 ns (tỉ lệ 9/10).
- Genus 21.1 đọc SAIF bằng `read_saif -instance tb_soc/dut`. Activity được gán cho 100% đối tượng: 4122 flop, 136 cell clock gating, 22825 net.

SAIF ở `syn/out_soc/gls_pwr/saif/` trên server, cho PWR-02 (Nguyên). Report của từng trường hợp ở `appendix/power_soc_pre/`.

## 6. Kiểm tra ở nhà (19/11)

- `tb_soc -DGLS` với `+vcd=`: ghi VCD của `dut` đúng cửa sổ đo (Icarus, netlist Yosys, test `soc`, 16 MB cho 2458 chu kỳ). Vì VCD rất lớn, các testcase dài dùng SAIF của Xcelium.
- SAIF dùng lệnh Tcl `dumpsaif` của xmsim. Với define `GLS_SAIF`, tb dừng bằng `$stop` khi reset nhả và khi ghi `tohost`, script Tcl bật và tắt `dumpsaif` ở hai điểm đó. Các task `$toggle_*` không dùng được vì xmsim báo `*E,MSSYSTF` (thử trên server 19/11).
- `power_soc.sh` đã thử phần đọc report với file `power.rpt` của STA-04: tách đúng leakage, internal, switching, tổng, và tính đúng năng lượng.
- Chế độ RTL của `tb_soc` không đổi: fw-soc 131/131, fw-soc-c 2/2. GLS ở nhà: `soc` và `dma` PASS.
- 3 benchmark ở mức cổng: trên server (26/11) Xcelium chạy CoreMark trong 26 phút, cả 3 PASS.

## 7. Nếu gặp lỗi trên server

- **Không có file SAIF** (`ERROR: no SAIF written`): xem log của test ở `syn/out_soc/gls_pwr/<test>.log`. Có thể dùng VCD thay thế cho các test ngắn: `VCD=1 OUT=syn/out_soc/gls_pwr T="soc dma i2c spi_pwm" NETLIST=$NET bash scripts/gls_soc.sh`. `power-soc` tự lấy VCD khi không có SAIF.
- **Genus không đọc được activity:** `power_soc.tcl` thử lần lượt `read_activity_file -scope`, `read_activity_file -instance`, rồi `read_saif` (hoặc `read_vcd`). Lệnh nào chạy được thì ghi vào `activity.txt`. Nếu cả ba đều lỗi, gửi phần lỗi trong `genus.log`.
- **Tỉ lệ gán activity thấp:** đổi scope bằng `PWR_SCOPE=tb_soc.dut` hoặc `PWR_SCOPE=dut` (biến môi trường của `power_soc.tcl`).

## 8. File

| File | Nội dung |
|------|----------|
| `tb/soc/tb_soc.v` | Ở chế độ GLS: `+vcd=<file>` và define `GLS_SAIF`, cửa sổ từ reset nhả đến ghi `tohost` |
| `scripts/gls_soc.sh` | `SAIF=1`, `VCD=1`, `BENCH=1` và các benchmark rv32im |
| `syn/scripts/power_soc.tcl` | Genus: netlist, SDC 10 ns, activity, `report_power` |
| `scripts/power_soc.sh` | Chạy Genus cho từng trường hợp, viết bảng `summary.md` (`make power-soc`) |

## 9. PWR-02: công suất sau layout (26/11)

Chủ: Nguyên. Layout `_p9` (`DBS/route_eco.enc`), SPEF sau ECO, SAIF của PWR-01, Innovus 21.19, góc slow, clock 10 ns. Cách chạy trên server:

```bash
ACT_DIR=$HOME/RV32i-SoC-main/syn/out_soc/gls_pwr bash power/run_power_post.sh
```

Report ở `appendix/power_soc_post/`. Công suất tính bằng mW. Năng lượng và EPI tính như mục 5.

| Testcase | Leakage | Internal | Switching | Tổng (mW) | So với PWR-01 (lần) | Năng lượng (µJ) | EPI (pJ/lệnh) |
|----------|--------:|---------:|----------:|----------:|--------------------:|----------------:|--------------:|
| `soc` | 0,0179 | 0,3078 | 0,2543 | 0,5800 | 1,90 | 0,0143 | 8,89 |
| `dma` | 0,0195 | 0,3759 | 0,3587 | 0,7541 | 1,97 | 0,0946 | 10,55 |
| `i2c` | 0,0185 | 0,3233 | 0,2742 | 0,6161 | 1,92 | 0,0093 | 8,69 |
| `spi_pwm` | 0,0186 | 0,3581 | 0,3152 | 0,6919 | 1,93 | 0,0180 | 9,32 |
| `soc_fw_rv32im` | 0,0189 | 0,4602 | 0,4857 | 0,9647 | 2,02 | 2,3923 | 11,02 |
| `coremark_rv32im` | 0,0202 | 0,4360 | 0,4507 | 0,9069 | 1,99 | 9,4384 | 10,23 |
| `dhrystone_rv32im` | 0,0211 | 0,3944 | 0,3916 | 0,8071 | 1,97 | 3,0530 | 10,01 |
| `accel_bench_rv32im` | 0,0198 | 0,4119 | 0,4071 | 0,8389 | 1,98 | 1,3640 | 11,59 |

Nhận xét và giới hạn:

- Công suất sau layout bằng 1,90 đến 2,02 lần trước layout. Phần switching tăng nhiều nhất. Nguyên nhân dự kiến là cây clock, buffer và tải dây, nhóm chưa tách riêng từng phần. Hai bước còn dùng hai công cụ khác nhau (Genus và Innovus).
- Gán activity từ SAIF: ngõ vào, flop và ngõ ra macro 100%, tổng số net 80,7%. Phần còn lại do Innovus tự lan truyền.
- Chỉ có góc slow, RC typical.
- PD-08 sau đó chỉ sửa lưới `VSS` (`route_trim.enc`), netlist và dây tín hiệu không đổi, nên nhóm không chạy lại.

