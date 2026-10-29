# sta_soc_nangate.tcl - OpenSTA on the Yosys Nangate45 netlist of soc_top with the real
# syn/constraints/soc.sdc (home flow, STA-03), FOR TRENDS ONLY. Official numbers come from
# Genus and Tempus at school (make synth-soc, make sta-soc).
# No placement or routing: default Nangate45 wire load, ideal clock, the 8 SRAM macros are
# black boxes so paths through them are not timed.
# Run: sta -no_splash -exit syn/yosys/sta_soc_nangate.tcl, through make sta-soc-nangate:
#   YS_OUT      folder with soc_top_nangate.v and stat.txt
#   YS_LIB      Nangate45 liberty file
#   STA_PERIOD  clock period in ns (default 20), replaces SOC_PERIOD in soc.sdc
set top    soc_top
set out    $::env(YS_OUT)
set period [expr {[info exists ::env(STA_PERIOD)] ? $::env(STA_PERIOD) : 20.0}]
set repo   [file normalize [file dirname [info script]]/../..]

read_liberty $::env(YS_LIB)
read_verilog $out/${top}_nangate.v
link_design $top

# soc.sdc with the SOC_PERIOD line replaced, so the IO delays follow the period
set fp [open $repo/syn/constraints/soc.sdc r]
set sdc [read $fp]
close $fp
if {![regsub -line {^set SOC_PERIOD .*$} $sdc "set SOC_PERIOD $period" sdc]} {
    puts "ERROR: no \"set SOC_PERIOD\" line in syn/constraints/soc.sdc"
    exit 1
}
set run_sdc $out/soc_run_$period.sdc
set fp [open $run_sdc w]
puts -nonewline $fp $sdc
close $fp
read_sdc $run_sdc

# Worst slack of a path group and check (max = setup or recovery, min = hold or removal)
proc worst {group delay} {
    set p [lindex [find_timing_paths -path_group $group -path_delay $delay] 0]
    if {$p eq ""} { return "n/a" }
    return [format "%.3f" [get_property $p slack]]
}
set setup    [worst clk max]
set hold     [worst clk min]
set recovery [worst asynchronous max]
set removal  [worst asynchronous min]
set area "n/a"
set fp [open $out/stat.txt r]
foreach line [split [read $fp] "\n"] {
    if {[regexp {Chip area[^0-9]*([0-9.]+)} $line -> a]} { set area $a }
}
close $fp

set rpt $out/sta_p$period
file mkdir $rpt
check_setup -verbose > $rpt/check_setup.txt
report_checks -path_group clk -path_delay max -fields {fanout cap slew} -digits 3 \
    > $rpt/setup.txt
report_checks -path_group clk -path_delay min -digits 3 > $rpt/hold.txt
report_checks -path_group asynchronous -path_delay max -digits 3 > $rpt/recovery.txt
report_checks -path_group asynchronous -path_delay min -fields {fanout slew} -digits 3 \
    > $rpt/removal.txt

# No F_max here: the real critical path starts at the IMEM macro (29/10 Genus), which is a black
# box at home, so the worst timed path is an IO path and period - slack would mislead
set line [format "period %s ns  setup %s  hold %s  recovery %s  removal %s ns  area %s um2" \
              $period $setup $hold $recovery $removal $area]
append line "  (paths through the SRAM macros not timed)"
puts $line
set fp [open $rpt/summary.txt w]
puts $fp $line
close $fp
