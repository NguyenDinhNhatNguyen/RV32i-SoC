# synth_nangate.tcl - trial Yosys synthesis with the open Nangate45 library (home flow),
# FOR TIMING TRENDS ONLY. No GPDK45. Official numbers come from Genus at school.
# The output netlist is read by OpenSTA through syn/yosys/sta_nangate.tcl.
# Run: yosys -c syn/yosys/synth_nangate.tcl, parameters through environment variables:
#   YS_TOP     module top
#   YS_SRCS    Verilog file list
#   YS_INC     include folders (may be empty)
#   YS_PARAMS  "NAME=VALUE ..." (may be empty)
#   YS_OUT     output folder
#   YS_LIB     Nangate45 liberty file (downloaded by scripts/get_nangate45.sh, never committed)
#   YS_ABC_D   abc delay target in ps (default 2000)
yosys -import

set top    $::env(YS_TOP)
set out    $::env(YS_OUT)
set lib    $::env(YS_LIB)
set inc    [expr {[info exists ::env(YS_INC)] ? $::env(YS_INC) : ""}]
set params [expr {[info exists ::env(YS_PARAMS)] ? $::env(YS_PARAMS) : ""}]
set abc_d  [expr {[info exists ::env(YS_ABC_D)] ? $::env(YS_ABC_D) : 2000}]
file mkdir $out

set incflags ""
foreach d $inc { append incflags " -I$d" }
foreach f $::env(YS_SRCS) {
    eval read_verilog -defer $incflags $f
}
set chp ""
foreach kv $params {
    lassign [split $kv =] k v
    append chp " -set $k $v"
}
if {$chp ne ""} { eval chparam $chp $top }

# Like synth -flatten, except the fine step maps $lcu (carry of add, subtract, compare)
# to Kogge-Stone instead of the default ripple, closer to the adders Genus picks.
set ks [file join [file dirname [info script]] lcu_kogge_stone.v]
synth -top $top -flatten -run :fine
opt -fast -full
memory_map
opt -full
techmap -autoproc -map +/techmap.v -map $ks
opt -fast
abc -fast
opt -fast
synth -run check:
# Count enable flops before mapping (Nangate has no enable flop, and dfflibmap
# turns enables into muxes, so count them here)
tee -o $out/stat_generic.txt stat
# Flops to DFFR/DFFS/DFF cells, logic to standard cells for the delay target.
# The default Yosys 0.33 abc script inserts no buffers and does not resize cells,
# so high-fanout nets get absurd delays. Add buffer, upsize and dnsize.
dfflibmap -liberty $lib
set abc_scr "+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,-D,$abc_d;&put;buffer,-p;upsize,-D,$abc_d;dnsize,-D,$abc_d;stime,-p"
abc -liberty $lib -D $abc_d -script $abc_scr
opt_clean -purge
hilomap -singleton -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
setundef -zero
splitnets -ports
opt_clean -purge
tee -o $out/stat.txt stat -liberty $lib
write_verilog -noattr -noexpr -nohex -nodec $out/${top}_nangate.v
