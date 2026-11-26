# IR drop tĩnh của `soc_top` (Voltus/Innovus, Lab 06 mục 3.2)

Tài liệu này mô tả cách chạy phân tích IR drop tĩnh trên layout của `soc_top`, kết quả ngày 20/11 (số chính xác đọc ngày 25/11) và các giới hạn. Đây là phần dựng flow (LEC-04) và số liệu đầu tiên. Chưa phải sign-off (LEC-06).

## 1. Đối tượng và điều kiện

| Mục | Giá trị |
| --- | --- |
| Database | `pnr/run_soc_p9/DBS/route_eco.enc.dat` (layout chính thức, bản `_p9`) |
| Công cụ | Innovus 21.19 (batch), Voltus rail analysis (`voltus_rail` 21.19) |
| Phương pháp | `era_static`, accuracy `xd`, view `av_setup` |
| VDD của view | 0,9 V (báo cáo công suất ghi `Rail VDD Voltage 0.9`, thư viện `slow_vdd1v0`) |
| Die | 450 x 450,68 um, 8 macro |
| Nguồn cấp | 12 pad giả định trên vòng ring VDD (xem mục 4) |
| Hoạt độ | A = 0,1, B = 0,5 (`set_default_switching_activity -input_activity`, chu kỳ 10 ns) |

## 2. Cách chạy

Script nằm ở `power/`: `ir_static.tcl` (Tcl cho Innovus) và `run_ir.sh` (chạy và tóm tắt). Chỉ đọc database, ghi kết quả vào `power/run_ir_act<hoạt độ>/` (đã bị `.gitignore`).

```bash
cd ~/RV32i-SoC
IR_DB=pnr/run_soc_p9/DBS/route_eco.enc.dat \
IR_TECH=/home/eda/library/cadence/gpdk045_v_6_0/qrc/typical/qrcTechFile \
nohup bash power/run_ir.sh > ~/ir_a.txt 2>&1 &            # kịch bản A (hoạt độ 0,1)

IR_ACT=0.5 IR_DB=... IR_TECH=... nohup bash power/run_ir.sh > ~/ir_b.txt 2>&1 &   # kịch bản B
```

Mỗi lần chạy mất vài phút. Biến môi trường: `IR_DB`, `IR_TECH`, `IR_ACT` (mặc định 0,1), `IR_VIEW` (mặc định `av_setup`), `IR_VOLT` (mặc định 0,9), `IR_PERIOD` (mặc định 10 ns), `IR_PADS` (file pad có sẵn), `IR_PADMODE` (`xy` mặc định, hoặc `auto`), `IR_OUT`. Mỗi bước in `IR: OK` hoặc `IR: FAIL` ra `reports/steps.txt`.

## 3. Các bước trong `ir_static.tcl`

1. `restoreDesign` database route.
2. `set_power_analysis_mode -method static ... -write_static_currents true`, rồi `set_default_switching_activity` và `report_power -rail_analysis_format VS`: ghi dòng điện từng cell vào `static_VDD.ptiavg` và `static_VSS.ptiavg`.
3. `set_rail_analysis_mode -method era_static -accuracy xd -analysis_view av_setup -extraction_tech_file <QRC>`.
4. Từ vòng ring VDD (`dbGet`), ghi file pad (mục 4).
5. `set_pg_nets` cho VDD (0,9 V, ngưỡng 5%) và VSS, `set_rail_analysis_domain`, `set_power_data -format current`.
6. `set_power_pads -net VDD -format xy -file <pad>`.
7. `analyze_rail -type net -results_directory <dir> VDD`. Bước chỉ tính "OK" khi có file kết quả, vì `analyze_rail` có thể in `**ERROR` mà vẫn trả về bình thường.

## 4. Những điều đã rút ra khi dựng flow (20/11)

Mỗi mục là một lỗi đã gặp, để người sau khỏi lặp lại.

- **File QRC.** `PDK_GPDK45/qrc/gpdk045.tch` không đọc được (`VOLTUS-5360`). Dùng `/home/eda/library/cadence/gpdk045_v_6_0/qrc/typical/qrcTechFile`.
- **File dòng điện `.ptiavg`.** Thiếu `-write_static_currents true` trong `set_power_analysis_mode` thì `report_power` chỉ ghi file text, và `analyze_rail` dừng với `VOLTUS_RAIL-1152`. Cùng tùy chọn có trong `Project_2_Hardware_Accelerator/scripts/run_lab06_signoff.tcl` (dòng 129).
- **Định dạng file pad.** Voltus 21.19 bỏ qua mọi dòng `x y Metal8` ("Skip invalid voltage source", `VOLTUS_RAIL-1261`). Định dạng đúng, lấy từ file `VDD.auto_ploc_vsrc.pp` do chính Voltus sinh, có 4 cột và dòng tiêu đề:

  ```
  *vsrc_name           x          y          layer_name
  VDDPad1 118.250 12.510 metal8_conn
  ```

  Tên layer dạng `metalN_conn` (chữ thường).
- **Chế độ pad tự động.** `set_power_pads -auto_voltage_source_creation true -layer Metal8 -number_of_voltage_source 12` tạo 1089 nguồn khắp lưới (không dừng ở 12), nên sụt áp bị đánh giá thấp. Không dùng cho kết quả báo cáo (`IR_PADMODE=auto` chỉ để thử).
- **Tọa độ pad Lab.** Các file `VDD.pp` của Lab 1 và Project 2 là cho die nhỏ hơn, không dùng lại. Script đặt pad từ hình học vòng ring thật.

