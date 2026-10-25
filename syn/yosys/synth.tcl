# synth.tcl - trial synthesis with Yosys (home flow), FOR TRENDS ONLY.
# Maps to Yosys generic gates, with no GPDK45 library and no timing
# constraints. Cell counts and logic depth are not comparable with Genus.
# Run: yosys -c syn/yosys/synth.tcl, parameters through environment variables:
#   YS_TOP     module top
#   YS_SRCS    Verilog file list
#   YS_INC     include folders (may be empty)
#   YS_PARAMS  "NAME=VALUE ..." (may be empty)
#   YS_OUT     output folder (netlist, reports)
yosys -import

set top    $::env(YS_TOP)
set out    $::env(YS_OUT)
set inc    [expr {[info exists ::env(YS_INC)] ? $::env(YS_INC) : ""}]
set params [expr {[info exists ::env(YS_PARAMS)] ? $::env(YS_PARAMS) : ""}]
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

# synth: elaborate, optimize, map memories to flip-flops, abc to generic gates
synth -top $top -flatten
opt_clean -purge
tee -o $out/stat.txt stat
tee -o $out/stat_cmos.txt stat -tech cmos
# ltp: longest combinational path in cells (flip-flops not counted)
tee -o $out/ltp.txt ltp -noff
write_verilog -noattr $out/${top}_yosys.v
