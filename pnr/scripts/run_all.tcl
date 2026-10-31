# run_all.tcl - Innovus end-to-end flow for the accelerator (PD-01) and soc_top (PD-03 onward).
# Commands follow the Lab 02-05 syntax (floorPlan, addRing, ccopt_design...).
# Run from the repo root on the server:
#   make pnr-accel   (after make synth-accel)   TOP=accel_wrapper, the default
#   make pnr-soc     (after make synth-soc)     TOP=soc_top, floorplan from soc_floorplan.tcl
# Each step saves DBS/<step>.enc as in the Labs, for restoreDesign when debugging.
# Route/signoff (Route, Check and Report, Output files) is not in Lab 05 yet: compare with the
# routing Lab later.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP [expr {[info exists ::env(TOP)] ? $::env(TOP) : "accel_wrapper"}]
if {$TOP eq "soc_top"} {
    set SUB out_soc
} elseif {$TOP eq "accel_wrapper"} {
    set SUB out_accel
    # The accelerator has no SRAM macro. config.tcl keeps the SRAM paths for soc_top and Tempus.
    set SRAM_LEF      {}
    set SRAM_LIB_SLOW {}
    set SRAM_LIB_FAST {}
} else {
    puts "ERROR: unknown TOP=$TOP, use accel_wrapper or soc_top"
    exit 1
}
set NETLIST    $REPO/syn/$SUB/${TOP}_netlist.v
set DESIGN_SDC $REPO/syn/$SUB/${TOP}_synth.sdc
set OUT        $REPO/pnr/$SUB
set RPT        $OUT/reports
file mkdir $OUT $RPT DBS

# Sweep parameters for the PPA challenges (Lab 02-04)
set UTIL     0.70     ;# Lab 02: 0.55 / 0.70 / 0.85
set IO_GAP   15       ;# Core to die edge (um)
set STRIPE_P 30.0     ;# Lab 03: 15 / 30 / 60 um
set SKEW     0.080    ;# Lab 05: 0.020 / 0.080 / 0.150 ns

# Report/check commands: on error only warn and keep going (options differ between Innovus versions).
# The main steps (init, floorplan, place, CTS, route, file output) still stop on error.
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "WARNING: command \"$cmd\" failed: $msg" }
}
# Mode options: try the Innovus 21.1 name (-place_... style) first, then the Lab name.
# If both fail, Innovus keeps its default and only warns.
proc try_mode {new old} {
    if {[catch {uplevel 1 $new}]} { try_cmd $old }
}

# Init (Lab 02)
set init_gnd_net    $GND_NET
set init_pwr_net    $PWR_NET
set init_verilog    $NETLIST
set init_top_cell   $TOP
set init_lef_file   [concat [list $TECH_LEF $CELL_LEF] $SRAM_LEF]
set init_mmmc_file  $REPO/pnr/scripts/mmmc.view
init_design

globalNetConnect $PWR_NET -type pgpin -pin VDD -inst *
globalNetConnect $GND_NET -type pgpin -pin VSS -inst *
globalNetConnect $PWR_NET -type tiehi -inst *
globalNetConnect $GND_NET -type tielo -inst *

# Banned cells, set before any optimization. BUFX2 is double height (DONT_USE_CELLS) and
# CLKBUFX2 breaks the pin spacing rule (Lab 04). Banning CLKBUFX2 only before CTS let
# place_opt_design insert 1220 of them as data buffers on 29/10.
foreach c [concat $DONT_USE_CELLS $CTS_DONT_USE] { try_cmd {setDontUse $c true} }

if {$TOP eq "soc_top"} {
    # Fixed core size, 8 SRAM macros, pin plan and power plan (PD-02)
    source $REPO/pnr/scripts/soc_floorplan.tcl
} else {
    # Floorplan + pin (Lab 02)
    floorPlan -site $CORE_SITE -r 1.0 $UTIL $IO_GAP $IO_GAP $IO_GAP $IO_GAP
    editPin -pin {clk rst_n s_valid s_we s_addr* s_wstrb*} -edge 0 -spreadType SIDE -layer 3
    editPin -pin {s_wdata*}                                -edge 1 -spreadType SIDE -layer 2
    editPin -pin {s_rdata* s_ready irq}                    -edge 2 -spreadType SIDE -layer 3

    # Power plan (Lab 03)
    addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
            -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
            -width 2.0 -spacing 1.0 -offset 1.5
    addStripe -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
              -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
    addStripe -nets [list $PWR_NET $GND_NET] -layer Metal7 -direction horizontal \
              -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
    sroute -connect {corePin} -layerChangeRange {Metal1 Metal8} -nets [list $PWR_NET $GND_NET]
}
try_cmd {verifyGeometry -report $RPT/pdn_geometry.rpt}       ;# Must be 0 violations (Innovus 21.1 has no -type power)
saveDesign DBS/floorplan.enc

# Placement (Lab 04)
try_cmd  {setPlaceMode -fp false}
try_mode {setPlaceMode -place_global_cong_effort high}           {setPlaceMode -congestionEffort high}
try_mode {setPlaceMode -place_global_timing_effort medium}       {setPlaceMode -timingDriven true}
try_mode {setPlaceMode -place_detail_wire_length_opt_effort medium} {setPlaceMode -wireLenOptEffort medium}
place_opt_design
try_cmd {checkPlace $RPT/placement_check.rpt}                                  ;# 0 unplaced/overlap/off-grid
try_cmd {reportCongestion -overflow > $RPT/placement_congestion.rpt}           ;# overflow < 0.5%
try_cmd {timeDesign -preCTS -expandedViews -outDir $RPT/prects}
saveDesign DBS/placement.enc

