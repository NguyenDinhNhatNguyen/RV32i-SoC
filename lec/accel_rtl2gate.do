// accel_rtl2gate.do - LEC RTL với netlist Genus của accelerator (PD-01).
// Theo mẫu run_lec_cg.do của Lab 1 (đã chạy được với license của trường).
// Không dùng dofile do Genus sinh vì nó cần license Conformal Ultra.
// Chạy từ gốc repo trên server: make lec-accel
// Thư viện đọc từ ~/PDK_GPDK45 (bản copy của Lab trong home mỗi người).

read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
read design -golden -verilog rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v
read design -revised -verilog syn/out_accel/accel_wrapper_netlist.v
set root module accel_wrapper -both
set system mode lec
add compared points -all
compare
report verification > syn/out_accel/reports/lec_verification.rpt
report verification
exit
