# accel.sdc - constraints for the standalone accelerator trial (PD-01).
# Follows the Lab 01 SDC structure, 20 ns period (50 MHz) as the project requires.
# Shared by Genus, Innovus, Tempus and OpenSTA at home.

create_clock -name clk -period 20.0 -waveform {0 10.0} [get_ports clk]
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.08 [get_clocks clk]
set_clock_transition 0.08 [get_clocks clk]

set in_ports [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
# Input/output delays keep the Lab 01 ratios (about 24% and 20% of the period)
set_input_delay  -clock clk -max 4.8 $in_ports
set_input_delay  -clock clk -min 0.3 $in_ports
set_output_delay -clock clk -max 4.0 [all_outputs]
set_output_delay -clock clk -min 0.2 [all_outputs]

set_driving_cell -lib_cell INVX2 $in_ports
set_load -pin_load 0.05 [all_outputs]

# Asynchronous reset: for the standalone block rst_n goes straight to the flops, so the input pin
# gets a false path.
# In the SoC, rst_n goes through the synchronizer in soc_top: only the pin to the synchronizer is a
# false path, and the deassert path after it must be checked for recovery/removal.
set_false_path -from [get_ports rst_n]
