# core.sdc - constraints for rv32_core alone (rv32_core_syn wrapper), Genus PPA runs.
# The SoC uses soc.sdc. This file models what sits around the core inside soc_top, so the
# numbers of the core alone are close to the core inside the SoC.
# synth_core.tcl replaces the CORE_PERIOD line below (PERIOD=<ns>), keep it on one line.
# Plain SDC with set and expr only, so OpenSTA at home can read it too.

set CORE_PERIOD 20.0

# 1. Clock: 50 MHz minimum as the project requires, 50% duty cycle
create_clock -name clk -period $CORE_PERIOD -waveform [list 0 [expr {$CORE_PERIOD / 2.0}]] \
             [get_ports clk]

# 2. Uncertainty and transition before CTS, same as Lab 01, accel.sdc and soc.sdc
set_clock_uncertainty -setup 0.15 [get_clocks clk]
set_clock_uncertainty -hold  0.08 [get_clocks clk]
set_clock_transition 0.08 [get_clocks clk]

# 3. Delays around the SRAM macros (docs/macro_notes.md).
# In soc_top, if_* goes through imem_port to the IMEM sram_2k_macro and d_* goes through the
# bus to the DMEM macro, the peripherals and the IMEM data port. Macro delays do not scale with
# the clock, so they are absolute values. Read from sram_2k_macro.lib on the server (29/10).
# The library has only a typical corner, so these values are slightly optimistic for slow.
set SRAM_CQ 1.2   ;# CLK->Q of the macro (Q output valid after the clock edge)
set SRAM_SU 0.4   ;# Worst setup of the macro pins (CEN and WEN 0.40, A 0.35, D 0.30)
set BUS_D   0.5   ;# Interconnect outside the core: address decode and read data mux
# Signals that come from flops in the SoC (grant, ready, irq, mtime, rst_n) and outputs that
# go to flops keep the Lab 01 ratios (24% and 20% of the period)
set IN_R  [expr {0.24 * $CORE_PERIOD}]
set OUT_R [expr {0.20 * $CORE_PERIOD}]

# 3a. Inputs
# Instruction straight from the IMEM macro Q pins. EX decodes it in the same cycle
# (critical path 2 in docs/spec/core.md section 4.5).
set_input_delay -clock clk -max $SRAM_CQ [get_ports {if_rdata_i[*]}]
# Load data and response: macro Q (or a peripheral register) through the bus read mux.
# WB aligns and forwards it in the same cycle (critical path 1).
set_input_delay -clock clk -max [expr {$SRAM_CQ + $BUS_D}] \
                [get_ports {d_rsp_rdata_i[*] d_rsp_valid_i d_rsp_err_i}]
set_input_delay -clock clk -max $IN_R \
                [get_ports {if_gnt_i if_err_i d_req_ready_i irq_software_i irq_timer_i
                            irq_external_i mtime_i[*]}]
# Min delay for hold: the fastest launch from a macro or a flop in the SoC
set_input_delay -clock clk -min 0.3 \
                [get_ports {if_rdata_i[*] d_rsp_rdata_i[*] d_rsp_valid_i d_rsp_err_i if_gnt_i
                            if_err_i d_req_ready_i irq_software_i irq_timer_i irq_external_i
                            mtime_i[*]}]

# 3b. Outputs
# Fetch address and request go straight to the IMEM macro pins (imem_port only muxes them)
set_output_delay -clock clk -max [expr {$SRAM_SU + 0.2}] [get_ports {if_addr_o[*] if_req_o}]
# Data request: bus decode then the macro pins (or a peripheral register)
set_output_delay -clock clk -max [expr {$SRAM_SU + $BUS_D}] \
                 [get_ports {d_req_valid_o d_addr_o[*] d_we_o d_be_o[*] d_wdata_o[*]}]
# core_sleep_o goes to the clock enable logic of soc_top
set_output_delay -clock clk -max $OUT_R [get_ports core_sleep_o]
# Min delay: hold time of the macro pins and flops
set_output_delay -clock clk -min 0.1 [all_outputs]

# 4. Input slew and output load, no library cell names (works with GPDK45 and Nangate45)
set_input_transition 0.1 [get_ports {rst_n if_gnt_i if_rdata_i[*] if_err_i d_req_ready_i
                                     d_rsp_valid_i d_rsp_rdata_i[*] d_rsp_err_i irq_software_i
                                     irq_timer_i irq_external_i mtime_i[*]}]
set_load -pin_load 0.05 [all_outputs]

# 5. Reset. In soc_top, rst_n of the core comes from the reset_sync flop (soc.sdc section 6),
# so it is a normal timed path: the deassert is checked for recovery and removal like the SoC.
# It is not a false path here, unlike the standalone accel.sdc.
set_input_delay -clock clk -max $IN_R [get_ports rst_n]
set_input_delay -clock clk -min 0.3   [get_ports rst_n]
