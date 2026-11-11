// ============================================================================
// Architecture V6: mac_top.sv (Final Selected Optimized Architecture)
// Description: Fully parameterized, high-throughput, configurable INT8/INT16 MAC.
//              Combines operand isolation for power efficiency, pipelined
//              multiplier stages for timing closure, shared arithmetic resources,
//              and optional saturation clamping.
//              Initiation Interval (II) = 1 cycle. Latency = 2 cycles.
// ============================================================================
`timescale 1ns / 1ps

module mac_top #(
    parameter bit    ENABLE_ISOLATION  = 1'b1,
    parameter bit    SATURATION_ENABLE = 1'b0,
    parameter        USE_DSP           = "yes"  // "yes", "no", or "auto"
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

    // ------------------------------------------------------------------------
    // Step 1: Operand Isolation
    // ------------------------------------------------------------------------
    logic [15:0] iso_a;
    logic [15:0] iso_b;

    operand_isolation #(
        .ENABLE_ISOLATION(ENABLE_ISOLATION)
    ) u_isolation (
        .enable            (enable),
        .in_valid          (in_valid),
        .raw_operand_a     (operand_a),
        .raw_operand_b     (operand_b),
        .isolated_operand_a(iso_a),
        .isolated_operand_b(iso_b)
    );

    // ------------------------------------------------------------------------
    // Step 2: Precision Decoding & Sign Extension
    // ------------------------------------------------------------------------
    logic signed [15:0] ext_a;
    logic signed [15:0] ext_b;

    precision_controller u_precision (
        .precision_mode(precision_mode),
        .operand_a     (iso_a),
        .operand_b     (iso_b),
        .ext_operand_a (ext_a),
        .ext_operand_b (ext_b)
    );

    // ------------------------------------------------------------------------
    // Step 3: Multiplier Pipeline Stage (Stage 1)
    // ------------------------------------------------------------------------
    logic signed [31:0] mult_out;
    logic               mult_valid;

    mac_multiplier #(
        .USE_DSP  (USE_DSP),
        .PIPELINED(1'b1)
    ) u_multiplier (
        .clk          (clk),
        .rst          (rst),
        .enable       (enable),
        .in_valid     (in_valid),
        .ext_operand_a(ext_a),
        .ext_operand_b(ext_b),
        .product_out  (mult_out),
        .valid_out    (mult_valid)
    );

    // Propagate acc_clear through pipeline to align with product stage
    logic clear_pipe;
    always_ff @(posedge clk) begin
        if (rst) begin
            clear_pipe <= 1'b0;
        end else if (enable) begin
            clear_pipe <= acc_clear;
        end
    end

    // ------------------------------------------------------------------------
    // Step 4: Sign Extension & Accumulator Stage (Stage 2)
    // ------------------------------------------------------------------------
    wire signed [39:0] prod_ext = {{8{mult_out[31]}}, mult_out};

    mac_accumulator #(
        .SATURATION_ENABLE(SATURATION_ENABLE)
    ) u_accumulator (
        .clk               (clk),
        .rst               (rst),
        .enable            (enable),
        .acc_clear         (clear_pipe),
        .valid_in          (mult_valid),
        .product_ext       (prod_ext),
        .accumulator_result(accumulator_result),
        .out_valid         (out_valid),
        .overflow_status   (overflow_status)
    );

endmodule
