// ============================================================================
// Testbench: tb_mac_configurable.sv
// Description: Functional verification of Configurable INT8/INT16 MAC (V2).
// ============================================================================
`timescale 1ns / 1ps

module tb_mac_configurable;

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

    initial clk = 0;
    always #5 clk = ~clk;

    mac_configurable #(
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
        $display("=== STARTING tb_mac_configurable ===");
        rst            = 1;
        enable         = 1;
        in_valid       = 0;
        precision_mode = 0; // INT8
        operand_a      = 16'd0;
        operand_b      = 16'd0;
        acc_clear      = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // --- INT8 Verification ---
        // Test 1: INT8 (-128) * (-128) = +16384
        precision_mode = 0;
        acc_clear      = 1;
        in_valid       = 1;
        operand_a      = 16'h0080; // 8'h80 = -128
        operand_b      = 16'h0080;
        check_result(40'sd16384, "INT8 (-128) * (-128)");

        // Test 2: Accumulate INT8 (-128) * 127 = -16256 -> 16384 - 16256 = 128
        acc_clear = 0;
        in_valid  = 1;
        operand_a = 16'h0080; // -128
        operand_b = 16'h007F; // +127
        check_result(40'sd128, "INT8 Accumulate (-128)*127");

        // Test 3: INT8 Zero test
        in_valid  = 1;
        operand_a = 16'h0000;
        operand_b = 16'h0050;
        check_result(40'sd128, "INT8 Multiply by Zero");

        // --- Runtime Switch to INT16 ---
        // Test 4: INT16 Mode: 1000 * -20 = -20000 -> 128 - 20000 = -19872
        precision_mode = 1;
        in_valid       = 1;
        operand_a      = 16'sd1000;
        operand_b      = -16'sd20;
        check_result(-40'sd19872, "Runtime Switch to INT16 Accumulation");

        // Test 5: INT16 Max boundary with clear
        acc_clear = 1;
        in_valid  = 1;
        operand_a = 16'sd32767;
        operand_b = 16'sd32767;
        check_result(40'sd1073676289, "INT16 Max Boundary with Clear");

        // --- Runtime Switch back to INT8 ---
        // Test 6: INT8 mode without clear -> 1073676289 + (10 * 10) = 1073676389
        precision_mode = 0;
        acc_clear      = 0;
        in_valid       = 1;
        operand_a      = 16'd10;
        operand_b      = 16'd10;
        check_result(40'sd1073676389, "Runtime Switch back to INT8");

        $display("=== tb_mac_configurable FINISHED: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "tb_mac_configurable failed!");
        $finish;
    end

endmodule
