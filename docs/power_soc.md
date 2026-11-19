# Công suất soc_top trước layout (PWR-01)

Chủ: Hiếu, cùng Phúc. Xuất SAIF (hoặc VCD) cho từng testcase từ GLS của netlist `soc_top` (VER-07), rồi tính công suất trước layout bằng Genus cho từng testcase và cho toggle rate mặc định. SAIF của task này dùng lại cho PWR-02 (công suất sau layout, Nguyên).

**Trạng thái (19/11):** flow đã sẵn sàng và đã kiểm ở nhà (mục 5). Chưa chạy trên server.

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
- Kiểm tra trong `genus.log` tỉ lệ net được gán activity từ SAIF. Tỉ lệ thấp nghĩa là tên trong SAIF không khớp netlist (xem mục 6).
- Chạy một testcase: `NETLIST=$NET make gls-soc-saif PWR_TESTS=soc`, rồi `NETLIST=$NET T="default soc" make power-soc`.

Lưu kết quả cho repo (chỉ file text do nhóm tạo):

```bash
mkdir -p appendix/power_soc_pre
cp syn/out_soc/power/summary.md appendix/power_soc_pre/
for d in syn/out_soc/power/*/; do t=$(basename $d); mkdir -p appendix/power_soc_pre/$t; cp $d/power.rpt $d/power_hier.rpt $d/activity.txt appendix/power_soc_pre/$t/ 2>/dev/null; done
cp syn/out_soc/gls_pwr/summary.txt appendix/power_soc_pre/gls_summary.txt
```

File SAIF lớn, không đưa lên repo. Giữ trên server ở `syn/out_soc/gls_pwr/saif/` cho PWR-02.

## 5. Kiểm tra ở nhà (19/11)

- `tb_soc -DGLS` với `+vcd=`: ghi VCD của `dut` đúng cửa sổ đo (Icarus, netlist Yosys, test `soc`, 16 MB cho 2458 chu kỳ). Vì VCD rất lớn, các testcase dài dùng SAIF của Xcelium.
- SAIF dùng lệnh Tcl `dumpsaif` của xmsim. Với define `GLS_SAIF`, tb dừng bằng `$stop` khi reset nhả và khi ghi `tohost`, script Tcl bật và tắt `dumpsaif` ở hai điểm đó. Các task `$toggle_*` không dùng được vì xmsim báo `*E,MSSYSTF` (thử trên server 19/11).
- `power_soc.sh` đã thử phần đọc report với file `power.rpt` của STA-04: tách đúng leakage, internal, switching, tổng, và tính đúng năng lượng.
- Chế độ RTL của `tb_soc` không đổi: fw-soc 131/131, fw-soc-c 2/2. GLS ở nhà: `soc` và `dma` PASS.
- 3 benchmark ở mức cổng (netlist Yosys, Icarus): đang chạy, Icarus mất hơn một giờ cho CoreMark. Trên server, `gls-soc-saif` kiểm luôn phần này (các benchmark phải PASS).

## 6. Nếu gặp lỗi trên server

- **Không có file SAIF** (`ERROR: no SAIF written`): xem log của test ở `syn/out_soc/gls_pwr/<test>.log`. Có thể dùng VCD thay thế cho các test ngắn: `VCD=1 OUT=syn/out_soc/gls_pwr T="soc dma i2c spi_pwm" NETLIST=$NET bash scripts/gls_soc.sh`. `power-soc` tự lấy VCD khi không có SAIF.
- **Genus không đọc được activity:** `power_soc.tcl` thử lần lượt `read_activity_file -scope`, `read_activity_file -instance`, rồi `read_saif` (hoặc `read_vcd`). Lệnh nào chạy được thì ghi vào `activity.txt`. Nếu cả ba đều lỗi, gửi phần lỗi trong `genus.log`.
- **Tỉ lệ gán activity thấp:** đổi scope bằng `PWR_SCOPE=tb_soc.dut` hoặc `PWR_SCOPE=dut` (biến môi trường của `power_soc.tcl`).

## 7. File

| File | Nội dung |
|------|----------|
| `tb/soc/tb_soc.v` | Ở chế độ GLS: `+vcd=<file>` và define `GLS_SAIF`, cửa sổ từ reset nhả đến ghi `tohost` |
| `scripts/gls_soc.sh` | `SAIF=1`, `VCD=1`, `BENCH=1` và các benchmark rv32im |
| `syn/scripts/power_soc.tcl` | Genus: netlist, SDC 10 ns, activity, `report_power` |
| `scripts/power_soc.sh` | Chạy Genus cho từng trường hợp, viết bảng `summary.md` (`make power-soc`) |