# CTS (Lab 05). CTS_DONT_USE is already banned right after init_design.
try_cmd {set_ccopt_property buffer_cells     $CTS_BUFFERS}
try_cmd {set_ccopt_property inverter_cells   $CTS_INVERTERS}
try_cmd {set_ccopt_property target_skew      $SKEW}
try_cmd {set_ccopt_property target_max_trans 0.150}
try_cmd {setAnalysisMode -analysisType onChipVariation -cppr both}
# Clock wires at double width and double spacing (Lab 05). Innovus 21.1 uses add_ndr and a CCOpt route type.
try_mode {add_ndr -name CLK_2W2S -width_multiplier {Metal3:Metal7 2} -spacing_multiplier {Metal3:Metal7 2}} \
         {addNDR -name CLK_2W2S -width_multiplier {Metal3:Metal7 2} -spacing_multiplier {Metal3:Metal7 2}}
try_cmd {create_route_type -name clk_trunk -non_default_rule CLK_2W2S -bottom_preferred_layer Metal3 -top_preferred_layer Metal7}
try_cmd {set_ccopt_property route_type clk_trunk -net_type trunk}

create_ccopt_clock_tree_spec -file $OUT/ccopt.spec
source $OUT/ccopt.spec
ccopt_design
try_cmd {report_ccopt_clock_trees -file $RPT/cts_clock_trees.rpt}   ; # skew <= 80 ps, latency < 0.8 ns
try_cmd {report_ccopt_skew_groups -file $RPT/cts_skew_groups.rpt}
optDesign -postCTS
optDesign -postCTS -hold
try_cmd {timeDesign -postCTS       -outDir $RPT/postcts_setup}
try_cmd {timeDesign -postCTS -hold -outDir $RPT/postcts_hold}
saveDesign DBS/cts.enc

# Route
try_mode {setNanoRouteMode -route_with_timing_driven true -route_with_si_driven true} {setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true}
routeDesign
try_cmd {setDelayCalMode -SIAware true}
optDesign -postRoute -setup -hold
# Quick checks before filler, written to reports/pd_checks.rpt (see docs/pnr_soc_status.md):
# banned cells must be 0, macros must sit where soc_floorplan.tcl put them, and the standard
# cell density shows whether the core size is right.
proc pd_checks {file banned} {
    set fp [open $file w]
    puts $fp "Core box (um): [dbGet top.fPlan.coreBox]"
    puts $fp "Die box (um) : [dbGet top.fPlan.box]"
    foreach c $banned {
        puts $fp "$c instances: [llength [dbGet -e top.insts.cell.name $c]] (must be 0)"
    }
    set mac_area 0.0
    set std_area 0.0
    foreach inst [dbGet top.insts] {
        set a [expr {[dbGet $inst.box_sizex] * [dbGet $inst.box_sizey]}]
        if {[dbGet $inst.cell.baseClass] eq "block"} {
            set mac_area [expr {$mac_area + $a}]
            puts $fp "Macro [dbGet $inst.name] at [dbGet $inst.pt] [dbGet $inst.orient]"
        } else {
            set std_area [expr {$std_area + $a}]
        }
    }
    set core [lindex [dbGet top.fPlan.coreBox] 0]
    lassign $core cx0 cy0 cx1 cy1
    set core_area [expr {($cx1 - $cx0) * ($cy1 - $cy0)}]
    puts $fp [format "Standard cell area %.0f um2, macro area %.0f um2, core %.0f um2" \
                  $std_area $mac_area $core_area]
    puts $fp [format "Standard cell density outside macros: %.1f%%" \
                  [expr {100.0 * $std_area / ($core_area - $mac_area)}]]
    close $fp
}
try_cmd {pd_checks $RPT/pd_checks.rpt [concat $DONT_USE_CELLS $CTS_DONT_USE]}

try_cmd {addFiller -cell [dbGet [dbGet -p head.libCells.name FILL*].name] -prefix FILLER}
saveDesign DBS/route.enc

# Check and Report
try_cmd {verify_drc -report $RPT/drc.rpt}
try_cmd {verifyConnectivity -report $RPT/connectivity.rpt}
if {[catch {verifyProcessAntenna -reportfile $RPT/antenna.rpt}]} { try_cmd {verifyProcessAntenna -report $RPT/antenna.rpt} }
try_cmd {timeDesign -postRoute       -outDir $RPT/postroute_setup}
try_cmd {timeDesign -postRoute -hold -outDir $RPT/postroute_hold}
try_cmd {reportGateCount -outfile $RPT/area.rpt}
try_cmd {report_power -outfile $RPT/power.rpt}
try_cmd {summaryReport -outdir $RPT/summary}

# Output files for the next steps
saveNetlist $OUT/${TOP}_pnr.v                                 ; # LEC (Phuc), GLS (Hieu)
saveNetlist $OUT/${TOP}_pnr_pg.v -includePowerGround          ; # LVS
extractRC
try_cmd {rcOut -spef $OUT/${TOP}.spef -rc_corner rc_typ}      ; # Tempus (Phat), Power (Nguyen)
try_cmd {write_sdf -view av_setup $OUT/${TOP}.sdf}            ; # GLS with SDF (Hieu)
if {$GDS_MAP ne ""} {
    if {$CELL_GDS ne ""} {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -merge $CELL_GDS -units 2000 -mode ALL}
    } else {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -units 2000 -mode ALL}
    }
}

puts "Innovus done. Copy only the text reports in $RPT to appendix/pnr_${SUB}/,
      never the netlist, SPEF, SDF or GDS in $OUT."
exit
