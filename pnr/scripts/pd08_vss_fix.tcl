# pd08_vss_fix.tcl - Record of the PD-08 power-only fixes (26/11) on soc_top layout _p9.
# The commands were typed one by one on the server. Run from pnr/run_soc_p9 with innovus -nowin.
# This replay saves to a new database so DBS/route_trim.enc is never overwritten.
restoreDesign DBS/route_eco.enc.dat soc_top

# Remove the floating Metal7 piece of VSS
editDelete -net VSS -type Special -shape STRIPE -layer Metal7 -object_type Wire \
           -area {21.6 327.5 23.15 329.05}

# Trim the dangling ends of the VSS stripes
editTrim -nets VSS -layers Metal7
editTrim -nets VSS -layers Metal8

verifyConnectivity -report conn_pd08.rpt
verify_drc -report drc_pd08.rpt
verifyProcessAntenna -reportfile ant_pd08.rpt
saveDesign DBS/route_trim_replay.enc
