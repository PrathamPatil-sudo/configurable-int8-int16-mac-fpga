// ============================================================================
// Module: mac_multiplier
// Description: Parameterized signed multiplier supporting configurable pipeline
//              registers and Vivado DSP synthesis attributes ("yes" / "no" / "auto").
// ============================================================================
`timescale 1ns / 1ps

module mac_multiplier #(
    parameter USE_DSP   = "auto", // "yes", "no", or "auto"
    parameter bit    PIPELINED = 1'b1
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     enable,
    input  logic                     in_valid,
    input  logic signed [15:0]       ext_operand_a,
    input  logic signed [15:0]       ext_operand_b,
    output logic signed [31:0]       product_out,
    output logic                     valid_out
);

    // Multiplier implementation with synthesis attribute
    (* use_dsp = USE_DSP *)
    logic signed [31:0] mult_comb;
    assign mult_comb = ext_operand_a * ext_operand_b;

    generate
        if (PIPELINED) begin : gen_pipelined_mult
            logic signed [31:0] prod_reg;
            logic               valid_reg;

            always_ff @(posedge clk) begin
                if (rst) begin
                    prod_reg  <= 32'sd0;
                    valid_reg <= 1'b0;
                end else if (enable) begin
                    prod_reg  <= mult_comb;
                    valid_reg <= in_valid;
                end
            end

            assign product_out = prod_reg;
            assign valid_out   = valid_reg;
        end else begin : gen_comb_mult
            assign product_out = mult_comb;
            assign valid_out   = in_valid;
        end
    endgenerate

endmodule
