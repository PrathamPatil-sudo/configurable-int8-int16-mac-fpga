// ============================================================================
// Architecture V2: mac_configurable.sv (Shared Configurable INT8/INT16 MAC)
// Description: Supports runtime precision switching between signed INT8 and INT16
//              using a shared multiplier datapath. Combinational multiplier
//              followed by 40-bit registered accumulator.
//              Latency = 1 cycle, Initiation Interval (II) = 1 cycle.
// ============================================================================
`timescale 1ns / 1ps

module mac_configurable #(
    parameter USE_DSP = "auto"
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     enable,
    input  logic                     in_valid,
    input  logic                     precision_mode, // 0: INT8, 1: INT16
    input  logic [15:0]              operand_a,
    input  logic [15:0]              operand_b,
    input  logic                     acc_clear,
    output logic signed [39:0]       accumulator_result,
    output logic                     out_valid,
    output logic                     overflow_status
);

    // Precision decoding and sign extension
    logic signed [15:0] ext_a;
    logic signed [15:0] ext_b;

    precision_controller u_precision (
        .precision_mode(precision_mode),
        .operand_a     (operand_a),
        .operand_b     (operand_b),
        .ext_operand_a (ext_a),
        .ext_operand_b (ext_b)
    );

    // Shared multiplier datapath (combinational)
    (* use_dsp = USE_DSP *)
    wire signed [31:0] mult_comb = ext_a * ext_b;
    wire signed [39:0] prod_ext  = {{8{mult_comb[31]}}, mult_comb};

    // Shared accumulator
    mac_accumulator #(
        .SATURATION_ENABLE(1'b0)
    ) u_acc (
        .clk               (clk),
        .rst               (rst),
        .enable            (enable),
        .acc_clear         (acc_clear),
        .valid_in          (in_valid),
        .product_ext       (prod_ext),
        .accumulator_result(accumulator_result),
        .out_valid         (out_valid),
        .overflow_status   (overflow_status)
    );

endmodule
