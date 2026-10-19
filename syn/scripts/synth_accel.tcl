# synth_accel.tcl - Genus tổng hợp accelerator để chạy thử flow (PD-01).
# Chạy: make synth-accel (từ gốc repo, trên server). Kết quả ở syn/out_accel/.
# Đường dẫn thư viện lấy từ pnr/scripts/config.tcl (điền theo báo cáo check_server).

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP  accel_wrapper
set OUT  $REPO/syn/out_accel
file mkdir $OUT $OUT/reports

set_db init_lib_search_path [list $LIB_DIR]
set_db library $LIB_SLOW
set_db lef_library [list $TECH_LEF $CELL_LEF]
set_db information_level 7

# Bài học Lab: không dùng scan flop (Innovus báo IMPSP-9099 khi netlist có scan
# flop mà không có scan chain).
foreach c [get_db lib_cells -if {.base_name == SDFF*}] { set_db $c .dont_use true }

# Clock gating tự động: dùng enable của mảng PE (en của sa_core).
set_db lp_insert_clock_gating true

read_hdl -v2001 [list \
    $REPO/rtl/accel/sa_core_model.v \
    $REPO/rtl/accel/accel_wrapper.v ]
elaborate $TOP
check_design -unresolved
read_sdc $REPO/syn/constraints/accel.sdc

syn_generic
syn_map
syn_opt

report_timing          > $OUT/reports/timing.rpt
report_area            > $OUT/reports/area.rpt
report_gates           > $OUT/reports/gates.rpt
report_power           > $OUT/reports/power.rpt
report_clock_gating    > $OUT/reports/clock_gating.rpt
report_qor             > $OUT/reports/qor.rpt

write_hdl              > $OUT/${TOP}.v
write_sdc              > $OUT/${TOP}.sdc
write_do_lec -golden_design rtl -revised_design $OUT/${TOP}.v > $OUT/rtl2gate.do

puts "Genus xong: netlist $OUT/${TOP}.v"
quit
