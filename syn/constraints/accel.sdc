# accel.sdc - ràng buộc cho chạy thử riêng accelerator (PD-01).
# Viết theo cấu trúc SDC của Lab 01, chu kỳ 20 ns (50 MHz) theo yêu cầu đồ án.
# Dùng chung cho Genus, Innovus, Tempus và OpenSTA ở nhà.

create_clock -name clk -period 20.0 -waveform {0 10.0} [get_ports clk]
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.08 [get_clocks clk]
set_clock_transition 0.08 [get_clocks clk]

set in_ports [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
# Input/output delay giữ tỉ lệ như Lab 01 (khoảng 24% và 20% chu kỳ)
set_input_delay  -clock clk -max 4.8 $in_ports
set_input_delay  -clock clk -min 0.3 $in_ports
set_output_delay -clock clk -max 4.0 [all_outputs]
set_output_delay -clock clk -min 0.2 [all_outputs]

set_driving_cell -lib_cell INVX2 $in_ports
set_load -pin_load 0.05 [all_outputs]

# Reset bất đồng bộ: khi chạy riêng block, rst_n vào thẳng flop nên đặt false path từ chân vào.
# Trong SoC, rst_n qua bộ đồng bộ ở soc_top: chỉ false path chân rst_n tới bộ đồng bộ, đường deassert sau đó phải kiểm tra recovery/removal.
set_false_path -from [get_ports rst_n]
