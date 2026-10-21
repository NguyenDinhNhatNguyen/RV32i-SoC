# run_all.tcl - Innovus chạy thử end-to-end trên accelerator (PD-01).
# Lệnh viết theo cú pháp của Lab 02-05 (floorPlan, addRing, ccopt_design...).
# Chạy từ gốc repo trên server (sau make synth-accel): make pnr-accel
# Mỗi bước lưu database DBS/<bước>.enc như trong Lab để restoreDesign khi debug.
# Phần route/signoff (Route, Check and Report, Xuất file) chưa có trong Lab 05: đối chiếu khi học tới Lab route.

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

# Lệnh báo cáo/kiểm tra: lỗi thì chỉ cảnh báo, không dừng flow (tuỳ chọn khác nhau giữa các bản Innovus).
# Các bước chính (init, floorplan, place, CTS, route, lưu file) vẫn dừng ngay nếu lỗi.
proc try_cmd {cmd} {
    if {[catch {uplevel 1 $cmd} msg]} { puts "CANH BAO: lenh \"$cmd\" loi: $msg" }
}
# Tuỳ chọn mode: thử tên mới của Innovus 21.1 (dạng -place_...), không được thì tên cũ như Lab.
# Sai cả hai thì Innovus dùng mặc định, chỉ cảnh báo.
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

# Floorplan + pin (Lab 02)
floorPlan -site $CORE_SITE -r 1.0 $UTIL $IO_GAP $IO_GAP $IO_GAP $IO_GAP
# gsclib045 có cell cao gấp đôi (SITE CoreSiteDouble). Thiếu hàng cho site này thì
# Innovus báo IMPSP-365 và đặt sai vị trí các cell đó (368 TechSite violation ngày 21/10).
try_cmd {createRow -site CoreSiteDouble}
editPin -pin {clk rst_n s_valid s_we s_addr* s_wstrb*} -edge 0 -spreadType SIDE -layer 3
editPin -pin {s_wdata*}                                -edge 1 -spreadType SIDE -layer 2
editPin -pin {s_rdata* s_ready irq}                    -edge 2 -spreadType SIDE -layer 3
# Khi có SRAM (soc_top): placeInstance <macro> x y R0 -fixed và addHaloToBlock 5 5 5 5 <macro>

# Power plan (Lab 03)
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
        -width 2.0 -spacing 1.0 -offset 1.5
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
          -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal7 -direction horizontal \
          -width 1.5 -spacing 1.0 -set_to_set_distance $STRIPE_P -start_offset 10.0
sroute -connect {corePin} -layerChangeRange {Metal1 Metal8} -nets [list $PWR_NET $GND_NET]
try_cmd {verifyGeometry -report $RPT/pdn_geometry.rpt}       ;# phải 0 violation (Innovus 21.1 không có -type power)
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

# CTS (Lab 05)
foreach c $CTS_DONT_USE { try_cmd {setDontUse $c true} }
try_cmd {set_ccopt_property buffer_cells     $CTS_BUFFERS}
try_cmd {set_ccopt_property inverter_cells   $CTS_INVERTERS}
try_cmd {set_ccopt_property target_skew      $SKEW}
try_cmd {set_ccopt_property target_max_trans 0.150}
try_cmd {setAnalysisMode -analysisType onChipVariation -cppr both}
# Dây clock rộng gấp đôi, cách gấp đôi (Lab 05). Innovus 21.1 dùng add_ndr và route type của CCOpt.
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

# Xuất file cho bước sau
saveNetlist $OUT/${TOP}_pnr.v                                 ; # LEC (Phúc), GLS (Hiếu)
saveNetlist $OUT/${TOP}_pnr_pg.v -includePowerGround          ; # LVS
extractRC
try_cmd {rcOut -spef $OUT/${TOP}.spef -rc_corner rc_typ}      ; # Tempus (Phát), Power (Nguyên)
try_cmd {write_sdf -view av_setup $OUT/${TOP}.sdf}            ; # GLS có SDF (Hiếu)
if {$GDS_MAP ne ""} {
    if {$CELL_GDS ne ""} {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -merge $CELL_GDS -units 2000 -mode ALL}
    } else {
        try_cmd {streamOut $OUT/${TOP}.gds -mapFile $GDS_MAP -units 2000 -mode ALL}
    }
}

puts "Innovus xong. Copy $RPT vào appendix/pnr_accel/ cho phụ lục."
exit
