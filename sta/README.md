# STA (Tempus)

Script Tempus cho `soc_top`, chỉ chạy trên server trường. Thư mục `run*/` bị ignore.

| File | Nội dung |
| --- | --- |
| `scripts/sta_soc.tcl` | STA của `soc_top` trên netlist Genus (STA-03, trước layout) hoặc netlist sau route có SPEF (STA-05). Corner theo `pnr/scripts/mmmc.view`, kiểm setup, hold, recovery, removal |

Chạy: `make sta-soc` (sau `make synth-soc`), hoặc `make sta-soc SPEF=<file> NETLIST=<file> SDC=<file>` cho bản sau route, mọi đường dẫn tuyệt đối. Report ở `sta/run_soc/pre/` hoặc `sta/run_soc/spef/`, hoặc ở `STA_OUT=<thư mục tuyệt đối>` để không ghi đè lần trước. Từ 16/11 lệnh xóa `summary.txt` cũ trước khi chạy. Signoff 100 MHz (18/11) dùng `soc.sdc` với `SOC_PERIOD` 10 ns, cách tạo ở `docs/flow_notes.md` (dòng "Signoff ở chu kỳ khác"). Kết quả ở `docs/sta_results.md` mục 1, 5, 6. Cách chạy và tiêu chí: `docs/flow_notes.md` mục 2, ghi kết quả vào `docs/sta_results.md`.
