# power_post.tcl - PWR-02: post-layout power of soc_top per testcase in Innovus.
# Run through power/run_power_post.sh (innovus -batch). Reads the routed database and writes only
# to the run folder. The SAIF files are the PWR-01 ones (zero-delay GLS of the synthesis netlist at
# 10 ns), so cells added by PnR have no activity of their own.
#
# Env (set by run_power_post.sh): PP_DB (routed .enc.dat), PP_SPEF, PP_SAIF (folder), PP_TESTS,
# PP_OUT, PP_SCOPE, PP_VIEW

set DB    $::env(PP_DB)
set OUT   $::env(PP_OUT)
set SCOPE $::env(PP_SCOPE)

proc pplog {msg} {
    puts "PP: $msg"
    set fp [open $::OUT/steps.txt a]
    puts $fp "PP: $msg"
    close $fp
}
# Returns 1 when the command runs, logs the Tcl message otherwise
proc try_log {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} {
        pplog "FAIL $cmd : $msg"
        return 0
    }
    pplog "OK   $cmd"
    return 1
}

if {![try_log [list restoreDesign $DB soc_top]]} {
    pplog "ERROR: cannot open the database"
    exit 1
}
if {![try_log [list spefIn -rc_corner rc_typ $::env(PP_SPEF)]]} {
    pplog "ERROR: cannot read the SPEF"
    exit 1
}
try_log [list set_power_analysis_mode -method static -analysis_view $::env(PP_VIEW) -corner max]

foreach t $::env(PP_TESTS) {
    set act $::env(PP_SAIF)/$t.saif
    if {![file exists $act]} {
        pplog "ERROR: $t has no $act"
        continue
    }
    # Drop the activity of the previous test before reading the next one
    try_log [list set_default_switching_activity -reset]
    try_log [list read_activity_file -reset]
    if {![try_log [list read_activity_file -format SAIF -scope $SCOPE $act]]} {
        pplog "ERROR: $t activity not read"
        continue
    }
    file mkdir $OUT/$t
    try_log [list report_power -outfile $OUT/$t/power.rpt]
}
exit
