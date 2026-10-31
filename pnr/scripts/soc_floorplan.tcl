# soc_floorplan.tcl - floorplan, SRAM macro placement, pin plan and power plan for soc_top (PD-02).
# Called by run_all.tcl when TOP=soc_top (make pnr-soc), after init_design and globalNetConnect.
# Numbers and reasoning: docs/pd02_floorplan.md.
#
# Layout: 4 IMEM macros in one row at the top edge, 4 DMEM macros at the bottom edge,
# logic in the middle band.
# Signal pins on the left and right edges (the top and bottom edges hold macros).
# Needs: try_cmd (as in run_all.tcl) and the config.tcl variables (PWR_NET, GND_NET, CORE_SITE).

# ---- Parameters ----------------------------------------------------------------------
# Core size from estimate_die.py with the standard cell area only (macros are added by the
# script): 53 408 um2 (Genus keep-flop netlist 30/10, total 117 408 um2 minus 8 x 8000 um2 of
# macro) at 70% density. The 29/10 run used 524 x 523 um because the total area with macros
# was given as --std-area, which counted the macros twice.
set CORE_W     394.0      ;# um
set CORE_H     395.0
set IO_GAP     15.0       ;# Core to die edge, room for the power ring
set MAC_W      80.0       ;# sram_2k_macro (HT-01)
set MAC_H      100.0
set HALO       5.0
set MAC_GAP    [expr {2*$HALO}]   ;# Gap between 2 neighbouring macros = 2 halos
# Orientation: macro signal pins must face the logic band in the middle. The defaults assume
# pins on the top edge of the macro (bottom row R0, top row mirrored on X). The block below
# reads the real pin edge from the LEF and overrides them.
set IMEM_ORIENT MX
set DMEM_ORIENT R0
# Metal layers of the ring around each macro: pick from the macro VDD/VSS pin layers, which
# are printed below and in scripts/macro_info.sh section 2
set BLK_RING_H Metal6
set BLK_RING_V Metal5

# ---- Macro orientation from the LEF -------------------------------------------------
# Returns bottom, top or side: where the signal pins of the macro sit in the R0 view,
# from the average y of their shapes.
proc macro_pin_side {cell_name} {
    set cell [dbGet -p head.libCells.name $cell_name]
    if {$cell eq "" || $cell eq "0x0"} { return unknown }
    set h [dbGet $cell.size_y]
    set ys {}
    foreach r [dbGet $cell.terms.pins.allShapes.shapes.rect] {
        lassign $r x0 y0 x1 y1
        lappend ys [expr {($y0 + $y1) / 2.0}]
    }
    if {[llength $ys] == 0} { return unknown }
    set avg [expr {[tcl::mathop::+ {*}$ys] / [llength $ys]}]
    if {$avg < $h / 3.0} { return bottom }
    if {$avg > 2.0 * $h / 3.0} { return top }
    return side
}
if {[catch {macro_pin_side sram_2k_macro} pin_side]} { set pin_side unknown }
switch -- $pin_side {
    bottom { set IMEM_ORIENT R0 ; set DMEM_ORIENT MX }
    top    { set IMEM_ORIENT MX ; set DMEM_ORIENT R0 }
}
puts "PD-02: macro signal pins on the $pin_side edge, IMEM $IMEM_ORIENT, DMEM $DMEM_ORIENT"
set mac_cell [dbGet -p head.libCells.name sram_2k_macro]
if {![catch {dbGet $mac_cell.pgTerms.pins.allShapes.layer.name} pg]} {
    puts "PD-02: macro VDD/VSS pin layers [lsort -unique $pg], ring layers $BLK_RING_H/$BLK_RING_V"
}

# ---- Floorplan with a fixed core size ------------------------------------------------
floorPlan -site $CORE_SITE -s $CORE_W $CORE_H $IO_GAP $IO_GAP $IO_GAP $IO_GAP

# ---- Macro placement -----------------------------------------------------------------
# Find macros by cell name, split IMEM and DMEM by instance name (u_imem, u_dmem in soc_top)
set macros [lsort [dbGet [dbGet -p2 top.insts.cell.name sram_2k_macro].name]]
set imem {}
set dmem {}
foreach m $macros {
    if {[string match *u_imem* $m]} {
        lappend imem $m
    } elseif {[string match *u_dmem* $m]} {
        lappend dmem $m
    }
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
# run_all.tcl runs verifyGeometry right after this file
