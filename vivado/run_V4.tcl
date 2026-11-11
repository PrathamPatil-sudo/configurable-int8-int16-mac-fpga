# Vivado Tcl Script for V4 (Separate INT8/INT16 Datapaths)
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/rtl/*.sv]

# Read Timing Constraints
read_xdc d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V4 ==="
synth_design -top mac_separate_datapaths -part xc7z020clg400-1 -mode out_of_context

# Synthesis Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V4_utilization_synth.rpt
report_timing_summary -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V4_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V4 ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V4_utilization_route.rpt
report_timing_summary -max_paths 10 -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V4_timing_route.rpt
report_power -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/power/V4_power.rpt

# Write checkpoint
write_checkpoint -force d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/vivado/V4_routed.dcp

puts "=== COMPLETED V4 ==="
exit 0
