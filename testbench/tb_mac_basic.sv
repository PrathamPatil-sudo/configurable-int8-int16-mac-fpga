// ============================================================================
// Testbench: tb_mac_basic.sv
// Description: Direct and boundary verification for Baseline INT16 MAC (V1).
// ============================================================================
`timescale 1ns / 1ps

module tb_mac_basic;

    logic        clk;
    logic        rst;
    logic        enable;
    logic        in_valid;
    logic        precision_mode;
    logic [15:0] operand_a;
    logic [15:0] operand_b;
    logic        acc_clear;
    logic signed [39:0] accumulator_result;
    logic        out_valid;
    logic        overflow_status;

    // Clock Generation: 100 MHz (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT Instantiation
    mac_basic #(
        .USE_DSP("auto")
    ) dut (
        .clk               (clk),
        .rst               (rst),
        .enable            (enable),
        .in_valid          (in_valid),
        .precision_mode    (precision_mode),
        .operand_a         (operand_a),
        .operand_b         (operand_b),
        .acc_clear         (acc_clear),
        .accumulator_result(accumulator_result),
        .out_valid         (out_valid),
        .overflow_status   (overflow_status)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check_result(input signed [39:0] expected_acc, input string test_name);
        @(posedge clk);
        #1;
        if (accumulator_result === expected_acc) begin
            $display("[PASS] %s: Accumulator = %0d (Expected: %0d)", test_name, accumulator_result, expected_acc);
            pass_count++;
        end else begin
            $display("[FAIL] %s: Accumulator = %0d (Expected: %0d)", test_name, accumulator_result, expected_acc);
            fail_count++;
        end
    endtask

    initial begin
        $display("=== STARTING tb_mac_basic ===");
        rst            = 1;
        enable         = 1;
        in_valid       = 0;
        precision_mode = 1;
        operand_a      = 16'd0;
        operand_b      = 16'd0;
        acc_clear      = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Test 1: Positive x Positive: 100 * 200 = 20000
        acc_clear = 1;
        in_valid  = 1;
        operand_a = 16'd100;
        operand_b = 16'd200;
        check_result(40'sd20000, "Pos x Pos with clear");

        // Test 2: Accumulate: Positive x Negative: 20000 + (50 * -100) = 15000
        acc_clear = 0;
        in_valid  = 1;
        operand_a = 16'sd50;
        operand_b = -16'sd100;
        check_result(40'sd15000, "Pos x Neg accumulation");

        // Test 3: Negative x Negative: 15000 + (-30 * -40) = 15000 + 1200 = 16200
        in_valid  = 1;
        operand_a = -16'sd30;
        operand_b = -16'sd40;
        check_result(40'sd16200, "Neg x Neg accumulation");

        // Test 4: Multiply by Zero: 16200 + (100 * 0) = 16200
        in_valid  = 1;
        operand_a = 16'sd100;
        operand_b = 16'sd0;
        check_result(40'sd16200, "Multiply by Zero");

        // Test 5: Multiply by One: 16200 + (1 * 555) = 16755
        in_valid  = 1;
        operand_a = 16'sd1;
        operand_b = 16'sd555;
        check_result(40'sd16755, "Multiply by One");

        // Test 6: INT16 Boundary: 32767 * 32767 = 1073676289
        acc_clear = 1;
        in_valid  = 1;
        operand_a = 16'sd32767;
        operand_b = 16'sd32767;
        check_result(40'sd1073676289, "INT16 Max Pos Boundary");

        // Test 7: INT16 Min Boundary: -32768 * 1 = -32768
        acc_clear = 1;
        in_valid  = 1;
        operand_a = -16'sd32768;
        operand_b = 16'sd1;
        check_result(-40'sd32768, "INT16 Min Neg Boundary");

        // Test 8: Enable Low should hold state
        enable    = 0;
        in_valid  = 1;
        operand_a = 16'sd999;
        operand_b = 16'sd999;
        @(posedge clk);
        #1;
        if (accumulator_result === -40'sd32768) begin
            $display("[PASS] Enable Low: Value held correctly (-32768)");
            pass_count++;
        end else begin
            $display("[FAIL] Enable Low: Value changed unexpectedly (%0d)", accumulator_result);
            fail_count++;
        end

        // Re-enable and reset
        enable = 1;
        rst    = 1;
        @(posedge clk);
        #1;
        if (accumulator_result === 40'sd0) begin
            $display("[PASS] Reset Test: Accumulator successfully cleared to 0");
            pass_count++;
        end else begin
            $display("[FAIL] Reset Test: Expected 0, got %0d", accumulator_result);
            fail_count++;
        end

        $display("=== tb_mac_basic FINISHED: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "tb_mac_basic failed!");
        $finish;
    end

endmodule
