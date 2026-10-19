# run_all.tcl - Innovus chạy thử end-to-end trên accelerator (PD-01).
# Chạy: make pnr-accel (sau make synth-accel). Kết quả ở pnr/out_accel/.
# Mỗi bước lưu database để mở lại bằng restoreDesign khi cần debug.
# Lệnh viết theo kiểu Innovus của Lab; nếu phiên bản trên server báo lệnh cũ,
# đối chiếu với script Lab 4 và sửa tại đây.

set REPO [file normalize [file dirname [info script]]/../..]
source $REPO/pnr/scripts/config.tcl

set TOP        accel_wrapper
set NETLIST    $REPO/syn/out_accel/${TOP}.v
set DESIGN_SDC $REPO/syn/out_accel/${TOP}.sdc
set OUT        $REPO/pnr/out_accel
set RPT        $OUT/reports
file mkdir $OUT $RPT

set UTIL   0.65      ;# mật độ core ban đầu; PD-07 quét 0.55 / 0.65 / 0.75
set MARGIN 10.0      ;# khoảng core tới biên die (um), chỗ cho power ring

# ----------------------------------------------------------- 1. khởi tạo
set_db init_power_nets  $PWR_NET
set_db init_ground_nets $GND_NET
read_mmmc     $REPO/pnr/scripts/mmmc.tcl
read_physical -lef [concat [list $TECH_LEF $CELL_LEF] $SRAM_LEF]
read_netlist  $NETLIST -top $TOP
init_design

connect_global_net $PWR_NET -type pg_pin -pin_base_name VDD -inst_base_name *
connect_global_net $GND_NET -type pg_pin -pin_base_name VSS -inst_base_name *

# ----------------------------------------------------------- 2. floorplan
create_floorplan -site $CORE_SITE -core_density_size 1.0 $UTIL $MARGIN $MARGIN $MARGIN $MARGIN
# Khi có SRAM: đặt macro sát cạnh die, thêm halo
# place_inst <tên_macro> <x> <y> R0 -fixed ; create_place_halo -insts <tên_macro> -halo_deltas 5 5 5 5
write_db $OUT/01_floorplan.db

# ----------------------------------------------------------- 3. power plan
add_rings -nets [list $PWR_NET $GND_NET] -type core_rings -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} \
          -width 2.0 -spacing 1.0 -offset 1.0
add_stripes -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
            -width 1.0 -spacing 1.0 -set_to_set_distance 40
route_special -connect {core_pin} -nets [list $PWR_NET $GND_NET]
write_db $OUT/02_power.db

# ----------------------------------------------------------- 4. placement
place_opt_design
report_timing -max_paths 20 > $RPT/place_setup.rpt
write_db $OUT/03_place.db

# ----------------------------------------------------------- 5. CTS
foreach c $CTS_DONT_USE { set_db [get_db lib_cells */$c] .dont_use true }   ;# bài học Lab
ccopt_design
opt_design -post_cts -hold
report_ccopt_clock_trees > $RPT/cts_tree.rpt
report_timing -max_paths 20             > $RPT/cts_setup.rpt
report_timing -max_paths 20 -early      > $RPT/cts_hold.rpt
write_db $OUT/04_cts.db

# ----------------------------------------------------------- 6. route
route_design
opt_design -post_route -setup -hold
add_fillers -base_cells [get_db [get_db lib_cells FILL*] .base_name]
write_db $OUT/05_route.db

# ----------------------------------------------------------- 7. kiểm tra + báo cáo
check_drc            -out_file $RPT/drc.rpt
check_connectivity   -out_file $RPT/connectivity.rpt
time_design -post_route        -report_dir $RPT/timing_setup
time_design -post_route -hold  -report_dir $RPT/timing_hold
report_area          > $RPT/area.rpt
report_power         > $RPT/power.rpt
report_summary       -out_dir $RPT/summary

# ----------------------------------------------------------- 8. xuất file cho bước sau
write_netlist  $OUT/${TOP}_pnr.v                    ;# LEC (Phúc), GLS (Hiếu)
write_netlist  $OUT/${TOP}_pnr_pg.v -include_pg_ports  ;# LVS
extract_rc
write_parasitics -spef_file $OUT/${TOP}.spef        ;# Tempus (Phát), power (Nguyên)
write_sdf      $OUT/${TOP}.sdf                      ;# GLS có SDF (Hiếu)
write_stream   $OUT/${TOP}.gds -map_file $GDS_MAP -merge [list $CELL_GDS]

puts "Innovus xong. Copy reports/ vào appendix/pnr_accel/ cho phụ lục."
exit
