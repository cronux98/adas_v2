# Post-resize script: detailed_placement → CTS
# OpenROAD v2.0-14726, sky130hs

set plat ~/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs
set res ~/Desktop/openroad/OpenROAD-flow-scripts/flow/results/sky130hs/adas_v2/base

puts "\n=== STAGE 3_5: Detailed Placement ==="

read_liberty $plat/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
read_db $res/3_4_place_resized.odb
read_sdc $res/2_floorplan.sdc
source $plat/setRC.tcl

detailed_placement
check_placement -verbose
report_design_area
write_db $res/3_5_place_dp.odb

puts "\n=== STAGE 4: CTS ==="

set_wire_rc -clock -layer met5
set_wire_rc -signal -layer met2

repair_clock_inverters
clock_tree_synthesis -sink_clustering_enable \
  -sink_clustering_size 30 \
  -sink_clustering_max_diameter 60

set_propagated_clock [all_clocks]

detailed_placement
estimate_parasitics -placement

repair_timing -setup -hold -verbose
detailed_placement
estimate_parasitics -placement
repair_timing -hold -verbose

report_cts
report_clock_skew
report_checks -path_delay min_max -format full_clock_expanded -digits 3
report_design_area

write_db $res/4_1_cts.odb
write_sdc -no_timestamp $res/4_cts.sdc

puts "\n=== DP + CTS COMPLETE ==="
exit
