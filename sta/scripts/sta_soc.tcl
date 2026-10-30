# sta_soc.tcl - Tempus STA of soc_top (STA-03 before layout, STA-05 after route with SPEF).
# Run from the repo root on the server: make sta-soc (after make synth-soc).
# First run on the server 30/10 (Tempus 23.14). Every report goes through try_cmd so one wrong
# command only warns and the other reports are still written.
#
# Environment:
#   NETLIST=<file>   default syn/out_soc/soc_top_netlist.v (Genus)
#   SDC=<file>       default syn/out_soc/soc_run.sdc (soc.sdc at the period of that Genus run)
#   SPEF=<file>      empty before layout. With SPEF the clock is propagated (after CTS)
#   STA_OUT=<dir>    default sta/run_soc/pre, or sta/run_soc/spef when SPEF is set
#
# Corners come from pnr/scripts/mmmc.view (same as Innovus): slow library for setup and
# recovery, fast library for hold and removal. sram_2k_macro.lib has only a typical corner and
# is used in both (docs/sta_results.md section 1). Before layout there is no SPEF, so wire
# delay is not counted and the numbers are optimistic.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}

# Try a command: on error only warn and keep going (names differ between Tempus versions)
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

set TOP     soc_top
set NETLIST [file normalize [env_or NETLIST $REPO/syn/out_soc/soc_top_netlist.v]]
set SPEF    [env_or SPEF ""]
set STAGE   [expr {$SPEF eq "" ? "pre" : "spef"}]
set OUT     [file normalize [env_or STA_OUT $REPO/sta/run_soc/$STAGE]]
file mkdir $OUT

# mmmc.view reads DESIGN_SDC, LIB_DIR, LIB_SLOW, LIB_FAST, SRAM_LIB_* and QRC_TECH
set DESIGN_SDC [file normalize [env_or SDC $REPO/syn/out_soc/soc_run.sdc]]
foreach f [list $NETLIST $DESIGN_SDC $SRAM_LIB_SLOW] {
    if {$f eq "" || ![file exists $f]} {
        puts "ERROR: $f not found (run make synth-soc first, SRAM_LIB_SLOW is set in config.tcl)"
        exit
    }
}

read_view_definition $REPO/pnr/scripts/mmmc.view
read_verilog $NETLIST
set_top_module $TOP

if {$SPEF ne ""} {
    if {![file exists $SPEF]} {
        puts "ERROR: SPEF $SPEF not found"
        exit
    }
    read_spef -rc_corner rc_typ $SPEF
    set_propagated_clock [all_clocks]
}

update_timing -full

# Reports, one per check type. Tempus 23.1 rejects -check_type together with -late or -early
# (TCLCMD-393, first run 30/10), and -late alone mixes recovery paths into the setup report
try_cmd {check_timing -verbose                         > $OUT/check_timing.rpt}
try_cmd {report_analysis_coverage                      > $OUT/coverage.rpt}
try_cmd {report_timing -check_type setup    -max_paths 10 > $OUT/setup.rpt}
try_cmd {report_timing -check_type hold     -max_paths 10 > $OUT/hold.rpt}
try_cmd {report_timing -check_type recovery -max_paths 10 > $OUT/recovery.rpt}
try_cmd {report_timing -check_type removal  -max_paths 10 > $OUT/removal.rpt}
try_cmd {report_constraint -all_violators              > $OUT/violators.rpt}
try_cmd {report_analysis_summary                       > $OUT/analysis_summary.rpt}

# Worst slack of each check (ns), n/a when the command is not available
proc worst_slack {args} {
    set s "n/a"
    catch {
        set p [report_timing {*}$args -max_paths 1 -collection]
        set s [get_property $p slack]
    }
    return $s
}
set s_setup    [worst_slack -check_type setup]
set s_hold     [worst_slack -check_type hold]
set s_recovery [worst_slack -check_type recovery]
set s_removal  [worst_slack -check_type removal]

set fp [open $OUT/summary.txt w]
puts $fp "top=$TOP stage=$STAGE setup_ns=$s_setup hold_ns=$s_hold recovery_ns=$s_recovery\
removal_ns=$s_removal"
close $fp
puts "Tempus done: $OUT (stage=$STAGE, setup $s_setup, hold $s_hold, recovery $s_recovery,\
removal $s_removal ns)"
exit
