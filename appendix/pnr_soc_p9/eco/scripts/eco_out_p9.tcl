# eco_out_p9.tcl - Export the files of the _p9 layout after the ECO (DBS/route_eco.enc).
# Run in pnr/run_soc_p9. Same commands and options as the output part of run_all.tcl.
set REPO $::env(HOME)/RV32i-SoC
source $REPO/pnr/scripts/config.tcl
set OUT $REPO/pnr/out_soc_p9
set TOP soc_top
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}
restoreDesign DBS/route_eco.enc.dat $TOP
saveNetlist $OUT/${TOP}_pnr.v
saveNetlist $OUT/${TOP}_pnr_pg.v -includePowerGround
extractRC
try_cmd {rcOut -spef $OUT/${TOP}.spef -rc_corner rc_typ}
try_cmd {write_sdf -view av_setup $OUT/${TOP}.sdf}
if {$GDS_MAP ne ""} {
    if {$CELL_GDS ne ""} {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -merge $CELL_GDS -units 2000 -mode ALL}
    } else {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -units 2000 -mode ALL}
    }
} else {
    puts "ERROR: GDS_MAP is empty or missing in config.tcl, no GDS was written"
}
puts "ECO export done: $OUT"
exit
