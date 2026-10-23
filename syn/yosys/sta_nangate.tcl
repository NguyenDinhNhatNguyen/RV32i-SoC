# sta_nangate.tcl - OpenSTA đọc netlist của synth_nangate.tcl (flow nhà), CHỈ ĐỂ XEM XU HƯỚNG.
# Không có đặt cell và đi dây: trễ dây theo wire load mặc định của Nangate45, clock lý tưởng.
# Chạy: sta -no_splash -exit syn/yosys/sta_nangate.tcl, tham số qua biến môi trường:
#   YS_TOP, YS_OUT, YS_LIB như synth_nangate.tcl
#   STA_PERIOD  chu kỳ clock, ns (mặc định 20, tức 50 MHz theo đề bài)
set top    $::env(YS_TOP)
set out    $::env(YS_OUT)
set period [expr {[info exists ::env(STA_PERIOD)] ? $::env(STA_PERIOD) : 20.0}]

read_liberty $::env(YS_LIB)
read_verilog $out/${top}_nangate.v
link_design $top

# Ràng buộc tối thiểu. Ngõ vào và ra chưa biết trễ ngoài nên đặt 0, đường
# vào và ra được báo riêng. Reset bất đồng bộ không tính (giống accel.sdc).
create_clock -name clk -period $period [get_ports clk]
set in_ports [lsearch -all -inline -not [all_inputs] [get_ports clk]]
set_input_delay  0 -clock clk $in_ports
set_output_delay 0 -clock clk [all_outputs]
set_driving_cell -lib_cell BUF_X2 $in_ports
set_load 0.005 [all_outputs]
set_false_path -from [get_ports rst_n]

set fp [open $out/sta.txt w]
proc both {fp s} { puts $s; puts $fp $s }

# Đường flop -> flop quyết định F_max của core
set p [lindex [find_timing_paths -from [all_registers -clock_pins] -to [all_registers -data_pins] -path_delay max] 0]
set slack [get_property $p slack]
set tmin  [expr {$period - $slack}]
both $fp [format "reg2reg  slack %.3f ns  chu ky nho nhat %.3f ns  F_max %.0f MHz" $slack $tmin [expr {1000.0 / $tmin}]]
foreach {name from to} [list in2reg [all_inputs] [all_registers -data_pins] \
                             reg2out [all_registers -clock_pins] [all_outputs] \
                             in2out [all_inputs] [all_outputs]] {
    set q [lindex [find_timing_paths -from $from -to $to -path_delay max] 0]
    if {$q ne ""} {
        both $fp [format "%-8s tre %.3f ns" $name [expr {$period - [get_property $q slack]}]]
    }
}
close $fp

report_checks -from [all_registers -clock_pins] -to [all_registers -data_pins] \
    -path_delay max -fields {fanout cap slew} -digits 3 > $out/path_reg2reg.txt
report_checks -from [all_inputs] -path_delay max -digits 3 > $out/path_in.txt
report_checks -group_count 20 -endpoint_count 1 -unique_paths_to_endpoint \
    -from [all_registers -clock_pins] -to [all_registers -data_pins] \
    -path_delay max -format end > $out/top_endpoints.txt
