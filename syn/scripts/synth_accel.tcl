# synth_accel.tcl - Genus tổng hợp accelerator (PD-01), theo luồng Lab 01:
# kiểm định trước tổng hợp -> syn_generic/map/opt -> kiểm định sau tổng hợp -> xuất file.
# Chạy từ gốc repo trên server: make synth-accel
# Biến CG=0 để chạy bản baseline không clock gating (so sánh power như Thử thách 2 Lab 01).

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP   accel_wrapper
set OUT   $REPO/syn/out_accel
set AUDIT $OUT/reports/audit
set RPT   $OUT/reports/synthesis
file mkdir $OUT $AUDIT $RPT
set CG [expr {[info exists ::env(CG)] ? $::env(CG) : 1}]

# 1. Thư viện và RTL
set_db init_lib_search_path [list $LIB_DIR]
set_db init_hdl_search_path [list $REPO/rtl/accel]
read_libs $LIB_SLOW

# Không dùng scan flop: netlist có scan flop mà không có scan chain làm Innovus
# báo IMPSP-9099 (bài học các Lab trước).
foreach c [get_db lib_cells -if {.base_name == SDFF*}] { set_db $c .dont_use true }

read_hdl -language v2001 {sa_core_model.v accel_wrapper.v}
elaborate $TOP

# 2. Kiểm định trước tổng hợp (Quality Gate 1)
check_design -unresolved > $AUDIT/pre_syn_unresolved.rpt     ;# phải 0 unresolved
check_design -all        > $AUDIT/pre_syn_design_lint.rpt    ;# 0 latch, 0 loop, 0 multi-driven
read_sdc $REPO/syn/constraints/accel.sdc
check_timing_intent -verbose > $AUDIT/pre_syn_timing_intent.rpt  ;# 0 unconstrained endpoint

# 3. Tổng hợp 3 giai đoạn
if {$CG} {
    set_db lp_insert_clock_gating true
    set_db lp_clock_gating_min_flops 4
}
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium
syn_generic
syn_map
syn_opt

# 4. Kiểm định sau tổng hợp (Quality Gate 2)
remove_assigns -all                                ;# assign làm Innovus lỗi
set_db write_vlog_unconnected_port_style none
check_design -all > $AUDIT/post_syn_design_lint.rpt

report_qor           > $RPT/qor.rpt
report_timing -lint  > $RPT/timing_lint.rpt
report_timing        > $RPT/timing.rpt
report_area          > $RPT/area.rpt
report_gates         > $RPT/gates.rpt
report_power         > $RPT/power.rpt
if {$CG} { report_clock_gating > $RPT/clock_gating.rpt }

# 5. Xuất file bàn giao cho Innovus, Conformal, GLS
write_hdl -mapped > $OUT/${TOP}_netlist.v
write_sdc         > $OUT/${TOP}_synth.sdc
write_do_lec -golden_design rtl -revised_design $OUT/${TOP}_netlist.v > $OUT/rtl2gate.do

puts "Genus xong: $OUT/${TOP}_netlist.v (CG=$CG)"
quit
