// ============================================================================
// Architecture V3: mac_pipelined.sv (Pipelined Configurable INT8/INT16 MAC)
// Description: Fully pipelined MAC architecture targeting maximum throughput.
//              Features intermediate pipeline registers between the shared
//              multiplier and the 40-bit accumulator.
//              Initiation Interval (II) = 1 cycle. Latency = 2 cycles.
// ============================================================================
`timescale 1ns / 1ps

module mac_pipelined #(
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

    // Stage 0: Precision decoding
    logic signed [15:0] ext_a;
    logic signed [15:0] ext_b;

    precision_controller u_precision (
        .precision_mode(precision_mode),
        .operand_a     (operand_a),
        .operand_b     (operand_b),
        .ext_operand_a (ext_a),
        .ext_operand_b (ext_b)
    );

    // Stage 1: Multiplier with pipeline register
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

    // Control pipeline: propagate acc_clear synchronously with pipeline depth
    logic clear_pipe;
    always_ff @(posedge clk) begin
        if (rst) begin
            clear_pipe <= 1'b0;
        end else if (enable) begin
            clear_pipe <= acc_clear;
        end
    end

    // Stage 2: 40-bit Accumulator
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
