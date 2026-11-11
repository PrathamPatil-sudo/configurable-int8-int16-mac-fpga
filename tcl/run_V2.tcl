# ============================================================================
# Vivado Tcl Script: run_V2.tcl
# ============================================================================
set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize "$script_dir/.."]

# Vivado Tcl Script for V2 (Shared Configurable INT8/INT16 MAC)
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob $repo_root/rtl/*.sv]

# Read Timing Constraints
read_xdc $repo_root/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V2 ==="
synth_design -top mac_configurable -part xc7z020clg400-1 -mode out_of_context

# Synthesis Reports
report_utilization -file $repo_root/reports/synthesis/V2_utilization_synth.rpt
report_timing_summary -file $repo_root/reports/timing/V2_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V2 ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file $repo_root/reports/synthesis/V2_utilization_route.rpt
report_timing_summary -max_paths 10 -file $repo_root/reports/timing/V2_timing_route.rpt
report_power -file $repo_root/reports/power/V2_power.rpt

# Write checkpoint
write_checkpoint -force $repo_root/vivado/V2_routed.dcp

puts "=== COMPLETED V2 ==="
exit 0
