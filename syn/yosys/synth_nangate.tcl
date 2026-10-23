# synth_nangate.tcl - tổng hợp thử bằng Yosys với thư viện mở Nangate45 (flow nhà),
# CHỈ ĐỂ XEM XU HƯỚNG TIMING. Không dùng GPDK45. Số chính thức lấy từ Genus ở trường.
# Netlist ra được OpenSTA đọc bằng syn/yosys/sta_nangate.tcl.
# Chạy: yosys -c syn/yosys/synth_nangate.tcl, tham số qua biến môi trường:
#   YS_TOP     module top
#   YS_SRCS    danh sách file Verilog
#   YS_INC     thư mục include (có thể rỗng)
#   YS_PARAMS  "NAME=VALUE ..." (có thể rỗng)
#   YS_OUT     thư mục kết quả
#   YS_LIB     file liberty Nangate45 (scripts/get_nangate45.sh tải về, không commit)
#   YS_ABC_D   mục tiêu trễ cho abc, đơn vị ps (mặc định 2000)
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

# Như synth -flatten, riêng bước fine map $lcu (carry của cộng, trừ, so sánh)
# thành Kogge-Stone thay cho ripple mặc định, gần với bộ cộng Genus chọn hơn.
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
# Thống kê flop có enable trước khi map (Nangate không có flop enable, dfflibmap
# tách enable thành mux nên phải đếm ở đây)
tee -o $out/stat_generic.txt stat
# Flop sang cell DFFR/DFFS/DFF, logic sang cell chuẩn theo mục tiêu trễ.
# Script abc mặc định của Yosys 0.33 không chèn buffer và không đổi cỡ cell,
# net fanout lớn sẽ có trễ vô lý, nên thêm buffer, upsize, dnsize.
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
