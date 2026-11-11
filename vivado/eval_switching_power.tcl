# vivado/eval_switching_power.tcl
# Evaluate dynamic power of V3 (unisolated) vs V5 (isolated) under idle input switching

set proj_dir "d:/iswdp_tcad/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture"

proc eval_design_power {checkpoint name proj_dir} {
    puts "=========================================================="
    puts "Analyzing $name from $checkpoint"
    puts "=========================================================="
    open_checkpoint $checkpoint
    
    # 1. Active Workload: in_valid = 1, enable = 1, operands toggling at 50% toggle rate
    set_switching_activity -static_probability 1.0 -toggle_rate 0 [get_ports enable]
    set_switching_activity -static_probability 1.0 -toggle_rate 0 [get_ports in_valid]
    set_switching_activity -static_probability 0.5 -toggle_rate 50 [get_ports {operand_a* operand_b*}]
    set_switching_activity -static_probability 0.5 -toggle_rate 20 [get_ports precision_mode]
    set_switching_activity -static_probability 0.0 -toggle_rate 0 [get_ports rst]
    set_switching_activity -static_probability 0.0 -toggle_rate 0 [get_ports acc_clear]
    
    set pwr_active [report_power -no_propagation -return_string]
    # Extract dynamic power
    regexp {Total On-Chip Power \(W\)\s+\|\s+([0-9\.]+)} $pwr_active -> total_act
    regexp {Dynamic \(W\)\s+\|\s+([0-9\.]+)} $pwr_active -> dyn_act
    regexp {Device Static \(W\)\s+\|\s+([0-9\.]+)} $pwr_active -> stat_act
    puts "$name Active -> Dynamic: $dyn_act W, Static: $stat_act W, Total: $total_act W"
    
    # 2. Idle Noise Workload: in_valid = 0, enable = 1, operands toggling rapidly (noise/bus sharing at 100% toggle rate)
    set_switching_activity -static_probability 1.0 -toggle_rate 0 [get_ports enable]
    set_switching_activity -static_probability 0.0 -toggle_rate 0 [get_ports in_valid]
    set_switching_activity -static_probability 0.5 -toggle_rate 100 [get_ports {operand_a* operand_b*}]
    
    # Report power with vectorless/user-defined activity
    set pwr_idle [report_power -return_string]
    regexp {Total On-Chip Power \(W\)\s+\|\s+([0-9\.]+)} $pwr_idle -> total_idle
    regexp {Dynamic \(W\)\s+\|\s+([0-9\.]+)} $pwr_idle -> dyn_idle
    regexp {Device Static \(W\)\s+\|\s+([0-9\.]+)} $pwr_idle -> stat_idle
    puts "$name Idle Noise -> Dynamic: $dyn_idle W, Static: $stat_idle W, Total: $total_idle W"
    
    # Also get detailed power per block type (Signals, Logic, DSP)
    report_power -file "$proj_dir/reports/power/${name}_switching_activity_power.rpt"
    close_project
    return [list $dyn_act $dyn_idle]
}

set res_v3 [eval_design_power "$proj_dir/vivado/V3_routed.dcp" "V3_unisolated" $proj_dir]
set res_v5 [eval_design_power "$proj_dir/vivado/V5_routed.dcp" "V5_isolated" $proj_dir]

puts "=========================================================="
puts "SUMMARY OF SWITCHING ACTIVITY POWER EXPERIMENT:"
puts "V3 (Unisolated): Active Dynamic = [lindex $res_v3 0] W, Idle Noise Dynamic = [lindex $res_v3 1] W"
puts "V5 (Isolated):   Active Dynamic = [lindex $res_v5 0] W, Idle Noise Dynamic = [lindex $res_v5 1] W"
puts "=========================================================="
