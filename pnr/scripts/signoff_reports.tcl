# signoff_reports.tcl - Writes the Innovus reports of the lecture sign-off checklist from a
# finished database. Read only: the design is restored and never saved.
# Run through pnr/run_signoff_reports.sh. Environment: SIGNOFF_DB (database .enc.dat),
# SIGNOFF_OUT (output folder).
set DB  $::env(SIGNOFF_DB)
set OUT $::env(SIGNOFF_OUT)
file mkdir $OUT

# Report commands: on error only warn and keep going, the shell script checks the files
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}

restoreDesign $DB soc_top

try_cmd {summaryReport -noHtml -outfile $OUT/design_summary.rpt}
try_cmd {report_ccopt_clock_trees -file $OUT/cts_clock_trees.rpt}
try_cmd {report_ccopt_skew_groups -file $OUT/cts_skew_groups.rpt}
try_cmd {report_power -outfile $OUT/signoff_power.rpt}
try_cmd {verify_drc -report $OUT/geometry.rpt}
try_cmd {verifyConnectivity -report $OUT/connectivity.rpt}
if {[catch {verifyProcessAntenna -reportfile $OUT/antenna.rpt}]} {
    try_cmd {verifyProcessAntenna -report $OUT/antenna.rpt}
}
exit
