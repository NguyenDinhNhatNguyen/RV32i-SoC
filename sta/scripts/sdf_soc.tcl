# sdf_soc.tcl - Tempus: write the SDF of the post-layout soc_top at the hold corner (VER-09).
# Run from the repo root on the server: make sdf-soc-hold. Only reads the PnR outputs.
# The PnR flow (pnr/scripts/run_all.tcl) writes only the SDF of av_setup (slow library), for
# the max run of the GLS (VER-08). The min run needs the delays of av_hold (fast library),
# so this script reads the same netlist and SPEF, the views of mmmc.view, and writes:
#   soc_top_hold.sdf    write_sdf -view av_hold (fast library, RC typical)
#   soc_top_setup.sdf   write_sdf -view av_setup, to compare with the SDF of Innovus
#
# Environment:
#   NETLIST=<file>   post-layout netlist (soc_top_pnr.v)
#   SPEF=<file>      its SPEF (soc_top.spef)
#   SDC=<file>       SDC (a copy of soc.sdc at 10 ns, written by the Makefile)
#   SDF_OUT=<dir>    output folder

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

proc env_or {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

set TOP        soc_top
set NETLIST    [file normalize [env_or NETLIST ""]]
set SPEF       [file normalize [env_or SPEF ""]]
set DESIGN_SDC [file normalize [env_or SDC ""]]
set OUT        [file normalize [env_or SDF_OUT $REPO/sta/run_soc/sdf]]
file mkdir $OUT
foreach f [list $NETLIST $SPEF $DESIGN_SDC $SRAM_LIB_SLOW] {
    if {$f eq "" || ![file exists $f]} {
        puts "ERROR: $f not found (set NETLIST, SPEF and SDC)"
        exit
    }
}

read_view_definition $REPO/pnr/scripts/mmmc.view
read_verilog $NETLIST
set_top_module $TOP
read_spef -rc_corner rc_typ $SPEF
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
update_timing -full

try_cmd {write_sdf -view av_hold  $OUT/${TOP}_hold.sdf}
try_cmd {write_sdf -view av_setup $OUT/${TOP}_setup.sdf}
foreach v {hold setup} {
    set f $OUT/${TOP}_${v}.sdf
    puts "SDF: $v [expr {[file exists $f] ? "$f [file size $f] bytes" : "NOT WRITTEN"}]"
}
exit
