# ============================================================================
# Vivado Tcl Script: package_mac_ip.tcl
# ============================================================================
set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize "$script_dir/.."]

# ============================================================================
# Vivado Tcl Script: package_mac_ip.tcl
# Description: Packages the custom AXI4-Lite Configurable MAC into a Vivado IP.
# ============================================================================
set_param general.maxThreads 4

set proj_dir "$repo_root"
set ip_repo_dir "$proj_dir/vivado/ip_repo/axi_lite_mac_ip"

file delete -force $ip_repo_dir
file mkdir $ip_repo_dir

create_project -force ip_packager_proj "$proj_dir/vivado/ip_packager_proj" -part xc7z020clg400-1

# Add relevant RTL sources
add_files -norecurse [list \
    "$proj_dir/rtl/precision_controller.sv" \
    "$proj_dir/rtl/operand_isolation.sv" \
    "$proj_dir/rtl/overflow_detector.sv" \
    "$proj_dir/rtl/mac_multiplier.sv" \
    "$proj_dir/rtl/mac_accumulator.sv" \
    "$proj_dir/rtl/mac_top.sv" \
    "$proj_dir/rtl/axi_lite_mac_ip.sv" \
]
set_property top axi_lite_mac_ip [current_fileset]
update_compile_order -fileset sources_1

# Package IP
ipx::package_project -root_dir $ip_repo_dir -vendor xilinx.com -library user -taxonomy /UserIP -import_files -set_current false

ipx::unload_core $ip_repo_dir/component.xml
ipx::open_ipxact_file $ip_repo_dir/component.xml

set_property name "axi_lite_mac_ip" [ipx::current_core]
set_property display_name "Configurable INT8/INT16 MAC AXI IP" [ipx::current_core]
set_property description "High-Throughput Configurable INT8/INT16 Multiply-Accumulate Architecture with AXI4-Lite Slave Interface" [ipx::current_core]
set_property version "1.0" [ipx::current_core]

# Infer AXI4-Lite slave bus interface if not automatically inferred
ipx::infer_bus_interfaces [ipx::current_core]

ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
close_project -delete

puts "=== Custom AXI4-Lite MAC IP Packaged Successfully at $ip_repo_dir ==="
exit 0
