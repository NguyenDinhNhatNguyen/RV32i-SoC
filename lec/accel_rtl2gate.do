// accel_rtl2gate.do - LEC RTL với netlist Genus của accelerator (PD-01).
// Theo mẫu run_lec_cg.do của Lab 1 (đã chạy được với license của trường).
// Không dùng dofile do Genus sinh vì nó cần license Conformal Ultra.
// Chạy từ gốc repo trên server: make lec-accel
// Thư viện đọc từ ~/PDK_GPDK45 (bản copy của Lab trong home mỗi người).

// Lệnh nào lỗi (ví dụ thiếu license) thì bỏ qua và chạy tiếp
set dofile abort off

read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
read design -golden -verilog rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v
read design -revised -verilog syn/out_accel/accel_wrapper_netlist.v
set root module accel_wrapper -both
// Netlist có cell clock gating (latch + AND): mô hình hoá nó thành enable của flop,
// nếu không Conformal báo 3 DLAT unmapped và gần hết flop non-equivalent.
set flatten model -gated_clock
set system mode lec
// Effort mặc định để lại 149 điểm Abort sau bộ nhân 8x8. analyze datapath cần license
// Conformal_Ultra (trường chỉ có Conformal_Asic). Effort high cho PASS 812/812 (21/10, khoảng 9 phút).
// Kiểm thêm chức năng bằng mô phỏng mức cổng: make gls-accel
set compare effort high
add compared points -all
compare
report verification > syn/out_accel/reports/lec_verification.rpt
report verification
exit -force
