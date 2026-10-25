# soc_floorplan.tcl - floorplan, đặt SRAM macro, pin plan, power plan cho soc_top (PD-02).
# Source sau init_design và globalNetConnect, trước placement (PD-03 sẽ gọi từ script chạy SoC).
# Số liệu và lý do chọn: docs/pd02_floorplan.md. CHƯA CHẠY TRÊN SERVER: kiểm lần đầu ở PD-03.
#
# Bố trí: 4 macro IMEM xếp một hàng sát cạnh trên, 4 macro DMEM sát cạnh dưới, logic ở dải giữa.
# Chân tín hiệu ở cạnh trái và phải (cạnh trên, dưới đã có macro).
# Cần có sẵn: try_cmd (như run_all.tcl), các biến của config.tcl (PWR_NET, GND_NET, CORE_SITE).

# ---- Tham số -------------------------------------------------------------------------
set CORE_W     391.0      ;# µm, estimate_die.py với diện tích an toàn 51 714 µm², mật độ 70%
set CORE_H     392.0
set IO_GAP     15.0       ;# core tới biên die, chỗ cho power ring
set MAC_W      80.0       ;# sram_2k_macro (HT-01)
set MAC_H      100.0
set HALO       5.0
set MAC_GAP    [expr {2*$HALO}]   ;# khe giữa 2 macro cạnh nhau = 2 halo
# Hướng đặt: chân của macro phải quay vào dải logic ở giữa. Chọn lại theo cạnh có chân
# trong output của scripts/macro_info.sh. Hàng dưới R0, hàng trên lật trục X (MX).
set IMEM_ORIENT MX
set DMEM_ORIENT R0
# Lớp kim loại của ring quanh macro: chọn theo lớp chân VDD/VSS của macro (macro_info.sh mục 2)
set BLK_RING_H Metal6
set BLK_RING_V Metal5

# ---- Floorplan theo kích thước core cố định -------------------------------------------
floorPlan -site $CORE_SITE -s $CORE_W $CORE_H $IO_GAP $IO_GAP $IO_GAP $IO_GAP

# ---- Đặt macro ------------------------------------------------------------------------
# Tìm macro theo tên cell, tách IMEM và DMEM theo tên instance (u_imem, u_dmem trong soc_top)
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
try_cmd {cutRow}            ;# bỏ hàng cell chuẩn nằm dưới macro và halo

# ---- Pin plan -------------------------------------------------------------------------
# Trái (edge 0): clock, reset, UART, GPIO vào. Phải (edge 2): GPIO ra và output enable.
editPin -pin {clk rst_n uart_rx uart_tx gpio_i*} -edge 0 -spreadType CENTER -spacing 4 -layer 3
editPin -pin {gpio_o* gpio_oe*}                  -edge 2 -spreadType CENTER -spacing 4 -layer 3

# ---- Power plan -----------------------------------------------------------------------
# Ring lõi và stripe như run_all.tcl (đã chạy được trên Innovus 21.1 ngày 21/10)
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer {top Metal8 bottom Metal8 left Metal7 right Metal7} \
        -width 2.0 -spacing 1.0 -offset 1.5
# Ring quanh từng macro, rồi nối chân nguồn của macro
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
