// ============================================================================
// Testbench: tb_mac_top.sv
// Description: Comprehensive testbench for Architecture V6 (mac_top).
//              - Reads 2362+ randomized and corner-case vectors from disk.
//              - Clock-for-clock cycle-accurate comparison against Python golden model.
//              - Checks SVA protocol assertions.
//              - Dumps VCD switching activity for Vivado power analysis.
// ============================================================================
`timescale 1ns / 1ps

module tb_mac_top;

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

    // 100 MHz Clock Generation
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT Instantiation (Optimized Architecture V6)
    mac_top #(
        .ENABLE_ISOLATION (1'b1),
        .SATURATION_ENABLE(1'b0),
        .USE_DSP          ("yes")
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

    // ------------------------------------------------------------------------
    // SystemVerilog Assertions (SVA)
    // ------------------------------------------------------------------------
    // Property 1: Reset must clear accumulator
    property p_rst_clears_acc;
        @(posedge clk) rst |=> (accumulator_result == 40'sd0);
    endproperty
    assert property (p_rst_clears_acc) else $error("SVA VIOLATION: Reset failed to clear accumulator!");

    // Property 2: Enable low must freeze accumulator
    property p_en_low_holds_acc;
        @(posedge clk) disable iff (rst) (!enable) |=> $stable(accumulator_result);
    endproperty
    assert property (p_en_low_holds_acc) else $error("SVA VIOLATION: Accumulator changed while enable=0!");

    // ------------------------------------------------------------------------
    // File I/O Verification against Python Golden Dataset
    // ------------------------------------------------------------------------
    integer f_stim, f_exp, f_rep;
    integer status_stim, status_exp;
    integer line_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer total_vectors = 0;

    // Stimulus variables
    integer v_rst, v_en, v_in_val, v_mode, v_clr;
    logic [15:0] v_a, v_b;

    // Expected variables
    logic [39:0] exp_res;
    integer exp_out_val, exp_ovf;

    initial begin
        $display("=== STARTING tb_mac_top GOLDEN VERIFICATION ===");
        
        // Dump VCD for waveform and Vivado switching activity analysis
        $dumpfile("mac_top_activity.vcd");
        $dumpvars(0, tb_mac_top);

        f_stim = $fopen("../../results/experimental_data/stimulus.txt", "r");
        if (f_stim == 0) f_stim = $fopen("../results/experimental_data/stimulus.txt", "r");
        if (f_stim == 0) f_stim = $fopen("stimulus.txt", "r");
        if (f_stim == 0) f_stim = $fopen("results/experimental_data/stimulus.txt", "r");

        f_exp  = $fopen("../../results/experimental_data/expected_l2.txt", "r");
        if (f_exp == 0) f_exp = $fopen("../results/experimental_data/expected_l2.txt", "r");
        if (f_exp == 0) f_exp = $fopen("expected_l2.txt", "r");
        if (f_exp == 0) f_exp = $fopen("results/experimental_data/expected_l2.txt", "r");

        if (f_stim == 0 || f_exp == 0) begin
            $display("[ERROR] Could not open test vector files!");
            $fatal(1, "Test vector files missing!");
        end

        // Initial default state
        rst            = 1;
        enable         = 1;
        in_valid       = 0;
        precision_mode = 0;
        operand_a      = 16'd0;
        operand_b      = 16'd0;
        acc_clear      = 0;

        @(posedge clk);
        #1;

        while (!$feof(f_stim) && !$feof(f_exp)) begin
            status_stim = $fscanf(f_stim, "%d %d %d %d %h %h %d\n", 
                                  v_rst, v_en, v_in_val, v_mode, v_a, v_b, v_clr);
            status_exp  = $fscanf(f_exp, "%h %d %d\n", 
                                  exp_res, exp_out_val, exp_ovf);

            if (status_stim == 7 && status_exp == 3) begin
                line_num++;
                total_vectors++;

                // Apply stimulus at clock boundary
                rst            <= v_rst;
                enable         <= v_en;
                in_valid       <= v_in_val;
                precision_mode <= v_mode;
                operand_a      <= v_a;
                operand_b      <= v_b;
                acc_clear      <= v_clr;

                @(posedge clk);
                #1; // Sample post-clock state

                // Verify output against golden expectation
                // Note: exp_res is compared when out_valid is active or reset
                if (accumulator_result === exp_res && 
                    out_valid === exp_out_val && 
                    overflow_status === exp_ovf) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    if (fail_count <= 10) begin
                        $display("[MISMATCH at Cycle %0d] Stim(rst=%b,en=%b,val=%b,mode=%b,a=%h,b=%h,clr=%b)",
                                 line_num, v_rst, v_en, v_in_val, v_mode, v_a, v_b, v_clr);
                        $display("   RTL Output: acc=%h, out_val=%b, ovf=%b", 
                                 accumulator_result, out_valid, overflow_status);
                        $display("   Golden Exp: acc=%h, out_val=%b, ovf=%b", 
                                 exp_res, exp_out_val, exp_ovf);
                    end
                end
            end
        end

        $fclose(f_stim);
        $fclose(f_exp);

        $display("\n=======================================================");
        $display(" tb_mac_top VERIFICATION SUMMARY");
        $display(" Total Vectors Executed : %0d", total_vectors);
        $display(" Total Vectors Passed   : %0d", pass_count);
        $display(" Total Vectors Failed   : %0d", fail_count);
        $display(" Verification Rate      : %0.2f%%", (real'(pass_count)/real'(total_vectors))*100.0);
        $display("=======================================================\n");

        if (fail_count == 0) begin
            $display("[SUCCESS] All %0d vectors matched golden reference model with 100%% precision!", pass_count);
        end else begin
            $fatal(1, "[FAILURE] Encountered %0d mismatches during verification!", fail_count);
        end

        $finish;
    end

endmodule
