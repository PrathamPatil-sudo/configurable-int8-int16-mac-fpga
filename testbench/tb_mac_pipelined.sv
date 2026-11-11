// ============================================================================
// Testbench: tb_mac_pipelined.sv
// Description: Pipeline verification for Architecture V3 (Pipelined Configurable MAC).
//              Explicitly validates:
//              - Pipeline Latency = 2 clock cycles.
//              - Initiation Interval (II) = 1 cycle under back-to-back streaming.
//              - Transaction ordering and alignment.
//              - Zero lost or duplicated transactions.
// ============================================================================
`timescale 1ns / 1ps

module tb_mac_pipelined;

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

    mac_pipelined #(
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

    initial begin
        $display("=== STARTING tb_mac_pipelined ===");
        rst            = 1;
        enable         = 1;
        in_valid       = 0;
        precision_mode = 1;
        operand_a      = 16'd0;
        operand_b      = 16'd0;
        acc_clear      = 0;

        repeat (4) @(posedge clk);
        rst <= 0;
        @(posedge clk);

        // --------------------------------------------------------------------
        // Phase 1: Latency Measurement
        // --------------------------------------------------------------------
        $display("[INFO] Phase 1: Measuring Pipeline Latency...");
        
        // Cycle 0: Input Transaction (10 * 20 = 200) with clear
        acc_clear      <= 1;
        in_valid       <= 1;
        precision_mode <= 1;
        operand_a      <= 16'sd10;
        operand_b      <= 16'sd20;

        @(posedge clk);
        // Cycle 1: Bubble
        acc_clear <= 0;
        in_valid  <= 0;
        operand_a <= 16'd0;
        operand_b <= 16'd0;

        #1;
        if (out_valid === 1'b0) begin
            $display("[PASS] Cycle 1 after input: out_valid = 0 (pipeline filling, latency > 1)");
            pass_count++;
        end else begin
            $display("[FAIL] Cycle 1 after input: out_valid unexpectedly asserted = %b", out_valid);
            fail_count++;
        end

        @(posedge clk);
        // Cycle 2: Result should emerge!
        #1;
        if (out_valid === 1'b1 && accumulator_result === 40'sd200) begin
            $display("[PASS] Cycle 2 after input: out_valid = 1, acc = %0d (Pipeline Latency = 2 cycles confirmed)", accumulator_result);
            pass_count++;
        end else begin
            $display("[FAIL] Cycle 2 after input: out_valid = %b, acc = %0d (Expected: 200, out_valid=1)", out_valid, accumulator_result);
            fail_count++;
        end

        @(posedge clk);
        // Cycle 3: Pipeline idle again
        #1;
        if (out_valid === 1'b0 && accumulator_result === 40'sd200) begin
            $display("[PASS] Cycle 3: out_valid = 0, accumulator held previous value 200");
            pass_count++;
        end else begin
            $display("[FAIL] Cycle 3: unexpected state out_valid = %b, acc = %0d", out_valid, accumulator_result);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // Phase 2: Initiation Interval II = 1 Continuous Streaming Verification
        // --------------------------------------------------------------------
        $display("[INFO] Phase 2: Verifying Initiation Interval (II = 1) across 10 back-to-back cycles...");
        
        // Apply 10 inputs consecutively, one per clock cycle
        fork
            // Thread 1: Generator applying inputs back-to-back
            begin
                for (int i = 1; i <= 10; i++) begin
                    acc_clear      <= (i == 1) ? 1'b1 : 1'b0;
                    in_valid       <= 1'b1;
                    precision_mode <= 1'b0; // INT8 mode
                    operand_a      <= i;
                    operand_b      <= 16'd1;
                    @(posedge clk);
                end
                // Deassert in_valid after 10 transactions
                in_valid  <= 1'b0;
                acc_clear <= 1'b0;
            end

            // Thread 2: Checker verifying outputs emerging with latency 2
            begin
                longint exp_sums[10] = '{1, 3, 6, 10, 15, 21, 28, 36, 45, 55};
                // Wait for the 2-cycle latency
                @(posedge clk);
                @(posedge clk);

                for (int k = 0; k < 10; k++) begin
                    #1;
                    if (out_valid === 1'b1 && accumulator_result === exp_sums[k]) begin
                        $display("[PASS] Streaming cycle %0d: out_valid=1, acc = %0d (Expected: %0d) -> II=1 Verified", 
                                 k+1, accumulator_result, exp_sums[k]);
                        pass_count++;
                    end else begin
                        $display("[FAIL] Streaming cycle %0d: out_valid=%b, acc = %0d (Expected: %0d)", 
                                 k+1, out_valid, accumulator_result, exp_sums[k]);
                        fail_count++;
                    end
                    @(posedge clk);
                end
            end
        join

        // Drain cycle
        repeat (3) @(posedge clk);
        #1;
        if (out_valid === 1'b0 && accumulator_result === 40'sd55) begin
            $display("[PASS] Post-stream idle: out_valid=0, final acc = 55 maintained");
            pass_count++;
        end else begin
            $display("[FAIL] Post-stream idle: out_valid=%b, acc = %0d", out_valid, accumulator_result);
            fail_count++;
        end

        $display("\n=======================================================");
        $display(" tb_mac_pipelined FINISHED: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=======================================================\n");

        if (fail_count > 0) $fatal(1, "tb_mac_pipelined failed!");
        $finish;
    end

endmodule
