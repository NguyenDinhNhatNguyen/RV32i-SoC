# synth_accel.tcl - Genus tổng hợp accelerator (PD-01), theo luồng Lab 01: kiểm định trước tổng hợp -> syn_generic/map/opt -> kiểm định sau tổng hợp -> xuất file.
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

# Thư viện và RTL
set_db init_lib_search_path [list $LIB_DIR]
set_db init_hdl_search_path [list $REPO/rtl/accel]
read_libs $LIB_SLOW

# Không dùng scan flop: netlist có scan flop mà không có scan chain làm Innovus báo IMPSP-9099 (bài học các Lab trước).
foreach c [get_db lib_cells -if {.base_name == SDFF*}] { set_db $c .dont_use true }

# Clock gating phải bật trước elaborate, nếu không Genus bỏ qua (POPT-104)
if {$CG} { set_db lp_insert_clock_gating true }

read_hdl -language v2001 {sa_core_model.v accel_wrapper.v}
elaborate $TOP

# Số flop tối thiểu cho một clock gate là thuộc tính của design trong Genus 21.1, không phải của root.
# Bọc catch để bản Genus khác tên thuộc tính chỉ cảnh báo, không dừng cả script.
if {$CG && [catch {set_db [get_db designs] .lp_clock_gating_min_flops 4} msg]} {
    puts "CANH BAO: khong dat duoc lp_clock_gating_min_flops ($msg), dung mac dinh cua Genus"
}

# Kiểm định trước tổng hợp (Quality Gate 1)
check_design -unresolved > $AUDIT/pre_syn_unresolved.rpt     ;# phải 0 unresolved
check_design -all        > $AUDIT/pre_syn_design_lint.rpt    ;# 0 latch, 0 loop, 0 multi-driven
read_sdc $REPO/syn/constraints/accel.sdc
check_timing_intent -verbose > $AUDIT/pre_syn_timing_intent.rpt  ;# 0 unconstrained endpoint

# Tổng hợp 3 giai đoạn
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium

# Lệnh thử: lỗi thì chỉ cảnh báo, không dừng script (tên lệnh, thuộc tính khác nhau giữa các bản Genus)
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "CANH BAO: lenh \"$cmd\" loi: $msg" }
}

# assign trong netlist làm Innovus lỗi. Genus 21.1 bỏ lệnh remove_assigns, thay bằng thuộc tính cùng tên.
try_cmd {set_db remove_assigns true}

syn_generic
syn_map
syn_opt

# Dọn netlist (Quality Gate 2)
try_cmd {remove_assigns_without_optimization}
try_cmd {set_db write_vlog_unconnected_port_style none}

# Xuất file bàn giao cho Innovus, Conformal, GLS trước, để báo cáo có lỗi vẫn còn netlist
write_hdl > $OUT/${TOP}_netlist.v
write_sdc > $OUT/${TOP}_synth.sdc
# LEC dùng lec/accel_rtl2gate.do (make lec-accel), không dùng write_do_lec
# vì dofile của Genus cần license Conformal Ultra mà server trường không có.

try_cmd {check_design -all > $AUDIT/post_syn_design_lint.rpt}
try_cmd {report_qor          > $RPT/qor.rpt}
try_cmd {report_timing -lint > $RPT/timing_lint.rpt}
try_cmd {report_timing       > $RPT/timing.rpt}
try_cmd {report_area         > $RPT/area.rpt}
try_cmd {report_gates        > $RPT/gates.rpt}
try_cmd {report_power        > $RPT/power.rpt}
if {$CG} { try_cmd {report_clock_gating > $RPT/clock_gating.rpt} }

puts "Genus xong: $OUT/${TOP}_netlist.v (CG=$CG)"
quit
