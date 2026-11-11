# ============================================================================
# Vivado Tcl Script: build_pynq_overlay.tcl
# Description: Builds full Zynq SoC Block Design for PYNQ-Z2 board:
#              - Zynq-7000 Processing System (PS7)
#              - AXI SmartConnect / Interconnect
#              - Custom AXI4-Lite Configurable MAC IP
#              - Processor System Reset
#              - Full synthesis, implementation, and bitstream generation.
# ============================================================================
set_param general.maxThreads 4

set proj_dir "d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture"
# Use a short root path for the BD project to prevent Windows 260-char path limit
set bd_proj_dir "d:/pynq_mac_soc"
set ip_repo_dir "$proj_dir/vivado/ip_repo/axi_lite_mac_ip"
set overlay_dir "$proj_dir/vivado/pynq_overlay"
set hw_reports_dir "$proj_dir/reports/hardware"

file delete -force $bd_proj_dir
file mkdir $bd_proj_dir
file mkdir $overlay_dir
file mkdir $hw_reports_dir

create_project -force pynq_mac_soc $bd_proj_dir -part xc7z020clg400-1
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog

# Create Block Design
create_bd_design "pynq_mac_bd"

# Instantiate Zynq-7000 Processing System
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]

# Configure PS7: 100 MHz FCLK0, M_AXI_GP0 enabled, DDR3 enabled for PYNQ-Z2
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
] $ps7

# Instantiate Custom MAC IP
set mac_ip [create_bd_cell -type ip -vlnv xilinx.com:user:axi_lite_mac_ip:1.0 axi_lite_mac_ip_0]

# Instantiate AXI Interconnect and Reset
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $axi_ic

set rst_gen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M]

# Clock and Reset Connections
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_lite_mac_ip_0/s_axi_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_100M/slowest_sync_clk]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_100M/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_0_100M/interconnect_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_lite_mac_ip_0/s_axi_aresetn]

# AXI Bus Connections
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins axi_lite_mac_ip_0/s_axi]

# Memory Map Address Assignment (0x43C00000 - 64K)
create_bd_addr_seg -range 0x00010000 -offset 0x43C00000 [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_lite_mac_ip_0/s_axi/reg0] SEG_axi_lite_mac_ip_0_reg0

# Validate and Save
validate_bd_design
save_bd_design

# Create HDL Wrapper
set wrapper_file [make_wrapper -files [get_files "pynq_mac_bd.bd"] -top]
add_files -norecurse $wrapper_file
update_compile_order -fileset sources_1

# Synthesis & Implementation Flow for Bitstream
puts "=== RUNNING SYNTHESIS FOR PYNQ OVERLAY ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

puts "=== RUNNING IMPLEMENTATION FOR PYNQ OVERLAY ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Collect Bitstream and Hardware Handoff
set bit_file [get_property DIRECTORY [get_runs impl_1]]/pynq_mac_bd_wrapper.bit
file copy -force $bit_file "$overlay_dir/pynq_mac.bit"
file copy -force $bit_file "$hw_reports_dir/pynq_mac.bit"

# Export Hardware Handoff (.hwh)
set hwh_src [glob -nocomplain "$bd_proj_dir/pynq_mac_soc.gen/sources_1/bd/pynq_mac_bd/hw_handoff/*.hwh"]
if {[llength $hwh_src] > 0} {
    file copy -force [lindex $hwh_src 0] "$overlay_dir/pynq_mac.hwh"
    file copy -force [lindex $hwh_src 0] "$hw_reports_dir/pynq_mac.hwh"
}

# Open implemented run for reports
open_run impl_1
report_utilization -file "$hw_reports_dir/pynq_soc_utilization.rpt"
report_timing_summary -file "$hw_reports_dir/pynq_soc_timing.rpt"
report_power -file "$hw_reports_dir/pynq_soc_power.rpt"

puts "=== PYNQ OVERLAY GENERATION COMPLETE! ==="
puts "Overlay Files Ready at: $overlay_dir/pynq_mac.bit and pynq_mac.hwh"
exit 0
