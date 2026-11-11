// ============================================================================
// Architecture V4: mac_separate_datapaths.sv (Separate INT8/INT16 Datapaths)
// Description: Implements separate, non-shared multiplier datapaths:
//              - Dedicated 8x8 signed multiplier for INT8
//              - Dedicated 16x16 signed multiplier for INT16
//              Used to evaluate resource sharing trade-offs against shared architectures.
//              Initiation Interval (II) = 1 cycle. Latency = 2 cycles.
// ============================================================================
`timescale 1ns / 1ps

module mac_separate_datapaths #(
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

    // Dedicated 8-bit operands
    wire signed [7:0] a_int8 = operand_a[7:0];
    wire signed [7:0] b_int8 = operand_b[7:0];

    // Dedicated 16-bit operands
    wire signed [15:0] a_int16 = operand_a[15:0];
    wire signed [15:0] b_int16 = operand_b[15:0];

    // Dedicated Multiplier 1: 8x8 Signed Multiplier
    (* use_dsp = USE_DSP *)
    logic signed [15:0] mult8_comb;
    assign mult8_comb = a_int8 * b_int8;

    // Dedicated Multiplier 2: 16x16 Signed Multiplier
    (* use_dsp = USE_DSP *)
    logic signed [31:0] mult16_comb;
    assign mult16_comb = a_int16 * b_int16;

    // Pipeline registers for both datapaths
    logic signed [15:0] mult8_reg;
    logic signed [31:0] mult16_reg;
    logic               mode_pipe;
    logic               valid_pipe;
    logic               clear_pipe;

    always_ff @(posedge clk) begin
        if (rst) begin
            mult8_reg  <= 16'sd0;
            mult16_reg <= 32'sd0;
            mode_pipe  <= 1'b0;
            valid_pipe <= 1'b0;
            clear_pipe <= 1'b0;
        end else if (enable) begin
            mult8_reg  <= mult8_comb;
            mult16_reg <= mult16_comb;
            mode_pipe  <= precision_mode;
            valid_pipe <= in_valid;
            clear_pipe <= acc_clear;
        end
    end

    // Selected product sign-extended to 40 bits
    logic signed [39:0] selected_prod_ext;
    always_comb begin
        if (mode_pipe == 1'b0) begin
            // Sign-extend 16-bit INT8 product to 40 bits
            selected_prod_ext = {{24{mult8_reg[15]}}, mult8_reg};
        end else begin
            // Sign-extend 32-bit INT16 product to 40 bits
            selected_prod_ext = {{8{mult16_reg[31]}}, mult16_reg};
        end
    end

    // Shared Accumulator
    mac_accumulator #(
        .SATURATION_ENABLE(1'b0)
    ) u_acc (
        .clk               (clk),
        .rst               (rst),
        .enable            (enable),
        .acc_clear         (clear_pipe),
        .valid_in          (valid_pipe),
        .product_ext       (selected_prod_ext),
        .accumulator_result(accumulator_result),
        .out_valid         (out_valid),
        .overflow_status   (overflow_status)
    );

endmodule
