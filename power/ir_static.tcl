# ir_static.tcl - LEC-04/LEC-06: static IR drop of soc_top in Innovus, following Lab 06 section 3.2.
# Run through power/run_ir.sh (innovus -batch). Reads the routed database, writes only to the run folder.
# Commands follow the ones that ran on this server in Lab 06 (~/voltus_check.cmd, 20/11 check).
# Ran on soc_top (pnr/run_soc_p9 route_eco) on 20/11, see docs/ir_drop.md. Every step is wrapped in catch and logged with "IR:".
#
# Env (set by run_ir.sh): IR_DB (routed .enc.dat), IR_TOP, IR_ACT (activity, Lab scenario A = 0.1,
# scenario B = 0.5), IR_OUT (report folder), IR_PADS (optional pad file: header "*vsrc_name x y layer_name", then "name x y metalN_conn" per line), IR_PADMODE (xy default, or auto),
# IR_VIEW (analysis view, default av_setup), IR_VOLT (VDD of the view, default 0.9), IR_PERIOD (ns, default 10),
# IR_TECH (extraction tech file for ERA)

proc env_or {name def} { if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) } ; return $def }
proc irlog {msg} {
    puts "IR: $msg"
    if {[catch {set fp [open $::OUT/steps.txt a] ; puts $fp "IR: $msg" ; close $fp}]} { }
}
proc step {name body} {
    if {[catch {uplevel 1 $body} msg]} { irlog "FAIL  $name : $msg" ; return 0 }
    irlog "OK    $name" ; return 1
}
set DB   [env_or IR_DB ""]
set TOP  [env_or IR_TOP soc_top]
set ACT  [env_or IR_ACT 0.1]
set OUT  [env_or IR_OUT reports]
set PADS [env_or IR_PADS ""]
file mkdir $OUT
file delete -force $OUT/steps.txt

if {![step "restoreDesign $DB" {restoreDesign $DB $TOP}]} { puts "IR: cannot open the database, stop" ; exit }
step "core/die box" {
    set fp [open $OUT/boxes.txt w]
    puts $fp "core [dbGet top.fPlan.coreBox]" ; puts $fp "die  [dbGet top.fPlan.box]" ; close $fp }

# 1. Static power per cell, written as current files for the rail analysis. Same commands and order as
# ~/Project_2_Hardware_Accelerator/scripts/run_lab06_signoff.tcl (line 129 then proc lab_ir), the run that
# wrote static_VDD.ptiavg and static_VSS.ptiavg on this server. The key option is
# set_power_analysis_mode ... -write_static_currents true: without it report_power writes only text (20/11).
# IR_PERIOD: clock period in ns for the activity (STA-04 locked the clock at 100 MHz, so 10).
set PERIOD [env_or IR_PERIOD 10.0]
set VIEW [env_or IR_VIEW av_setup]
step "power analysis mode (write static currents)" {
    catch {set_power_analysis_mode -reset}
    if {[catch {set_power_analysis_mode -method static -analysis_view $VIEW -corner max -create_binary_db true -write_static_currents true -honor_negative_energy true -ignore_control_signals true} m]} {
        irlog "retry without -corner: $m"
        set_power_analysis_mode -method static -analysis_view $VIEW -create_binary_db true -write_static_currents true -honor_negative_energy true -ignore_control_signals true
    }
}
step "reset activity" {set_default_switching_activity -reset}
step "default activity $ACT, period $PERIOD ns" {set_default_switching_activity -input_activity $ACT -period $PERIOD}
step "power output dir" {file mkdir $OUT/power ; set_power_output_dir $OUT/power}
step "report_power for rail analysis" {report_power -rail_analysis_format VS -outfile $OUT/power/power_act$ACT.rpt}
set PTI [lsort -unique [concat [glob -nocomplain $OUT/power/*.ptiavg $OUT/*.ptiavg ./*.ptiavg] \
                               [glob -nocomplain $OUT/power/*/*.ptiavg]]]
