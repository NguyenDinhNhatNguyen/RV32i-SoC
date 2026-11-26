# eco_p9.tcl - ECO on the _p9 layout: 2 max_tran nets, 1 Metal1 spacing error.
# Run in pnr/run_soc_p9. Saves DBS/route_eco.enc and writes reports to out_soc_p9/reports_eco.
# Does not write any output file, the export is a separate step after the checks.
set REPO $::env(HOME)/RV32i-SoC
source $REPO/pnr/scripts/config.tcl
set RPT $REPO/pnr/out_soc_p9/reports_eco
file mkdir $RPT
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}
# Latest database: route_drcfix exists only when run_all.tcl fixed DRC boxes
if {[file exists DBS/route_drcfix.enc.dat]} {
    set db DBS/route_drcfix.enc.dat
} else {
    set db DBS/route.enc.dat
}
puts "ECO: restoring $db"
restoreDesign $db soc_top
# 1. Remove filler so upsizing has room, then fix max_tran
try_cmd {deleteFiller -prefix FILLER}
try_cmd {setDelayCalMode -SIAware true}
optDesign -postRoute -drv
# 2. Reroute the net of the Metal1 spacing error (overlaps FE_OFN1608_...)
try_cmd {editDelete -net n_9957}
ecoRoute
# 3. Filler back, same command as run_all.tcl
try_cmd {addFiller -cell [dbGet [dbGet -p head.libCells.name FILL*].name] -prefix FILLER}
saveDesign DBS/route_eco.enc
# 4. Checks, same as run_all.tcl
try_cmd {verify_drc -report $RPT/drc.rpt}
try_cmd {verifyConnectivity -report $RPT/connectivity.rpt}
if {[catch {verifyProcessAntenna -reportfile $RPT/antenna.rpt}]} {
    try_cmd {verifyProcessAntenna -report $RPT/antenna.rpt}
}
try_cmd {timeDesign -postRoute -outDir $RPT/postroute_setup}
try_cmd {timeDesign -postRoute -hold -outDir $RPT/postroute_hold}
puts "ECO done: check $RPT before the export"
exit
