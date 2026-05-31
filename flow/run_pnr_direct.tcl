# Direct P&R script — single OpenROAD session, ORFS v2.0-14726
# David Chen, Backend Lead — 2026-04-29

set scr ~/Desktop/openroad/OpenROAD-flow-scripts/flow/scripts
set plat ~/Desktop/openroad/OpenROAD-flow-scripts/flow/platforms/sky130hs
set res ~/Desktop/openroad/OpenROAD-flow-scripts/flow/results/sky130hs/adas_v2/base
set rep ~/Desktop/openroad/OpenROAD-flow-scripts/flow/reports/sky130hs/adas_v2/base

file mkdir $res
file mkdir $rep

# === STAGE 3_4: Resize ===
puts "\n=== STAGE 3_4: Resize ==="

read_liberty $plat/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
read_db $res/3_3_place_gp.odb
read_sdc $res/2_floorplan.sdc
source $plat/setRC.tcl

estimate_parasitics -placement
repair_design -verbose
repair_timing -setup -hold -verbose
estimate_parasitics -placement
repair_timing -hold -verbose

report_checks -path_delay min_max -format full_clock_expanded -digits 3
report_design_area
write_db $res/3_4_place_resized.odb

# === STAGE 3_5: Detail Place ===
puts "\n=== STAGE 3_5: Detail Place ==="

detailed_placement
check_placement -verbose
report_design_area
write_db $res/3_5_place_dp.odb

# === STAGE 4: CTS ===
puts "\n=== STAGE 4: CTS ==="

set_wire_rc -clock -layer met5
set_wire_rc -signal -layer met2

repair_clock_inverters
clock_tree_synthesis -sink_clustering_enable \
  -sink_clustering_size 30 \
  -sink_clustering_max_diameter 60

set_propagated_clock [all_clocks]

detail_placement
estimate_parasitics -placement

repair_timing -setup -hold -verbose
detail_placement
estimate_parasitics -placement
repair_timing -hold -verbose

report_cts
report_clock_skew
report_checks -path_delay min_max -format full_clock_expanded -digits 3
report_design_area

write_db $res/4_1_cts.odb
write_sdc -no_timestamp $res/4_cts.sdc

# === STAGE 5_1: Global Route ===
puts "\n=== STAGE 5_1: Global Route ==="

# Fix zero_/one_ tie-off nets for TritonRoute
set block [ord::get_db_block]
foreach net_name {zero_ one_} {
  set net [$block findNet $net_name]
  if {$net != "NULL"} {
    puts "Making $net_name a special net..."
    if {$net_name == "one_"} {
      $net setSigType POWER
    } else {
      $net setSigType GROUND
    }
    $net setSpecial
  }
}

estimate_parasitics -global_routing
global_route -congestion_report_file $rep/congestion.rpt \
  -congestion_iterations 100
estimate_parasitics -global_routing

report_checks -path_delay min_max -format full_clock_expanded -digits 3
write_db $res/5_1_grt.odb

# === STAGE 5_2: Detail Route ===
puts "\n=== STAGE 5_2: Detail Route ==="

detailed_route -output_drc $rep/5_route_drc.rpt \
  -bottom_routing_layer met1 \
  -top_routing_layer met5 \
  -verbose 1

report_checks -path_delay min_max -format full_clock_expanded -digits 3
write_db $res/5_2_route.odb

# === STAGE 6: Final ===
puts "\n=== STAGE 6: Final ==="

filler_placement {sky130_fd_sc_hs__fill_1 sky130_fd_sc_hs__fill_2 sky130_fd_sc_hs__fill_4 sky130_fd_sc_hs__fill_8}
check_placement

estimate_parasitics -global_routing

report_design_area
report_power
report_tns
report_wns
report_worst_slack -max
report_worst_slack -min
report_clock_skew
report_checks -path_delay min_max -format full_clock_expanded -digits 3

write_gds $res/6_final.gds
exec mkdir -p ~/vlsi-team/shared/projects/adas_v2/gate
exec cp $res/6_final.gds ~/vlsi-team/shared/projects/adas_v2/gate/adas_v2_final.gds

puts "\n=== P&R FLOW COMPLETE: $res/6_final.gds ==="
exit
