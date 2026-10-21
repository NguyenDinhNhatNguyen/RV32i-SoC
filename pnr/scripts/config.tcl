# config.tcl - đường dẫn PDK dùng chung cho Genus và Innovus.
# Cấu trúc theo thư mục Lab: <PDK_DIR>/lib/*.lib, <PDK_DIR>/lef/gsclib045_*.lef
# Trên server, đặt biến môi trường PDK_DIR trỏ tới thư mục PDK_GPDK45 của Lab, hoặc sửa giá trị mặc định bên dưới.
# Không commit thư viện, chỉ commit đường dẫn.

if {[info exists ::env(PDK_DIR)]} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR $::env(HOME)/PDK_GPDK45   ;# bản copy của Lab nằm trong home mỗi người (HT-01, 21/10)
}

set LIB_DIR   $PDK_DIR/lib
set LIB_SLOW  slow_vdd1v0_basiccells.lib   ;# corner setup (1.0 V, 125 C) - tên như Lab 1
set LIB_FAST  fast_vdd1v0_basiccells.lib   ;# corner hold. HT-01 (21/10): PDK_GPDK45 của Lab chưa có file này
set TECH_LEF  $PDK_DIR/lef/gsclib045_tech.lef
set CELL_LEF  $PDK_DIR/lef/gsclib045_macro.lef
set QRC_TECH  $PDK_DIR/qrc/gpdk045.tch     ;# bỏ qua file captable/ vì đó là của công nghệ 28 nm
set GDS_MAP   $PDK_DIR/streamOut.map
set CELL_GDS  {}                           ;# GDS thư viện cell: HT-01 chưa thấy, để trống thì GDS chỉ có hình học của Innovus

# SRAM macro (cần khi chạy soc_top). HT-01 (21/10): sram_2k_macro 80 x 100 um, có LEF, .lib và .v nhưng chưa thấy GDS.
# Chạy accelerator thì để trống. Khi chạy soc_top điền:
#   SRAM_LEF $PDK_DIR/lef/sram_2k_macro.lef, SRAM_LIB_SLOW và SRAM_LIB_FAST $PDK_DIR/lib/sram_2k_macro.lib
set SRAM_LEF       {}
set SRAM_LIB_SLOW  {}
set SRAM_LIB_FAST  {}

set PWR_NET   VDD
set GND_NET   VSS
set CORE_SITE CoreSite

# Theo Lab 04: CLKBUFX2 có khoảng cách chân A tới blockage 0.035 um, vi phạm min spacing 0.06 um, nên cấm dùng khi CTS.
set CTS_DONT_USE  {CLKBUFX2}
set CTS_BUFFERS   {CLKBUFX3 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16}
set CTS_INVERTERS {CLKINVX3 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16}

# Thiếu thư viện fast thì tạm dùng slow cho cả hai corner để flow chạy được.
# Kết quả hold lúc đó không có giá trị, không đưa vào report.
if {![file exists $LIB_DIR/$LIB_FAST]} {
    puts "CANH BAO: khong thay $LIB_DIR/$LIB_FAST, tam dung $LIB_SLOW cho corner hold"
    set LIB_FAST $LIB_SLOW
}
if {$QRC_TECH ne "" && ![file exists $QRC_TECH]} { set QRC_TECH {} }
if {$GDS_MAP ne "" && ![file exists $GDS_MAP]} { set GDS_MAP {} }

foreach f [list $LIB_DIR/$LIB_SLOW $TECH_LEF $CELL_LEF] {
    if {![file exists $f]} { puts "CANH BAO: khong thay $f - sua pnr/scripts/config.tcl hoac dat PDK_DIR" }
}