irlog "current files: $PTI"

# 3. Rail analysis mode. Taken from the command that worked on this server in Lab 06
# (~/voltus_check.cmd): early rail analysis, no .cl power-grid library needed.
# The analysis view of soc_top is av_setup (power.rpt of pnr/out_soc_p9), the Lab used view_func.
set VIEW [env_or IR_VIEW av_setup]
# ERA builds a technology library from an extraction (QRC) tech file. Without one it stops with
# VOLTUS_ERA-3071 (20/11). IR_TECH gives that file, for example ~/PDK_GPDK45/qrc/gpdk045.tch
# (config.tcl notes Innovus 21.1 could not read it for RC extraction, IMPEXT-1211, 21/10).
set TECH [env_or IR_TECH ""]
if {$TECH ne ""} {
    step "rail mode era_static, view $VIEW, tech $TECH" {
        set_rail_analysis_mode -method era_static -accuracy xd -analysis_view $VIEW -extraction_tech_file $TECH }
} else {
    step "rail mode era_static, view $VIEW" {set_rail_analysis_mode -method era_static -accuracy xd -analysis_view $VIEW}
}

# 2. Power pads (Lab 06: set_power_pads -net VDD -format xy -file VDD.pp). The Lab coordinates are for
# a 100x100 um accelerator, so they cannot be reused. Without IR_PADS the pads go on the VDD core ring:
# 4 corners and 4 edge midpoints of the outermost ring rectangle, on the ring layer.
if {$PADS eq ""} {
    step "pads from the VDD ring" {
        set net [dbGet -p top.nets.name VDD]
        if {$net eq "" || $net eq "0x0"} { error "net VDD not found" }
        set shapes [lsort -unique [dbGet $net.sWires.shape]]
        set layers [lsort -unique [dbGet $net.sWires.layer.name]]
        irlog "VDD special wire shapes: $shapes, layers: $layers"
        set rings {}
        foreach w [dbGet $net.sWires] {
            if {![string equal -nocase [dbGet $w.shape] ring]} { continue }
            lassign [lindex [dbGet $w.box] 0] x0 y0 x1 y1
            lappend rings [list $x0 $y0 $x1 $y1 [dbGet $w.layer.name]]
        }
        if {[llength $rings] == 0} {
            # Fallback: VDD wires on Metal7 or Metal8 (core ring and stripes)
            irlog "no ring shape found, using VDD wires on Metal7/Metal8"
            foreach w [dbGet $net.sWires] {
                set ln [dbGet $w.layer.name]
                if {$ln ne "Metal7" && $ln ne "Metal8"} { continue }
                lassign [lindex [dbGet $w.box] 0] x0 y0 x1 y1
                lappend rings [list $x0 $y0 $x1 $y1 $ln]
            }
        }
        if {[llength $rings] == 0} { error "no VDD wire on the ring layers, give a pad file with IR_PADS" }
        set xs {} ; set ys {}
        foreach r $rings { lappend xs [lindex $r 0] [lindex $r 2] ; lappend ys [lindex $r 1] [lindex $r 3] }
        set X0 [lindex [lsort -real $xs] 0] ; set X1 [lindex [lsort -real $xs] end]
        set Y0 [lindex [lsort -real $ys] 0] ; set Y1 [lindex [lsort -real $ys] end]
        # One pad group per ring wire, on that wire's own layer: centre line of the wire, at 1/4, 1/2 and 3/4
        # of its length. (The first version put 8 points 1 um inside the outer edge, all on one layer, and
        # Voltus skipped all 8 as "invalid voltage source" on 20/11.)
        set PADS $OUT/VDD.pp
        set fp [open $PADS w]
        puts $fp "*vsrc_name           x          y          layer_name"
        set lays {}
        set padn 0
        foreach r $rings {
            lassign $r x0 y0 x1 y1 ln
            set cx [expr {($x0+$x1)/2.0}] ; set cy [expr {($y0+$y1)/2.0}]
            if {($x1-$x0) >= ($y1-$y0)} {
                foreach f {0.25 0.5 0.75} { incr padn ; puts $fp "VDDPad$padn [format %.3f [expr {$x0+($x1-$x0)*$f}]] [format %.3f $cy] [string tolower $ln]_conn" }
            } else {
                foreach f {0.25 0.5 0.75} { incr padn ; puts $fp "VDDPad$padn [format %.3f $cx] [format %.3f [expr {$y0+($y1-$y0)*$f}]] [string tolower $ln]_conn" }
            }
            lappend lays $ln
            irlog "ring wire $ln box $x0 $y0 $x1 $y1"
        }
        close $fp
        set lay [lsort -unique $lays]
        irlog "pads: extent $X0 $Y0 $X1 $Y1, layer $lay, [llength $rings] wires, file $PADS"
    }
}
if {$PADS eq "" || ![file exists $PADS]} { irlog "STOP: no pad file, rail analysis skipped" ; exit }

