# gls_home.tcl - Yosys netlist of soc_top for the home check of the GLS flow (make gls-soc-home).
# Generic Yosys gates (simulated with simcells.v), hierarchy kept like the Genus netlist,
# the 8 sram_2k_macro stay black boxes. Not a synthesis result, only a netlist that
# tb_soc -DGLS and scripts/gls_soc.sh can be tried on without the school server.
# Run: YS_OUT=<folder> yosys -c syn/yosys/gls_home.tcl
yosys -import
set out $::env(YS_OUT)
file mkdir $out
foreach f [lsort [glob rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/accel/*.v]] {
    read_verilog -defer -Irtl/core -Irtl/bus -Irtl/mem $f
}
read_verilog -lib syn/yosys/sram_2k_macro_bb.v
synth -top soc_top
opt_clean -purge
write_verilog -noattr $out/soc_top_yosys_hier.v
