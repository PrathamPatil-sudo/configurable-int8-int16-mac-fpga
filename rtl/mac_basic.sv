// ============================================================================
// Architecture V1: mac_basic.sv (Baseline Non-Pipelined INT16 MAC)
// Description: Simplest signed MAC unit. Pure 16-bit signed multiplication
//              accumulated into a 40-bit accumulator register.
//              Combinational multiplier followed by registered accumulator.
//              Latency = 1 cycle, Initiation Interval (II) = 1 cycle.
// ============================================================================
`timescale 1ns / 1ps

module mac_basic #(
    parameter USE_DSP = "auto"
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     enable,
    input  logic                     in_valid,
    input  logic                     precision_mode, // Ignored in V1 (strictly INT16)
    input  logic [15:0]              operand_a,
    input  logic [15:0]              operand_b,
    input  logic                     acc_clear,
    output logic signed [39:0]       accumulator_result,
    output logic                     out_valid,
    output logic                     overflow_status
);

    // Interpret 16-bit inputs directly as signed two's-complement
    wire signed [15:0] s_a = operand_a;
    wire signed [15:0] s_b = operand_b;

    // Combinational 16x16 signed multiplier
    (* use_dsp = USE_DSP *)
    wire signed [31:0] mult_comb = s_a * s_b;
    wire signed [39:0] prod_ext  = {{8{mult_comb[31]}}, mult_comb};

    // Accumulator instance
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
