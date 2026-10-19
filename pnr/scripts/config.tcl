# config.tcl - đường dẫn thư viện GPDK45 trên server, dùng chung cho Genus và Innovus.
# ĐIỀN LẠI theo file appendix/server_check/server_check_*.txt hoặc theo script Lab 3/4.
# Có thể đặt biến môi trường GPDK45_DIR thay vì sửa file.
# Không commit thư viện, chỉ commit đường dẫn.

if {[info exists ::env(GPDK45_DIR)]} {
    set GPDK45_DIR $::env(GPDK45_DIR)
} else {
    set GPDK45_DIR /CHUA_DIEN/gsclib045        ;# TODO: điền sau khi chạy check_server.sh
}

set LIB_DIR   $GPDK45_DIR/timing
set LIB_SLOW  slow_vdd1v0_basicCells.lib      ;# corner setup
set LIB_FAST  fast_vdd1v0_basicCells.lib      ;# corner hold
set TECH_LEF  $GPDK45_DIR/lef/gsclib045_tech.lef
set CELL_LEF  $GPDK45_DIR/lef/gsclib045_macro.lef
set QRC_TECH  $GPDK45_DIR/qrc/qx/gpdk045.tch
set GDS_MAP   $GPDK45_DIR/streamOut.map        ;# TODO: kiểm tra tên file map
set CELL_GDS  $GPDK45_DIR/gds/gsclib045.gds    ;# TODO: kiểm tra

# SRAM macro (dùng khi chạy soc_top, chưa cần cho accelerator)
set SRAM_LEF  {}                               ;# TODO
set SRAM_LIB_SLOW {}
set SRAM_LIB_FAST {}

# Tên net nguồn và site của thư viện
set PWR_NET   VDD
set GND_NET   VSS
set CORE_SITE CoreSite

# Cell không dùng khi CTS (bài học Lab)
set CTS_DONT_USE {CLKBUFX2}

foreach f [list $LIB_DIR/$LIB_SLOW $LIB_DIR/$LIB_FAST $TECH_LEF $CELL_LEF] {
    if {![file exists $f]} { puts "CANH BAO: khong thay $f - sua pnr/scripts/config.tcl" }
}
