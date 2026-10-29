# synth_soc.tcl - Genus synthesis of the whole soc_top with soc.sdc, same Lab 01 flow as
# synth_accel.tcl: pre-synthesis checks -> syn_generic/map/opt -> post-synthesis checks -> files.
# Run from the repo root on the server: make synth-soc (CG=0 for the run without clock gating).
# Environment: CG=0|1 (default 1), PERIOD=<ns> (default 20, replaces SOC_PERIOD in soc.sdc),
# SYN_OUT=<dir> (default syn/out_soc). make synth-soc-sweep sets PERIOD and SYN_OUT (STA-03).
# The netlist and SDC are the input of soc_floorplan.tcl (PD-02, PD-03, docs/pd02_floorplan.md).
#
# Parameters are the soc_top defaults: ENABLE_M=1, ENABLE_WFI_SLEEP=1, ENABLE_DMA=0, and the
# core picks ENABLE_BTB=1 and RESET_PC = boot ROM. 8 sram_2k_macro (4 IMEM, 4 DMEM) stay as
# black boxes with timing from sram_2k_macro.lib.
#
# Scan flops are forbidden, as in synth_block.tcl:
#   1. every SDFF* library cell gets dont_use and use_scan_seqs_for_non_dft is false
#   2. after synthesis the netlist is searched for SDFF* cells, and any hit is an ERROR.
# The netlist must also hold exactly 8 sram_2k_macro instances, otherwise ERROR.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}

set TOP    soc_top
set PERIOD [env_or PERIOD 20.0]
set OUT    [file normalize [env_or SYN_OUT $REPO/syn/out_soc]]
set AUDIT $OUT/reports/audit
set RPT   $OUT/reports/synthesis
file mkdir $OUT $AUDIT $RPT
set CG [env_or CG 1]
set N_MACRO 8

# Try a command: on error only warn and keep going (names differ between Genus versions)
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

# Libraries: standard cells (slow corner) and the SRAM macro
set sram_lib $PDK_DIR/lib/sram_2k_macro.lib
if {![file exists $sram_lib]} {
    puts "ERROR: $sram_lib not found, soc_top needs the SRAM macro library"
    quit
}
set_db init_lib_search_path [list $LIB_DIR]
set_db init_hdl_search_path [list $REPO/rtl/core $REPO/rtl/bus $REPO/rtl/mem]
read_libs [list $LIB_SLOW $sram_lib]

# Scan flop ban, layer 1: no SDFF* cell may be picked, and no scan flop for normal flops
foreach c [get_db lib_cells -if {.base_name == SDFF*}] { set_db $c .dont_use true }
try_cmd {set_db use_scan_seqs_for_non_dft false}
# Double-height cells, see DONT_USE_CELLS in config.tcl
foreach n $DONT_USE_CELLS {
    foreach c [get_db lib_cells -if ".base_name == $n"] { set_db $c .dont_use true }
}

# Clock gating must be enabled before elaborate, otherwise Genus ignores it (POPT-104)
if {$CG} { set_db lp_insert_clock_gating true }

# Same file set as SOC_RTL in the Makefile (dma_apb is read but not elaborated with ENABLE_DMA=0)
set RTL [concat \
    [lsort [glob -directory $REPO/rtl/core rv32_*.v]] \
    [lsort [glob -directory $REPO/rtl/bus *.v]] \
    [lsort [glob -directory $REPO/rtl/mem *.v]] \
    [lsort [glob -directory $REPO/rtl/periph *.v]] \
    [list $REPO/rtl/accel/pe.v $REPO/rtl/accel/accelerator_top.v \
          $REPO/rtl/accel/accel_wrapper.v $REPO/rtl/accel/accel_apb.v]]
read_hdl -language v2001 $RTL
elaborate $TOP

if {$CG && [catch {set_db [get_db designs] .lp_clock_gating_min_flops 4} msg]} {
    puts "WARNING: could not set lp_clock_gating_min_flops ($msg), using the Genus default"
}

