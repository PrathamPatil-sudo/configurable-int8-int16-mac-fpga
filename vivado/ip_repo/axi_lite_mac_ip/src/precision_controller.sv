// ============================================================================
// Module: precision_controller
// Description: Unpacks and sign-extends 8-bit or 16-bit operands based on 
//              precision_mode:
//              - mode 0: Signed INT8 (uses lower 8 bits [7:0], sign-extended)
//              - mode 1: Signed INT16 (uses full 16 bits [15:0])
// ============================================================================
`timescale 1ns / 1ps

module precision_controller (
    input  logic        precision_mode, // 0: INT8, 1: INT16
    input  logic [15:0] operand_a,
    input  logic [15:0] operand_b,
    output logic signed [15:0] ext_operand_a,
    output logic signed [15:0] ext_operand_b
);

    always_comb begin
        if (precision_mode == 1'b0) begin
            // INT8 Mode: operand is in lower 8 bits [7:0]
            ext_operand_a = {{8{operand_a[7]}}, operand_a[7:0]};
            ext_operand_b = {{8{operand_b[7]}}, operand_b[7:0]};
        end else begin
            // INT16 Mode: full 16-bit signed operand
            ext_operand_a = operand_a;
            ext_operand_b = operand_b;
        end
    end

endmodule
