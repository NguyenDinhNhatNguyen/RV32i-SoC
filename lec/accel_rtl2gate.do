// accel_rtl2gate.do - LEC RTL với netlist Genus của accelerator (PD-01).
// Theo mẫu run_lec_cg.do của Lab 1 (đã chạy được với license của trường).
// Không dùng dofile do Genus sinh vì nó cần license Conformal Ultra.
// Chạy từ gốc repo trên server: make lec-accel
// Thư viện đọc từ ~/PDK_GPDK45 (bản copy của Lab trong home mỗi người).

// Lệnh nào lỗi (ví dụ thiếu license) thì bỏ qua và chạy tiếp
set dofile abort off

read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
read design -golden -verilog rtl/accel/sa_core_model.v rtl/accel/accel_wrapper.v
read design -revised -verilog syn/out_accel/accel_wrapper_netlist.v
set root module accel_wrapper -both
// Netlist có cell clock gating (latch + AND): mô hình hoá nó thành enable của flop,
// nếu không Conformal báo 3 DLAT unmapped và gần hết flop non-equivalent.
set flatten model -gated_clock
set system mode lec
// Bộ nhân 8x8 + cộng tích luỹ 20 bit làm so cổng-với-cổng bị Abort (149 điểm ngày 21/10).
// Phân tích datapath để so ở mức toán tử, rồi tăng effort cho điểm còn lại.
analyze datapath -merge -verbose
set compare effort high
add compared points -all
compare
report verification > syn/out_accel/reports/lec_verification.rpt
report verification
exit -force
