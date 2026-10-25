// accel_rtl2gate.do - LEC of the accelerator RTL against the Genus netlist (PD-01).
// Based on run_lec_cg.do from Lab 1 (which runs with the school license).
// The Genus-generated dofile is not used because it needs a Conformal Ultra license.
// Run from the repo root on the server: make lec-accel
// Libraries come from ~/PDK_GPDK45 (the Lab copy in each person's home).

// Skip any failing command (for example a missing license) and keep going
set dofile abort off

read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
read design -golden -verilog rtl/accel/pe.v rtl/accel/accelerator_top.v rtl/accel/accel_wrapper.v
read design -revised -verilog syn/out_accel/accel_wrapper_netlist.v
set root module accel_wrapper -both
// The netlist has clock gating cells (latch + AND): model them as flop enables,
// otherwise Conformal reports 3 unmapped DLATs and almost every flop non-equivalent.
set flatten model -gated_clock
set system mode lec
// The default effort leaves 149 aborted points behind the 8x8 multipliers. analyze datapath needs
// Conformal_Ultra (the school has only Conformal_Asic). High effort gives PASS 812/812 (21/10, about 9 min).
// Function is also checked by gate-level simulation: make gls-accel
set compare effort high
add compared points -all
compare
report verification > syn/out_accel/reports/lec_verification.rpt
report verification
exit -force
