# accel.sdc - ràng buộc cho chạy thử riêng accelerator (PD-01).
# Dùng chung được cho Genus, Tempus, Innovus và OpenSTA ở nhà.
# Khi ghép vào SoC, Phát gộp vào SDC của soc_top.

set CLK_PERIOD 20.0            ;# 50 MHz, quét giảm dần ở tuần 4-5
set IO_PCT     0.2             ;# input/output delay = 20% chu kỳ

create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty -setup 0.3 [get_clocks clk]   ;# jitter + dự phòng CTS
set_clock_uncertainty -hold  0.1 [get_clocks clk]
set_clock_transition 0.1 [get_clocks clk]

set in_ports [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  [expr {$CLK_PERIOD * $IO_PCT}] -clock clk $in_ports
set_output_delay [expr {$CLK_PERIOD * $IO_PCT}] -clock clk [all_outputs]

# Reset bất đồng bộ: khi chạy riêng block, rst_n đi thẳng vào flop nên đặt
# false path từ chân vào. Trong SoC, rst_n đi qua bộ đồng bộ ở soc_top; chỉ
# false path chân rst_n tới bộ đồng bộ, còn đường deassert sau bộ đồng bộ phải
# được kiểm tra recovery/removal (không đặt false path).
set_false_path -from [get_ports rst_n]

set_max_transition 0.5 [current_design]
set_load 0.01 [all_outputs]
