// ============================================================================
// Module: mac_accumulator
// Description: 40-bit signed accumulator register with synchronous clear,
//              clock enable, overflow detection and optional saturation.
// ============================================================================
`timescale 1ns / 1ps

module mac_accumulator #(
    parameter bit SATURATION_ENABLE = 1'b0
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     enable,
    input  logic                     acc_clear,
    input  logic                     valid_in,
    input  logic signed [39:0]       product_ext,
    output logic signed [39:0]       accumulator_result,
    output logic                     out_valid,
    output logic                     overflow_status
);

    logic signed [39:0] acc_reg;
    logic               overflow_reg;
    logic               out_valid_reg;

    // Combinational addition and overflow detection
    logic signed [39:0] acc_base;
    logic signed [39:0] raw_sum;
    logic signed [39:0] clamped_sum;
    logic               ovf_flag;

    // If acc_clear is asserted, the baseline for accumulation is zero
    assign acc_base = acc_clear ? 40'sd0 : acc_reg;
    assign raw_sum  = acc_base + product_ext;

    overflow_detector #(
        .SATURATION_ENABLE(SATURATION_ENABLE)
    ) u_overflow_detector (
        .acc_prev     (acc_base),
        .prod_ext     (product_ext),
        .acc_sum      (raw_sum),
        .overflow_flag(ovf_flag),
        .final_acc    (clamped_sum)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            acc_reg       <= 40'sd0;
            overflow_reg  <= 1'b0;
            out_valid_reg <= 1'b0;
        end else if (enable) begin
            if (acc_clear && !valid_in) begin
                acc_reg       <= 40'sd0;
                overflow_reg  <= 1'b0;
                out_valid_reg <= 1'b0;
            end else if (valid_in) begin
                acc_reg       <= clamped_sum;
                overflow_reg  <= ovf_flag;
                out_valid_reg <= 1'b1;
            end else begin
                out_valid_reg <= 1'b0;
            end
        end else begin
            out_valid_reg <= 1'b0;
        end
    end

    assign accumulator_result = acc_reg;
    assign overflow_status    = overflow_reg;
    assign out_valid          = out_valid_reg;

endmodule
