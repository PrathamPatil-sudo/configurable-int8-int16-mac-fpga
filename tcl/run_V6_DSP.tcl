# ============================================================================
# Vivado Tcl Script: run_V6_DSP.tcl
# ============================================================================
set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize "$script_dir/.."]

# Vivado Tcl Script for V6_DSP (Final Optimized Architecture (DSP))
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob $repo_root/rtl/*.sv]

# Read Timing Constraints
read_xdc $repo_root/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V6_DSP ==="
synth_design -top mac_top -part xc7z020clg400-1 -mode out_of_context -generic {ENABLE_ISOLATION=1'b1} -generic {USE_DSP="yes"}

# Synthesis Reports
report_utilization -file $repo_root/reports/synthesis/V6_DSP_utilization_synth.rpt
report_timing_summary -file $repo_root/reports/timing/V6_DSP_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V6_DSP ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file $repo_root/reports/synthesis/V6_DSP_utilization_route.rpt
report_timing_summary -max_paths 10 -file $repo_root/reports/timing/V6_DSP_timing_route.rpt
report_power -file $repo_root/reports/power/V6_DSP_power.rpt

# Write checkpoint
write_checkpoint -force $repo_root/vivado/V6_DSP_routed.dcp

puts "=== COMPLETED V6_DSP ==="
exit 0