# 4. PG net voltage and rail domain, as in Lab 06 (~/Lab1/work_pnr/innovus.cmd27 lines 57-58, which used
# 1.1 V and a 1.045 V threshold, i.e. 5%). soc_top: power.rpt of pnr/out_soc_p9 shows rail VDD = 0.9 V
# for the av_setup view (slow corner), so the default is 0.9 V with a 5% threshold (0.855 V).
set VOLT [env_or IR_VOLT 0.9]
set THR  [format %.4f [expr {$VOLT * 0.95}]]
step "set_pg_nets VDD $VOLT V, threshold $THR V" {set_pg_nets -net VDD -voltage $VOLT -threshold $THR}
step "set_pg_nets VSS 0 V, threshold [format %.4f [expr {$VOLT * 0.05}]] V" {
    set_pg_nets -net VSS -voltage 0 -threshold [format %.4f [expr {$VOLT * 0.05}]] }
step "rail analysis domain" {set_rail_analysis_domain -name PD_core -pwrnets VDD -gndnets VSS}

# 4b. Current files for the rail analysis (fix of VOLTUS_RAIL-1152)
if {[llength $PTI] > 0} {
    step "set_power_data" {catch {set_power_data -reset} ; set_power_data -format current -scale 1 [lsearch -all -inline $PTI *static_VDD*]}
} else {
    irlog "FAIL  no .ptiavg file was written by report_power, rail analysis will stop with VOLTUS_RAIL-1152"
}

# Pads are declared last, right before analyze_rail, in the same order as Lab 06 (run_lab06_signoff.tcl).
# xy pad file format, taken from the file Voltus wrote itself (VDD.auto_ploc_vsrc.pp, 20/11): a header line
# "*vsrc_name x y layer_name", then "name x y layer" with layer names like metal8_conn. Our first files had
# only "x y Metal8" and Voltus skipped every line ("Skip invalid voltage source"). IR_PADMODE=auto lets
# Voltus place sources by itself; it put 1089 sources over the whole grid, which hides the IR drop.
set PADMODE [env_or IR_PADMODE xy]
if {$PADMODE eq "auto"} {
    step "set_power_pads VDD (auto, Metal8, 12 sources)" {
        set_power_pads -reset
        set_power_pads -net VDD -auto_voltage_source_creation true -layer Metal8 -number_of_voltage_source 12 }
} else {
    step "set_power_pads VDD (xy file)" {set_power_pads -reset ; set_power_pads -net VDD -format xy -file $PADS}
}
# 5. Static rail analysis. analyze_rail can print **ERROR and still return normally, so the step
# only counts as OK when the results folder has files.
step "analyze_rail VDD" {
    analyze_rail -type net -results_directory $OUT/rail VDD
    set n [llength [glob -nocomplain -directory $OUT/rail -type f */* * */*/*]]
    if {$n == 0} { error "no result files in $OUT/rail, see **ERROR in innovus.log" }
    irlog "$n result files in $OUT/rail"
}
irlog "done, reports in $OUT"
exit
