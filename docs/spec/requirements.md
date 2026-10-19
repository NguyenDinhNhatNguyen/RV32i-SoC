# Yêu cầu đề bài (CE434 Final Project) và nơi đáp ứng

Nguồn: slide Final Project môn CE434 (GV Tạ Trí Đức, 16/10/2026), lưu trong Drive nhóm, không đưa lên repo công khai. Hạn nộp report PDF qua Courses: 20/12/2026.

| Yêu cầu | Đáp ứng ở đâu | Chủ |
| --- | --- | --- |
| Kiến trúc bắt buộc: core RV32I, SRAM hard macro, accelerator (Lab 2 + wrapper), interconnect, Timer, UART, GPIO | `rtl/core`, `rtl/mem`, `rtl/accel`, `rtl/bus`, `rtl/periph` | Nhân, Phát, Nguyên, Phúc |
| Process Cadence GPDK 45nm, tần số tối thiểu 50 MHz | `pnr/scripts/config.tcl`, `syn/constraints/*.sdc` (clock 20 ns) | Phát, Nguyên |
| Thiết kế RTL và kiểm tra chức năng | `tb/`, `fw/`, riscv-tests | Hiếu |
| Bộ ràng buộc thiết kế | `syn/constraints/` | Phát |
| Tổng hợp, tối ưu mức cổng, báo cáo | `syn/scripts/`, `appendix/syn*/` | Phát |
| Kiểm tra mức cổng: timing, trùng khớp, chức năng | STA (`sta/`), LEC (`lec/`), GLS (`tb/`) | Phát, Phúc, Hiếu |
| Thiết kế vật lý, báo cáo | `pnr/scripts/`, `appendix/pnr*/` | Nguyên |
| Signoff: timing, trùng khớp, chức năng, luật thiết kế, kết nối, lỗi điện | Tempus, LEC sau layout, GLS có SDF, DRC/LVS/antenna, IR drop/EM | Phát, Phúc, Hiếu, Nguyên |
| Đánh giá kết quả, so sánh thiết kế tương tự | Bảng PPA, so với PicoRV32/Ibex/SERV | Nhân, Hiếu |
| Thiết kế CLEAN, đạt chức năng và tần số | Mốc M3 Signoff clean 6/12 | Cả nhóm |
| Report: mọi bước, kết quả, tối ưu, kết luận; script/report/log ở phụ lục | `appendix/<bước>/` | Hiếu biên tập |

Điểm cộng nhóm chọn: tối ưu PPA (F_max, CPI, power theo testcase, EPI, area, GE, density), mở rộng lõi (ngắt, RV32IM, dự đoán nhánh), accelerator dùng ngắt, ngoại vi SPI/PWM (I2C tầng 2), DMA (tầng 2). Không làm: đa lõi, bảo mật.
