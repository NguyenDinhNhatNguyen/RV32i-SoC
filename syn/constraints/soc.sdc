# soc.sdc - SDC v1 for soc_top (STA-01).
# Shared by Genus, Innovus and Tempus at school and by OpenSTA at home, so it only uses
# commands all four accept (no remove_from_collection, no library cell names).
# Ports of soc_top: clk, rst_n, gpio_i[31:0], uart_rx, gpio_o[31:0], gpio_oe[31:0], uart_tx.
# Details and reasons: docs/soc_top.md section 4.7.

# 1. Clock: one clock domain, 50 MHz minimum (20 ns), 50% duty cycle.
# SOC_PERIOD is the only number to change for another frequency. synth_soc.tcl replaces this
# line for the F_max sweep (STA-03), and the max IO delays below follow it.
set SOC_PERIOD 20.0
create_clock -name clk -period $SOC_PERIOD -waveform [list 0 [expr {$SOC_PERIOD / 2.0}]] \
    [get_ports clk]

# 2. Clock uncertainty and transition before CTS, same values as Lab 01 and accel.sdc.
# Setup 0.15 ns covers jitter plus part of the 80 ps skew target, hold 0.08 ns covers skew.
# After CTS Innovus and Tempus use the propagated clock, so set_clock_transition no longer applies.
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.08 [get_clocks clk]
set_clock_transition 0.08 [get_clocks clk]

# 3. Input delays, 24% of the period for max (4.8 ns at 20 ns) and 0.3 ns for min (Lab 01 ratio).
# gpio_i and uart_rx are asynchronous to clk and each bit goes straight into a 2-flop
# synchronizer (gpio_apb, uart_apb). They still get an input delay so the path to the first
# synchronizer flop is constrained and no endpoint is left unconstrained.
set in_ports [get_ports {gpio_i[*] uart_rx}]
set_input_delay  -clock clk -max [expr {0.24 * $SOC_PERIOD}] $in_ports
set_input_delay  -clock clk -min 0.3 $in_ports

# 4. Output delays, 20% of the period for max (4.0 ns at 20 ns) and 0.2 ns for min (Lab 01 ratio).
# Every output comes straight from a flop (gpio_apb data_out and dir, uart_apb uart_txd).
set out_ports [get_ports {gpio_o[*] gpio_oe[*] uart_tx}]
set_output_delay -clock clk -max [expr {0.20 * $SOC_PERIOD}] $out_ports
set_output_delay -clock clk -min 0.2 $out_ports

# 5. Input slew and output load. set_input_transition replaces the Lab set_driving_cell so
# the file names no library cell and works with GPDK45 and the home Nangate45 library alike.
set_input_transition 0.1 [get_ports {rst_n gpio_i[*] uart_rx}]
set_load -pin_load 0.05 $out_ports

# 6. Asynchronous reset (docs/spec/soc_spec.md section 1).
# rst_n only drives the two flops of reset_sync (u_rst), so this false path covers exactly
# the pin to the synchronizer. rst_n is asynchronous to clk and those flops only resample it.
# The deassert path from u_rst (sync_q) to the reset pin of every other flop is NOT a false
# path: it is a normal timed path, and STA checks recovery (like setup) and removal (like hold)
# on it. Report it with report_timing -check_type recovery / removal (Tempus, Innovus)
# or report_checks -path_group asynchronous (OpenSTA).
set_false_path -from [get_ports rst_n]
# rst_n also gets an input delay so check_timing_intent (Genus) and check_setup (OpenSTA)
# report no input without a delay. The false path above makes the value irrelevant.
set_input_delay -clock clk 0.0 [get_ports rst_n]
