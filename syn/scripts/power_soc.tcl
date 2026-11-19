# power_soc.tcl - pre-layout power of the soc_top netlist in Genus (PWR-01).
# Called once per case by scripts/power_soc.sh (make power-soc), server only. Docs: docs/power_soc.md.
#
# Environment:
#   PWR_NETLIST  Genus netlist of soc_top (STA-04)
#   PWR_OUT      Folder for the reports of this case
#   PWR_ACT      Activity file (SAIF or VCD from make gls-soc-saif). Empty: no activity file,
#                Genus uses its default toggle rate and probability (the "default" case)
#   PWR_FMT      SAIF or VCD (default SAIF)
#   PWR_SCOPE    Instance of soc_top in the activity file (default tb_soc/dut)
#   PERIOD       Clock period in ns written into soc.sdc (default 10, the 100 MHz signoff)
# Libraries: slow corner (the only setup corner of the PDK, same as synthesis) and the SRAM macro.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg"; return 0 }
    return 1
}

set NETLIST [env_or PWR_NETLIST $REPO/syn/out_soc/soc_top_netlist.v]
set OUT     [file normalize [env_or PWR_OUT $REPO/syn/out_soc/power/default]]
set ACT     [env_or PWR_ACT ""]
set FMT     [string toupper [env_or PWR_FMT SAIF]]
set SCOPE   [env_or PWR_SCOPE tb_soc/dut]
set PERIOD  [env_or PERIOD 10]
file mkdir $OUT

set_db init_lib_search_path [list $LIB_DIR]
read_libs [list $LIB_SLOW $SRAM_LIB_SLOW]
read_netlist $NETLIST
try_cmd {init_design}

# soc.sdc with the clock period of the run (the GLS clock is 10 ns)
set fp [open $REPO/syn/constraints/soc.sdc r]
set sdc_text [read $fp]
close $fp
regsub -line {^set SOC_PERIOD .*$} $sdc_text "set SOC_PERIOD $PERIOD" sdc_text
set fp [open $OUT/power_run.sdc w]
puts -nonewline $fp $sdc_text
close $fp
read_sdc $OUT/power_run.sdc

set fp [open $OUT/activity.txt w]
if {$ACT eq ""} {
    puts $fp "activity: none, Genus default toggle rate"
    foreach a {lp_default_toggle_rate lp_default_probability} {
        if {![catch {get_db $a} v]} { puts $fp "$a = $v" }
    }
} else {
    # Command names differ between Genus versions: try the common UI one first
    set ok 0
    foreach cmd [list \
        [list read_activity_file -format $FMT -scope $SCOPE $ACT] \
        [list read_activity_file -format $FMT -instance $SCOPE $ACT] \
        [expr {$FMT eq "SAIF" ? [list read_saif -instance $SCOPE $ACT] : [list read_vcd -static -vcd_scope $SCOPE $ACT]}]] {
        if {[try_cmd $cmd]} { puts $fp "activity: $cmd"; set ok 1; break }
    }
    if {!$ok} {
        puts $fp "ERROR: could not read $ACT"
        close $fp
        puts "ERROR: could not read the activity file $ACT"
        quit
    }
}
close $fp
try_cmd {report_activity -summary > $OUT/activity_summary.rpt}

report_power > $OUT/power.rpt
if {![try_cmd {report_power -by_hierarchy -levels 3 > $OUT/power_hier.rpt}]} {
    try_cmd {report_power -depth 3 > $OUT/power_hier.rpt}
}
puts "power_soc: done, reports in $OUT"
quit