## 5. Kết quả (20/11)

Vòng ring VDD gồm 4 wire: 2 wire ngang trên Metal8 (y = 11,51 và y = 437,17) và 2 wire dọc trên Metal7 (x = 11,5 và x = 436,5), phạm vi 11,5 đến 438,5 um. Mỗi wire có 3 pad (ở 1/4, 1/2, 3/4 chiều dài, trên đường giữa), tổng 12 pad. Voltus xác nhận `Voltage Source Added/Total: 12/12`.

| | A (hoạt độ 0,1) | B (hoạt độ 0,5) |
| --- | --- | --- |
| Điện áp VDD nhỏ nhất / trung bình / lớn nhất | 0,899 / 0,900 / 0,900 V | 0,898 / 0,900 / 0,900 V |
| Sụt áp tối đa (làm tròn 3 chữ số) | khoảng 1 mV | khoảng 2 mV |
| Dòng pad nhỏ nhất / trung bình / lớn nhất | 70 uA / 0,109 mA / 0,160 mA | 0,142 / 0,238 / 0,353 mA |
| Điện áp lớn nhất trên một điện trở | 44 uV | 0,103 mV |

Tổng công suất ở hoạt độ 0,1 (báo cáo `power_act0.1.rpt`): 1,975 mW, gồm nội bộ 0,962 mW, chuyển mạch 1,001 mW, rò 0,011 mW.

Log của Voltus chỉ làm tròn đến 1 mV. Số chính xác của kịch bản A lấy từ file điện áp từng instance `power/run_ir_act0.1/reports/rail/VDD_25C_avg_4/Reports/VDD/VDD.iv` (46674 instance, đọc 25/11):

| Kịch bản A | Giá trị |
| --- | --- |
| Điện áp thấp nhất | 0,89931 V, tức sụt 0,69 mV (0,077% của 0,9 V) |
| Điện áp trung bình | 0,89992 V, tức sụt khoảng 0,08 mV |
| Instance thấp nhất | nhiều instance cùng 0,89931 V (file chỉ ghi 5 chữ số), ví dụ `FE_OFC16_FE_DBTN16_rst_n_sync_BAR` (CLKBUFX8) |
| Theo lớp (`VDD.layerbased_ir.rpt`) | Metal1 0,693 mV; Metal2 đến Metal8 khoảng 0,09 mV |
| Số vi phạm (`VDD.main.rpt`) | 0, ngưỡng 0,855 V |

Thư mục `VDD_25C_avg_3` là lần thử chế độ `auto` (1089 nguồn), không dùng. Thư mục `VDD_25C_avg_4` là lần chạy 12 pad, đúng với bảng trên. Kịch bản B (hoạt độ 0,5) chưa được đọc chi tiết từ file, chỉ có số làm tròn của log.

## 6. So với ngưỡng

Lab 06 dùng ngưỡng sụt áp tĩnh nhỏ hơn 5% VDD. VDD của Lab là 1,0 V (50 mV), còn view `av_setup` của `soc_top` là 0,9 V (45 mV). Nhóm chốt ngưỡng 45 mV (5% của 0,9 V, đúng điện áp corner slow mà timing và IR đang dùng; Phát đề xuất 22/11, nhóm xác nhận 25/11). Kết quả ở cả hai kịch bản (khoảng 1 đến 2 mV) thấp hơn cả hai ngưỡng.

## 7. Giới hạn và việc còn lại

- **Pad là giả định.** Thiết kế chưa có pad hay bump thật. Số liệu chỉ đúng khi nguồn được cấp từ 12 điểm trên vòng ring. Cần nhóm hoặc thầy xác nhận cách cấp nguồn.
- **Dòng pad chưa khớp công suất.** Ở kịch bản A, 12 pad x 0,109 mA cho khoảng 1,3 mA, trong khi 1,975 mW chia 0,9 V cho khoảng 2,2 mA. Chưa rõ nguyên nhân (có thể do scale của `.ptiavg` hoặc phần dòng không đi qua pad VDD). Mức sụt áp rất thấp nên kết luận không đổi, nhưng cần ghi chú.
- **Chỉ phân tích VDD.** Chưa phân tích VSS (ground bounce) và không có EM, vì Lab 06 không yêu cầu. Cần hỏi nhóm hoặc thầy có cần hay không.
- **Layout cuối.** Chạy trên `route_eco` của `run_soc_p9`. LEC-06 (sign-off) chỉ xong khi chạy lại trên layout cuối, nếu PD-08 làm thay đổi lưới nguồn.
- **Database là bản cuối của `_p9`.** `route_eco.enc.dat` được lưu lúc 15:10 ngày 18/11 (`~/eco_p9.tcl`), rồi `~/eco_out_p9.tcl` khôi phục đúng database này để ghi `soc_top_pnr.v`, SPEF, SDF và GDS lúc 15:31. Giữa hai bước không có lệnh nào sửa layout (Phát làm ECO, xác nhận 21/11, `docs/pnr_soc_status.md` mục 6). Vì vậy IR drop ở đây và Tempus của STA-05 chạy trên cùng một layout.
- **Vành nguồn VSS.** Sheet (PD-06) ghi "2 chỗ hở VSS ở góc vành nguồn". Kết quả ở đây chỉ phân tích VDD nên không phản ánh ảnh hưởng của chỗ hở này lên VSS.
- **Hoạt độ là giả định.** 0,1 và 0,5 theo Lab 06, không phải hoạt độ từ mô phỏng thực tế của SoC.
