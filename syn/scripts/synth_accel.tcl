# synth_accel.tcl - Genus synthesis of the accelerator (PD-01), following the Lab 01 flow:
# pre-synthesis checks -> syn_generic/map/opt -> post-synthesis checks -> write files.
# Run from the repo root on the server: make synth-accel
# Set CG=0 for the baseline without clock gating (power comparison as in Lab 01 challenge 2).

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP   accel_wrapper
set OUT   $REPO/syn/out_accel
set AUDIT $OUT/reports/audit
set RPT   $OUT/reports/synthesis
file mkdir $OUT $AUDIT $RPT
set CG [expr {[info exists ::env(CG)] ? $::env(CG) : 1}]

# Libraries and RTL
set_db init_lib_search_path [list $LIB_DIR]
set_db init_hdl_search_path [list $REPO/rtl/accel]
read_libs $LIB_SLOW

# No scan flops: a netlist with scan flops but no scan chain makes Innovus report IMPSP-9099
# (lesson from earlier Labs).
foreach c [get_db lib_cells -if {.base_name == SDFF*}] { set_db $c .dont_use true }
# Double-height cells, see DONT_USE_CELLS in config.tcl
foreach n $DONT_USE_CELLS { foreach c [get_db lib_cells -if ".base_name == $n"] { set_db $c .dont_use true } }

# Clock gating must be enabled before elaborate, otherwise Genus ignores it (POPT-104)
if {$CG} { set_db lp_insert_clock_gating true }

read_hdl -language v2001 {pe.v accelerator_top.v accel_wrapper.v}
elaborate $TOP

# The minimum flop count per clock gate is a design attribute in Genus 21.1, not a root one.
# Wrapped in catch so a Genus version with another attribute name only warns.
if {$CG && [catch {set_db [get_db designs] .lp_clock_gating_min_flops 4} msg]} {
    puts "WARNING: could not set lp_clock_gating_min_flops ($msg), using the Genus default"
}

# Pre-synthesis checks (Quality Gate 1)
check_design -unresolved > $AUDIT/pre_syn_unresolved.rpt     ;# Must be 0 unresolved
check_design -all        > $AUDIT/pre_syn_design_lint.rpt    ;# 0 latch, 0 loop, 0 multi-driven
read_sdc $REPO/syn/constraints/accel.sdc
check_timing_intent -verbose > $AUDIT/pre_syn_timing_intent.rpt  ;# 0 unconstrained endpoint

# 3-stage synthesis
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium

# Try a command: on error only warn and keep going (command and attribute names differ between
# Genus versions)
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

# assign statements in the netlist break Innovus. Genus 21.1 dropped the remove_assigns command
# in favor of an attribute with the same name.
try_cmd {set_db remove_assigns true}

syn_generic
syn_map
syn_opt

# Netlist cleanup (Quality Gate 2)
try_cmd {remove_assigns_without_optimization}
try_cmd {set_db write_vlog_unconnected_port_style none}

# Write the handoff files for Innovus, Conformal and GLS first, so a failing report still leaves a netlist
write_hdl > $OUT/${TOP}_netlist.v
write_sdc > $OUT/${TOP}_synth.sdc
# LEC uses lec/accel_rtl2gate.do (make lec-accel), not write_do_lec,
# because the Genus dofile needs a Conformal Ultra license that the school server lacks.

try_cmd {check_design -all > $AUDIT/post_syn_design_lint.rpt}
try_cmd {report_qor          > $RPT/qor.rpt}
try_cmd {report_timing -lint > $RPT/timing_lint.rpt}
try_cmd {report_timing       > $RPT/timing.rpt}
try_cmd {report_area         > $RPT/area.rpt}
try_cmd {report_gates        > $RPT/gates.rpt}
try_cmd {report_power        > $RPT/power.rpt}
if {$CG} { try_cmd {report_clock_gating > $RPT/clock_gating.rpt} }

puts "Genus done: $OUT/${TOP}_netlist.v (CG=$CG)"
quit
