// core_rtl2gate.do - LEC of rv32_core RTL against the Genus netlist (rv32_core_syn).
// Same structure as accel_rtl2gate.do (run_lec_cg.do of Lab 1, Conformal_Asic license).
// Run from the repo root on the server: make lec-core (after make synth-core)
// The golden side reads the wrapper written by synth_core.tcl, so both sides have the same top
// module with the same parameters (ENABLE_M=1, ENABLE_BTB as synthesized).

// Skip any failing command (for example a missing license) and keep going
set dofile abort off

read library -both ~/PDK_GPDK45/lib/slow_vdd1v0_basiccells.v
// -incdir for `include "rv32_defs.vh"
read design -golden -verilog -incdir rtl/core rtl/core/rv32_alu.v rtl/core/rv32_btb.v rtl/core/rv32_csr.v rtl/core/rv32_decoder.v rtl/core/rv32_imm_gen.v rtl/core/rv32_lsu_align.v rtl/core/rv32_muldiv.v rtl/core/rv32_regfile.v rtl/core/rv32_core.v syn/out_core/rv32_core_syn.v
read design -revised -verilog syn/out_core/rv32_core_syn_netlist.v
set root module rv32_core_syn -both
// The netlist has clock gating cells (latch + AND): model them as flop enables
set flatten model -gated_clock
set system mode lec
// The 32x32 multiplier (ENABLE_M=1) can leave aborted points at the default effort, and
// analyze datapath needs Conformal_Ultra. GLS also checks function: make gls-core
set compare effort high
add compared points -all
compare
report verification > syn/out_core/reports/lec_verification.rpt
report unmapped points > syn/out_core/reports/lec_unmapped.rpt
report verification
exit -force
