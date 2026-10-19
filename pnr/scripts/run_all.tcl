# run_all.tcl - Innovus chạy thử end-to-end trên accelerator (PD-01).
# Lệnh viết theo cú pháp của Lab 02-05 (floorPlan, addRing, ccopt_design...).
# Chạy từ gốc repo trên server (sau make synth-accel): make pnr-accel
# Mỗi bước lưu database DBS/<bước>.enc như trong Lab để restoreDesign khi debug.
# Phần route/signoff (bước 6-8) chưa có trong Lab 05: đối chiếu khi học tới Lab route.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP        accel_wrapper
set NETLIST    $REPO/syn/out_accel/${TOP}_netlist.v
set DESIGN_SDC $REPO/syn/out_accel/${TOP}_synth.sdc
set OUT        $REPO/pnr/out_accel
set RPT        $OUT/reports
file mkdir $OUT $RPT DBS

# Tham số quét cho thử thách PPA (Lab 02-04)
set UTIL     0.70     ;# Lab 02: 0.55 / 0.70 / 0.85
set IO_GAP   15       ;# khoảng core tới biên die (um)
set STRIPE_P 30.0     ;# Lab 03: 15 / 30 / 60 um
set SKEW     0.080    ;# Lab 05: 0.020 / 0.080 / 0.150 ns

# ---------------------------------------------------------------- 1. init (Lab 02)
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

# ---------------------------------------------------------------- 2. floorplan + pin (Lab 02)
floorPlan -site $CORE_SITE -r 1.0 $UTIL $IO_GAP $IO_GAP $IO_GAP $IO_GAP
editPin -pin {clk rst_n s_valid s_we s_addr* s_wstrb*} -edge 0 -spreadType SIDE -layer 3
editPin -pin {s_wdata*}                                -edge 1 -spreadType SIDE -layer 2
editPin -pin {s_rdata* s_ready irq}                    -edge 2 -spreadType SIDE -layer 3
# Khi có SRAM (soc_top): placeInstance <macro> x y R0 -fixed ; addHaloToBlock 5 5 5 5 <macro>

# ---------------------------------------------------------------- 3. power plan (Lab 03)
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
        -width 2.0 -spacing 1.0 -offset 1.5
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
          -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal7 -direction horizontal \
          -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
sroute -connect {corePin} -layerChangeRange {Metal1 Metal8} -nets [list $PWR_NET $GND_NET]
verifyGeometry -type power -report $RPT/pdn_geometry.rpt     ;# phải 0 violation
saveDesign DBS/floorplan.enc

# ---------------------------------------------------------------- 4. placement (Lab 04)
setPlaceMode -fp false
setPlaceMode -congestionEffort high
setPlaceMode -timingDriven true
setPlaceMode -wireLenOptEffort medium
place_opt_design
checkPlace -verbose                          > $RPT/placement_check.rpt       ;# 0 unplaced/overlap/off-grid
checkCongestion -detailed                    > $RPT/placement_congestion.rpt  ;# overflow < 0.5%
timeDesign -preCTS -expandedViews -outDir $RPT/prects
saveDesign DBS/placement.enc

# ---------------------------------------------------------------- 5. CTS (Lab 05)
foreach c $CTS_DONT_USE { setDontUse $c true }
set_ccopt_property buffer_cells     $CTS_BUFFERS
set_ccopt_property inverter_cells   $CTS_INVERTERS
set_ccopt_property target_skew      $SKEW
set_ccopt_property target_max_trans 0.150
setAnalysisMode -analysisType onChipVariation -cppr both
addNDR -name CLK_2W2S -width_multiplier {Metal3:Metal7 2} -spacing_multiplier {Metal3:Metal7 2}
setAttribute -net clk -non_default_rule CLK_2W2S

create_ccopt_clock_tree_spec -file $OUT/ccopt.spec
source $OUT/ccopt.spec
ccopt_design
report_ccopt_clock_trees -file $RPT/cts_clock_trees.rpt   ;# skew <= 80 ps, latency < 0.8 ns
report_ccopt_skew_groups -file $RPT/cts_skew_groups.rpt
optDesign -postCTS
optDesign -postCTS -hold
timeDesign -postCTS       -outDir $RPT/postcts_setup
timeDesign -postCTS -hold -outDir $RPT/postcts_hold
saveDesign DBS/cts.enc

# ---------------------------------------------------------------- 6. route
setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true
routeDesign
setDelayCalMode -SIAware true
optDesign -postRoute -setup -hold
addFiller -cell [dbGet [dbGet -p head.libCells.name FILL*].name] -prefix FILLER
saveDesign DBS/route.enc

# ---------------------------------------------------------------- 7. kiểm tra + báo cáo
verify_drc          -report $RPT/drc.rpt
verifyConnectivity  -report $RPT/connectivity.rpt
verifyProcessAntenna -report $RPT/antenna.rpt
timeDesign -postRoute       -outDir $RPT/postroute_setup
timeDesign -postRoute -hold -outDir $RPT/postroute_hold
report_area  > $RPT/area.rpt
report_power -outfile $RPT/power.rpt
summaryReport -outdir $RPT/summary

# ---------------------------------------------------------------- 8. xuất file cho bước sau
saveNetlist $OUT/${TOP}_pnr.v                                 ;# LEC (Phúc), GLS (Hiếu)
saveNetlist $OUT/${TOP}_pnr_pg.v -includePowerGround          ;# LVS
extractRC
rcOut -spef $OUT/${TOP}.spef -rc_corner rc_typ                ;# Tempus (Phát), power (Nguyên)
write_sdf -view av_setup $OUT/${TOP}.sdf                      ;# GLS có SDF (Hiếu)
if {$GDS_MAP ne ""} {
    streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -merge $CELL_GDS -units 2000 -mode ALL
}

puts "Innovus xong. Copy $RPT vào appendix/pnr_accel/ cho phụ lục."
exit
