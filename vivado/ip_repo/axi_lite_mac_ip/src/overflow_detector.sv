// ============================================================================
// Module: overflow_detector
// Description: Detects signed two's-complement overflow for a 40-bit accumulator
//              addition: ACC_next = ACC_prev + PROD_ext.
//              Provides optional saturation clamp.
// ============================================================================
`timescale 1ns / 1ps

module overflow_detector #(
    parameter bit SATURATION_ENABLE = 1'b0
) (
    input  logic signed [39:0] acc_prev,
    input  logic signed [39:0] prod_ext,
    input  logic signed [39:0] acc_sum,
    output logic               overflow_flag,
    output logic signed [39:0] final_acc
);

    // Two's complement addition overflow occurs if operands have same sign
    // but the sum has an inverted sign.
    wire sign_prev = acc_prev[39];
    wire sign_prod = prod_ext[39];
    wire sign_sum  = acc_sum[39];

    assign overflow_flag = (~(sign_prev ^ sign_prod)) & (sign_prev ^ sign_sum);

    generate
        if (SATURATION_ENABLE) begin : gen_saturation
            always_comb begin
                if (overflow_flag) begin
                    if (!sign_prev) begin
                        // Positive overflow -> saturate to maximum positive 40-bit signed value
                        final_acc = 40'sh7F_FFFF_FFFF;
                    end else begin
                        // Negative overflow -> saturate to maximum negative 40-bit signed value
                        final_acc = 40'sh80_0000_0000;
                    end
                end else begin
                    final_acc = acc_sum;
                end
            end
        end else begin : gen_wraparound
            // Standard modulo-2^40 wraparound arithmetic
            assign final_acc = acc_sum;
        end
    endgenerate

endmodule
