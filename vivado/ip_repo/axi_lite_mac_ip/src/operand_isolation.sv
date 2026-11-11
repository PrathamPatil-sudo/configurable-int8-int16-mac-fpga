// ============================================================================
// Module: operand_isolation
// Description: Selectively gates input operands to reduce dynamic switching 
//              power dissipation in downstream multipliers when input is invalid
//              or unit is disabled.
// ============================================================================
`timescale 1ns / 1ps

module operand_isolation #(
    parameter bit ENABLE_ISOLATION = 1'b1
) (
    input  logic        enable,
    input  logic        in_valid,
    input  logic [15:0] raw_operand_a,
    input  logic [15:0] raw_operand_b,
    output logic [15:0] isolated_operand_a,
    output logic [15:0] isolated_operand_b
);

    generate
        if (ENABLE_ISOLATION) begin : gen_isolation
            // Gate operands to 0 when disabled or input transaction is invalid
            wire gate_en = enable & in_valid;
            assign isolated_operand_a = gate_en ? raw_operand_a : 16'h0000;
            assign isolated_operand_b = gate_en ? raw_operand_b : 16'h0000;
        end else begin : gen_no_isolation
            assign isolated_operand_a = raw_operand_a;
            assign isolated_operand_b = raw_operand_b;
        end
    endgenerate

endmodule
