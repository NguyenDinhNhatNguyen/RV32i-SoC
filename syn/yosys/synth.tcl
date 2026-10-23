# synth.tcl - tổng hợp thử bằng Yosys (flow nhà), CHỈ ĐỂ XEM XU HƯỚNG.
# Ánh xạ sang cổng logic chung của Yosys, không dùng thư viện GPDK45, không có
# ràng buộc thời gian. Số cell và số tầng logic không so được với Genus.
# Chạy: yosys -c syn/yosys/synth.tcl, tham số qua biến môi trường:
#   YS_TOP     module top
#   YS_SRCS    danh sách file Verilog
#   YS_INC     thư mục include (có thể rỗng)
#   YS_PARAMS  "NAME=VALUE ..." (có thể rỗng)
#   YS_OUT     thư mục kết quả (netlist, báo cáo)
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

# synth: elaborate, tối ưu, map bộ nhớ thành flip-flop, abc ra cổng chung
synth -top $top -flatten
opt_clean -purge
tee -o $out/stat.txt stat
tee -o $out/stat_cmos.txt stat -tech cmos
# ltp: đường tổ hợp dài nhất tính theo số cell (không tính flip-flop)
tee -o $out/ltp.txt ltp -noff
write_verilog -noattr $out/${top}_yosys.v
