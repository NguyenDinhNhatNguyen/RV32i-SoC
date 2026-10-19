# config.tcl - đường dẫn PDK dùng chung cho Genus và Innovus.
# Cấu trúc theo thư mục Lab: <PDK_DIR>/lib/*.lib, <PDK_DIR>/lef/gsclib045_*.lef
# Trên server, đặt biến môi trường PDK_DIR trỏ tới thư mục PDK_GPDK45 của Lab,
# hoặc sửa giá trị mặc định bên dưới. Không commit thư viện, chỉ commit đường dẫn.

if {[info exists ::env(PDK_DIR)]} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR /CHUA_DIEN/PDK_GPDK45      ;# TODO: điền đường dẫn tuyệt đối tới PDK_GPDK45 của Lab
}

set LIB_DIR   $PDK_DIR/lib
set LIB_SLOW  slow_vdd1v0_basiccells.lib   ;# corner setup (1.0 V, 125 C) - tên như Lab 1
set LIB_FAST  fast_vdd1v0_basiccells.lib   ;# corner hold - TODO: kiểm tra tên file thật trong lib/
set TECH_LEF  $PDK_DIR/lef/gsclib045_tech.lef
set CELL_LEF  $PDK_DIR/lef/gsclib045_macro.lef
set QRC_TECH  {}                           ;# TODO: file qrcTech/capTable nếu có (để trống thì Innovus dùng ước lượng)
set GDS_MAP   {}                           ;# TODO: streamOut map cho bước xuất GDS
set CELL_GDS  {}                           ;# TODO: GDS thư viện cell

# SRAM macro (cần khi chạy soc_top)
set SRAM_LEF       {}                      ;# TODO
set SRAM_LIB_SLOW  {}
set SRAM_LIB_FAST  {}

set PWR_NET   VDD
set GND_NET   VSS
set CORE_SITE CoreSite

# Theo Lab 04: CLKBUFX2 có khoảng cách chân A tới blockage 0.035 um,
# vi phạm min spacing 0.06 um, nên cấm dùng khi CTS.
set CTS_DONT_USE  {CLKBUFX2}
set CTS_BUFFERS   {CLKBUFX3 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16}
set CTS_INVERTERS {CLKINVX3 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16}

foreach f [list $LIB_DIR/$LIB_SLOW $LIB_DIR/$LIB_FAST $TECH_LEF $CELL_LEF] {
    if {![file exists $f]} { puts "CANH BAO: khong thay $f - sua pnr/scripts/config.tcl hoac dat PDK_DIR" }
}
