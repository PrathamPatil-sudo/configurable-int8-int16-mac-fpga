# Vivado Tcl Script for V5 (Pipelined MAC with Operand Isolation)
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/rtl/*.sv]

# Read Timing Constraints
read_xdc d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/constraints/mac_timing.xdc

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR V5 ==="
synth_design -top mac_pipelined_isolated -part xc7z020clg400-1 -mode out_of_context

# Synthesis Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V5_utilization_synth.rpt
report_timing_summary -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V5_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR V5 ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/synthesis/V5_utilization_route.rpt
report_timing_summary -max_paths 10 -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/timing/V5_timing_route.rpt
report_power -file d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/reports/power/V5_power.rpt

# Write checkpoint
write_checkpoint -force d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture/vivado/V5_routed.dcp

puts "=== COMPLETED V5 ==="
exit 0
