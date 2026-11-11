# ============================================================================
# Vivado Tcl Script: run_V4.tcl
# ============================================================================
set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize "$script_dir/.."]

# Vivado Tcl Script for V4 (Separate INT8/INT16 Datapaths)
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob $repo_root/rtl/*.sv]

# Read Timing Constraints
read_xdc $repo_root/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V4 ==="
synth_design -top mac_separate_datapaths -part xc7z020clg400-1 -mode out_of_context

# Synthesis Reports
report_utilization -file $repo_root/reports/synthesis/V4_utilization_synth.rpt
report_timing_summary -file $repo_root/reports/timing/V4_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V4 ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file $repo_root/reports/synthesis/V4_utilization_route.rpt
report_timing_summary -max_paths 10 -file $repo_root/reports/timing/V4_timing_route.rpt
report_power -file $repo_root/reports/power/V4_power.rpt

# Write checkpoint
write_checkpoint -force $repo_root/vivado/V4_routed.dcp

puts "=== COMPLETED V4 ==="
exit 0
