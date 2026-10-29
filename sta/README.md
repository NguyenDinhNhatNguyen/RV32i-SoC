# STA (Tempus)

Script Tempus cho `soc_top`, chỉ chạy trên server trường. Thư mục `run*/` bị ignore.

| File | Nội dung |
| --- | --- |
| `scripts/sta_soc.tcl` | STA của `soc_top` trên netlist Genus (STA-03, trước layout) hoặc netlist sau route có SPEF (STA-05). Corner theo `pnr/scripts/mmmc.view`, kiểm setup, hold, recovery, removal |

Chạy: `make sta-soc` (sau `make synth-soc`), hoặc `make sta-soc SPEF=<file> NETLIST=<file>` cho bản sau route. Report ở `sta/run_soc/pre/` hoặc `sta/run_soc/spef/`. Script chưa chạy lần nào trên server. Cách chạy và tiêu chí: `docs/flow_notes.md` mục 2, ghi kết quả vào `docs/sta_results.md`.
