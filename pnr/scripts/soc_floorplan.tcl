# soc_floorplan.tcl - floorplan, SRAM macro placement, pin plan and power plan for soc_top (PD-02).
# Source after init_design and globalNetConnect, before placement (PD-03 will call it from the SoC script).
# Numbers and reasoning: docs/pd02_floorplan.md. NOT RUN ON THE SERVER YET: first check in PD-03.
#
# Layout: 4 IMEM macros in one row at the top edge, 4 DMEM macros at the bottom edge, logic in the middle band.
# Signal pins on the left and right edges (the top and bottom edges hold macros).
# Needs: try_cmd (as in run_all.tcl) and the config.tcl variables (PWR_NET, GND_NET, CORE_SITE).

# ---- Parameters ----------------------------------------------------------------------
set CORE_W     391.0      ;# um, estimate_die.py with the safe area 51 714 um2 at 70% density
set CORE_H     392.0
set IO_GAP     15.0       ;# Core to die edge, room for the power ring
set MAC_W      80.0       ;# sram_2k_macro (HT-01)
set MAC_H      100.0
set HALO       5.0
set MAC_GAP    [expr {2*$HALO}]   ;# Gap between 2 neighbouring macros = 2 halos
# Orientation: macro pins must face the logic band in the middle. Pick again from the pin edge
# in the scripts/macro_info.sh output. Bottom row R0, top row mirrored on X (MX).
set IMEM_ORIENT MX
set DMEM_ORIENT R0
# Metal layers of the ring around each macro: pick from the macro VDD/VSS pin layers (macro_info.sh section 2)
set BLK_RING_H Metal6
set BLK_RING_V Metal5

# ---- Floorplan with a fixed core size ------------------------------------------------
floorPlan -site $CORE_SITE -s $CORE_W $CORE_H $IO_GAP $IO_GAP $IO_GAP $IO_GAP

# ---- Macro placement -----------------------------------------------------------------
# Find macros by cell name, split IMEM and DMEM by instance name (u_imem, u_dmem in soc_top)
set macros [lsort [dbGet [dbGet -p2 top.insts.cell.name sram_2k_macro].name]]
set imem {}
set dmem {}
foreach m $macros {
    if {[string match *u_imem* $m]} { lappend imem $m } elseif {[string match *u_dmem* $m]} { lappend dmem $m }
}
puts "PD-02: [llength $macros] macro, IMEM [llength $imem], DMEM [llength $dmem]"

set core [lindex [dbGet top.fPlan.coreBox] 0]
lassign $core cx0 cy0 cx1 cy1
proc place_row {insts y orient} {
    upvar cx0 cx0 HALO HALO MAC_W MAC_W MAC_GAP MAC_GAP
    set x [expr {$cx0 + $HALO}]
    foreach m $insts {
        placeInstance $m $x $y $orient -fixed
        set x [expr {$x + $MAC_W + $MAC_GAP}]
    }
}
place_row $dmem [expr {$cy0 + $HALO}]           $DMEM_ORIENT
place_row $imem [expr {$cy1 - $HALO - $MAC_H}]  $IMEM_ORIENT

foreach m $macros { try_cmd {addHaloToBlock $HALO $HALO $HALO $HALO $m} }
try_cmd {cutRow}            ;# Remove standard cell rows under the macros and halos

# ---- Pin plan -------------------------------------------------------------------------
# Left (edge 0): clock, reset, UART, GPIO inputs. Right (edge 2): GPIO outputs and output enables.
editPin -pin {clk rst_n uart_rx uart_tx gpio_i*} -edge 0 -spreadType CENTER -spacing 4 -layer 3
editPin -pin {gpio_o* gpio_oe*}                  -edge 2 -spreadType CENTER -spacing 4 -layer 3

# ---- Power plan -----------------------------------------------------------------------
# Core ring and stripes as in run_all.tcl (ran on Innovus 21.1 on 21/10)
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
        -width 2.0 -spacing 1.0 -offset 1.5
# A ring around each macro, then connect the macro power pins
try_cmd {addRing -nets [list $PWR_NET $GND_NET] -type block_rings -around each_block \
         -layer [list top $BLK_RING_H bottom $BLK_RING_H left $BLK_RING_V right $BLK_RING_V] \
         -width 1.0 -spacing 0.5 -offset 1.0}
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal8 -direction vertical \
          -width 1.5 -spacing 1.0 -set_to_set_distance 30.0 -start_offset 10.0
addStripe -nets [list $PWR_NET $GND_NET] -layer Metal7 -direction horizontal \
          -width 1.5 -spacing 1.0 -set_to_set_distance 30.0 -start_offset 10.0
try_cmd {sroute -connect {blockPin} -nets [list $PWR_NET $GND_NET] -blockPinTarget {nearestTarget}}
sroute -connect {corePin} -layerChangeRange {Metal1 Metal8} -nets [list $PWR_NET $GND_NET]
try_cmd {verifyGeometry}