# Pre-synthesis checks (Quality Gate 1)
check_design -unresolved > $AUDIT/pre_syn_unresolved.rpt     ;# Must be 0 unresolved
check_design -all        > $AUDIT/pre_syn_design_lint.rpt    ;# 0 latch, 0 loop, 0 multi-driven
# SDC for this run: soc.sdc with the SOC_PERIOD line replaced, kept with the reports
set fp [open $REPO/syn/constraints/soc.sdc r]
set sdc_text [read $fp]
close $fp
if {![regsub -line {^set SOC_PERIOD .*$} $sdc_text "set SOC_PERIOD $PERIOD" sdc_text]} {
    puts "ERROR: no \"set SOC_PERIOD\" line in syn/constraints/soc.sdc"
    quit
}
set fp [open $OUT/soc_run.sdc w]
puts -nonewline $fp $sdc_text
close $fp
read_sdc $OUT/soc_run.sdc
check_timing_intent -verbose > $AUDIT/pre_syn_timing_intent.rpt  ;# 0 unconstrained endpoint

# 3-stage synthesis
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium
# assign statements in the netlist break Innovus (attribute since Genus 21.1)
try_cmd {set_db remove_assigns true}

syn_generic
syn_map
syn_opt

# Netlist cleanup (Quality Gate 2)
try_cmd {remove_assigns_without_optimization}
try_cmd {set_db write_vlog_unconnected_port_style none}

# Handoff files first, so a failing report still leaves a netlist
set netlist $OUT/${TOP}_netlist.v
write_hdl > $netlist
write_sdc > $OUT/${TOP}_synth.sdc
try_cmd {write_sdf -timescale ns > $OUT/${TOP}.sdf}

try_cmd {check_design -all > $AUDIT/post_syn_design_lint.rpt}
try_cmd {report_qor                   > $RPT/qor.rpt}
try_cmd {report_timing -lint          > $RPT/timing_lint.rpt}
try_cmd {report_timing                > $RPT/timing.rpt}
try_cmd {report_timing -max_paths 10  > $RPT/timing_paths.rpt}
try_cmd {report_area                  > $RPT/area.rpt}
try_cmd {report_gates                 > $RPT/gates.rpt}
try_cmd {report_power                 > $RPT/power.rpt}
# Max transition, fanout and cap violations. Check that the reset net from reset_sync (fanout
# about 2900, docs/soc_top.md section 4.7) is buffered
try_cmd {report_design_rules          > $RPT/design_rules.rpt}
if {$CG} { try_cmd {report_clock_gating > $RPT/clock_gating.rpt} }

# Scan flop ban, layer 2, and the macro count: count cell instances in the written netlist
# (an instance line starts with the cell name, then the instance name and an opening parenthesis)
set fp [open $netlist r]
set text [read $fp]
close $fp
set n_scan  [regexp -all -line {^\s*SDFF\w*\s+\S+\s*\(} $text]
set n_flop  [regexp -all -line {^\s*S?DFF\w*\s+\S+\s*\(} $text]
# Clock gating cells of gsclib045 are TLATNTSCA* or TLATNCA*, so they are not counted as latches
set n_icg   [regexp -all -line {^\s*(TLATNTSCA|TLATNCA)\w*\s+\S+\s*\(} $text]
set n_latch [expr {[regexp -all -line {^\s*TLAT\w*\s+\S+\s*\(} $text] - $n_icg}]
set n_macro [regexp -all -line {^\s*sram_2k_macro\s+\S+\s*\(} $text]
set wns ""
catch {set wns [get_db [get_db designs] .slack]}
if {$wns eq ""} { set wns "n/a" }

set fp [open $OUT/summary.txt w]
puts $fp "top=$TOP period=$PERIOD cg=$CG macros=$n_macro scan_flops=$n_scan flops=$n_flop\
latches=$n_latch icg=$n_icg wns_ps=$wns"
close $fp

if {$n_scan > 0} {
    puts "ERROR: $n_scan scan flops (SDFF*) in $netlist"
} elseif {$n_macro != $N_MACRO} {
    puts "ERROR: $n_macro sram_2k_macro instances in $netlist, expected $N_MACRO"
} else {
    puts "Genus done: $netlist (PERIOD=$PERIOD, CG=$CG, $n_macro macros, 0 scan flops,\
$n_flop flops, WNS $wns ps)"
}
quit
