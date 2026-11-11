# Vivado Tcl Script for V6_LUT (Optimized Architecture (Forced LUTs))
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/rtl/*.sv]

# Read Timing Constraints
read_xdc d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V6_LUT ==="
synth_design -top mac_top -part xc7z020clg400-1 -mode out_of_context -generic {ENABLE_ISOLATION=1'b1} -generic {USE_DSP="no"}

# Synthesis Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V6_LUT_utilization_synth.rpt
report_timing_summary -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V6_LUT_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V6_LUT ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V6_LUT_utilization_route.rpt
report_timing_summary -max_paths 10 -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V6_LUT_timing_route.rpt
report_power -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/power/V6_LUT_power.rpt

# Write checkpoint
write_checkpoint -force d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/vivado/V6_LUT_routed.dcp

puts "=== COMPLETED V6_LUT ==="
exit 0
