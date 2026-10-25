# config.tcl - PDK paths shared by Genus and Innovus.
# Lab folder layout: <PDK_DIR>/lib/*.lib, <PDK_DIR>/lef/gsclib045_*.lef
# On the server, point the PDK_DIR environment variable at the Lab PDK_GPDK45 folder, or edit
# the default below.
# Never commit libraries, only paths.

if {[info exists ::env(PDK_DIR)]} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR $::env(HOME)/PDK_GPDK45   ;# The Lab copy sits in each person's home (HT-01, 21/10)
}

set LIB_DIR   $PDK_DIR/lib
set LIB_SLOW  slow_vdd1v0_basiccells.lib   ;# Setup corner (1.0 V, 125 C), same name as Lab 1
set LIB_FAST  fast_vdd1v0_basicCells.lib   ;# Hold corner. Capital C, unlike the slow file (HT-01, 21/10)
set TECH_LEF  $PDK_DIR/lef/gsclib045_tech.lef
set CELL_LEF  $PDK_DIR/lef/gsclib045_macro.lef
set QRC_TECH  {}                           ;# The Lab qrc/gpdk045.tch is unreadable (IMPEXT-1211, 21/10) and captable/ is for 28 nm.
                                           # Empty: Innovus estimates RC from the tech LEF
set GDS_MAP   $PDK_DIR/streamOut.map
set CELL_GDS  {}                           ;# Cell library GDS: not found by HT-01. Empty means the GDS holds only Innovus geometry

# SRAM macro (needed for soc_top). HT-01 (21/10): sram_2k_macro 80 x 100 um with LEF, .lib and .v,
# no GDS (not required, lecturer 22/10).
# Leave empty for the accelerator. For soc_top set:
#   SRAM_LEF $PDK_DIR/lef/sram_2k_macro.lef, SRAM_LIB_SLOW and SRAM_LIB_FAST $PDK_DIR/lib/sram_2k_macro.lib
set SRAM_LEF       {}
set SRAM_LIB_SLOW  {}
set SRAM_LIB_FAST  {}

# Double-height cells (SITE CoreSiteDouble) in gsclib045: BUFX2 and the low-power cells
# (switch, isolation, level shifter). The floorplan has only CoreSite rows, so BUFX2 is banned in
# both Genus and Innovus, otherwise Innovus places them illegally (IMPSP-365, 368 cells on 21/10).
set DONT_USE_CELLS {BUFX2}

set PWR_NET   VDD
set GND_NET   VSS
set CORE_SITE CoreSite

# From Lab 04: CLKBUFX2 has 0.035 um from pin A to a blockage, below the 0.06 um min spacing,
# so it is banned during CTS.
set CTS_DONT_USE  {CLKBUFX2}
set CTS_BUFFERS   {CLKBUFX3 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16}
set CTS_INVERTERS {CLKINVX3 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16}

# Without the fast library, use slow for both corners so the flow still runs.
# Hold results are then meaningless and must not go into the report.
if {![file exists $LIB_DIR/$LIB_FAST]} {
    puts "WARNING: cannot find $LIB_DIR/$LIB_FAST, using $LIB_SLOW for the hold corner"
    set LIB_FAST $LIB_SLOW
}
if {$QRC_TECH ne "" && ![file exists $QRC_TECH]} { set QRC_TECH {} }
if {$GDS_MAP ne "" && ![file exists $GDS_MAP]} { set GDS_MAP {} }

foreach f [list $LIB_DIR/$LIB_SLOW $TECH_LEF $CELL_LEF] {
    if {![file exists $f]} { puts "WARNING: cannot find $f - edit pnr/scripts/config.tcl or set PDK_DIR" }
}
