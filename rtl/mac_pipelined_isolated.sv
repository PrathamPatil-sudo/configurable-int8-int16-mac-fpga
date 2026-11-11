// ============================================================================
// Architecture V5: mac_pipelined_isolated.sv (Pipelined MAC with Operand Isolation)
// Description: Incorporates input operand gating (operand isolation) to eliminate
//              spurious dynamic switching inside the multiplier during inactive
//              clock cycles (when enable=0 or in_valid=0).
//              Initiation Interval (II) = 1 cycle. Latency = 2 cycles.
// ============================================================================
`timescale 1ns / 1ps

module mac_pipelined_isolated #(
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

    // Operand Isolation Stage
    logic [15:0] iso_a;
    logic [15:0] iso_b;

    operand_isolation #(
        .ENABLE_ISOLATION(1'b1)
    ) u_isolation (
        .enable            (enable),
        .in_valid          (in_valid),
        .raw_operand_a     (operand_a),
        .raw_operand_b     (operand_b),
        .isolated_operand_a(iso_a),
        .isolated_operand_b(iso_b)
    );

    // Precision decoding and sign extension
    logic signed [15:0] ext_a;
    logic signed [15:0] ext_b;

    precision_controller u_precision (
        .precision_mode(precision_mode),
        .operand_a     (iso_a),
        .operand_b     (iso_b),
        .ext_operand_a (ext_a),
        .ext_operand_b (ext_b)
    );

    // Pipelined multiplier
    logic signed [31:0] mult_out;
    logic               mult_valid;

    mac_multiplier #(
        .USE_DSP  (USE_DSP),
        .PIPELINED(1'b1)
    ) u_mult (
        .clk          (clk),
        .rst          (rst),
        .enable       (enable),
        .in_valid     (in_valid),
        .ext_operand_a(ext_a),
        .ext_operand_b(ext_b),
        .product_out  (mult_out),
        .valid_out    (mult_valid)
    );

    // Control pipeline: propagate acc_clear
    logic clear_pipe;
    always_ff @(posedge clk) begin
        if (rst) begin
            clear_pipe <= 1'b0;
        end else if (enable) begin
            clear_pipe <= acc_clear;
        end
    end

    // Stage 2: Accumulator
    wire signed [39:0] prod_ext = {{8{mult_out[31]}}, mult_out};

    mac_accumulator #(
        .SATURATION_ENABLE(1'b0)
    ) u_acc (
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
