set_db init_power_nets  VDD
set_db init_ground_nets VSS

source ./syndb/final.invs_setup.tcl

set_db design_process_node 45

connect_global_net VSS -type tie_lo
connect_global_net VSS -type pg_pin -pin_base_name VSS -all 

connect_global_net VDD -type tie_hi
connect_global_net VDD -type pg_pin -pin_base_name VDD -all

read_io_file {../chip/chip.io}

create_floorplan -stdcell_density_size  1 0.7 20 20 20 20

add_rings -around user_defined \
    -type core_rings \
    -nets {VSS VDD} \
    -center 1 \
    -offset 0 \
    -width 4 \
    -spacing 2 \
    -layer {bottom Metal9 top Metal9 right Metal8 left Metal8}

#add_stripes \
  #-layer Metal9 \
  #-direction horizontal \
  #-width 2 \
  #-spacing 1 \
  #-start_offset 10 \
  #-set_to_set_distance 20 \
  #-nets {VSS VDD}

#add_stripes \
  #-layer Metal8 \
  #-direction vertical \
  #-width 2 \
  #-spacing 1 \
  #-start_offset 10 \
  #-set_to_set_distance 20 \
  #-nets {VSS VDD}

route_special -connect {core_pin pad_pin} \
    -core_pin_target {first_after_row_end} \
    -pad_pin_target {nearest_target} \
    -allow_jogging 1 \
    -allow_layer_change 1 \
    -pad_pin_layer_range {Metal1(1) Metal9(9)} \
    -layer_change_range { Metal1(1) Metal9(9) } \
    -crossover_via_layer_range { Metal1(1) Metal9(9) } \
    -target_via_layer_range { Metal1(1) Metal9(9) } \
    -nets {VSS VDD}

#route_special \
    #-connect {core_pin pad_pin} \
    #-core_pin_target {first_after_row_end} \
    # -pad_pin_target {nearest_target} \
    #-nets {VDD VSS} \
    #-allow_layer_change 1 \
    #-pad_pin_layer_range {Metal1(1) Metal9(9)} 


#-----------------------------------------------------------------------
# Pre-placement timing check
#-----------------------------------------------------------------------

check_timing
time_design -pre_place -report_prefix preplace -report_dir reports/STA

#-----------------------------------------------------------------------
## Placement and Pre CTS optimization
#-----------------------------------------------------------------------

place_opt_design -report_dir reports/STA

set_db add_tieoffs_cells { TIEHI TIELO }
add_tieoffs

#-----------------------------------------------------------------------
## Pre Clock tree timing analysis
#-----------------------------------------------------------------------

time_design -pre_cts -report_dir reports/STA

#-----------------------------------------------------------------------
## Clock Tree Synthesis
#-----------------------------------------------------------------------
set_db cts_inverter_cells {CLKINVX12 CLKINVX16 CLKINVX4}
set_db cts_buffer_cells {CLKBUFX16 CLKBUFX12 CLKBUFX4}
set_db cts_update_io_latency false

clock_design

report_clock_trees -summary -out_file reports/report_clock_trees.rpt
report_skew_groups  -summary -out_file reports/report_ccopt_skew_groups.rpt

#-----------------------------------------------------------------------
## Post CTS setup and hold optimization
#-----------------------------------------------------------------------

set_interactive_constraint_modes [all_constraint_modes -active]
reset_clock_tree_latency [all_clocks]
set_propagated_clock [all_clocks]
set_interactive_constraint_modes []

opt_design -post_cts        -report_dir reports/STA
time_design -post_cts       -report_dir reports/STA

opt_design -post_cts -hold -report_dir reports/STA
time_design -post_cts -hold -report_dir reports/STA

#-----------------------------------------------------------------------
## Global and Detail routing
#-----------------------------------------------------------------------

assign_io_pins

route_design

#-----------------------------------------------------------------------
## Post Route setup and hold optimization
#-----------------------------------------------------------------------
set_db extract_rc_engine post_route
set_db extract_rc_effort_level high

# enable Signal Integrity analysis
set_db delaycal_enable_si true
set_db timing_analysis_type ocv

opt_design -post_route -setup -hold -report_dir reports/STA

#-----------------------------------------------------------------------
## Add filler cells
#-----------------------------------------------------------------------
set_db add_fillers_cells {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
add_fillers

#-----------------------------------------------------------------------
## Verification: physical, logical equivalent checking and timing
#-----------------------------------------------------------------------

# DRC and LVS
check_drc           -out_file reports/check_drc.rpt
check_connectivity  -out_file reports/check_connectivity.rpt

#-----------------------------------------------------------------------
## Signoff extraction
#-----------------------------------------------------------------------
# Select QRC extraction to be in signoff mode
set_db extract_rc_engine post_route
set_db extract_rc_effort_level signoff
set_db extract_rc_coupled true
set_db extract_rc_lef_tech_file_map cds45.layermap

extract_rc

# Generate RC spefs  for WC_rc & BC_rc corners
write_parasitics -rc_corner default_rc -spef_file out/design_default_rc.spef

#-----------------------------------------------------------------------
## Saving verilog netlist, delays, constraints
#-----------------------------------------------------------------------
write_netlist out/design.v
write_sdf out/design.sdf
write_sdc out/design.sdc

#-----------------------------------------------------------------------
## Save the design
#-----------------------------------------------------------------------
write_db out/final_route.db

#--------------------------------
# report core area
#--------------------------------

set xl [get_db current_design .core_bbox.ll.x]
set xu [get_db current_design .core_bbox.ur.x]
set yl [get_db current_design .core_bbox.ll.y]
set yu [get_db current_design .core_bbox.ur.y]

puts "FINAL DESIGN CORE AREA:"
puts [expr ($xu - $xl)*($yu - $yl)]



