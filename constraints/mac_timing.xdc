## Timing Constraints for Configurable INT8/INT16 MAC Architecture
## Target Device: XC7Z020CLG400-1 (PYNQ-Z2)

# 100 MHz Target Clock (10.000 ns period)
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# Set input/output delays for realistic timing analysis
set_input_delay -clock [get_clocks clk] -min 0.500 [get_ports {rst enable in_valid precision_mode acc_clear operand_a* operand_b*}]
set_input_delay -clock [get_clocks clk] -max 2.000 [get_ports {rst enable in_valid precision_mode acc_clear operand_a* operand_b*}]

set_output_delay -clock [get_clocks clk] -min 0.500 [get_ports {accumulator_result* out_valid overflow_status}]
set_output_delay -clock [get_clocks clk] -max 2.000 [get_ports {accumulator_result* out_valid overflow_status}]
