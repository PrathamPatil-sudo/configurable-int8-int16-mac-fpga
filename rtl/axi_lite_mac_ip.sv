// ============================================================================
// Module: axi_lite_mac_ip.sv
// Description: AXI4-Lite Slave wrapper for the Configurable INT8/INT16 MAC.
//              Enables ARM Cortex-A9 Processing System control on PYNQ-Z2.
// ============================================================================
`timescale 1ns / 1ps

module axi_lite_mac_ip #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
    // AXI4-Lite Clock and Reset
    input  logic                                  s_axi_aclk,
    input  logic                                  s_axi_aresetn,

    // AXI4-Lite Write Address Channel
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr,
    input  logic [2:0]                            s_axi_awprot,
    input  logic                                  s_axi_awvalid,
    output logic                                  s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  logic [C_S_AXI_DATA_WIDTH-1:0]         s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb,
    input  logic                                  s_axi_wvalid,
    output logic                                  s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]                            s_axi_bresp,
    output logic                                  s_axi_bvalid,
    input  logic                                  s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr,
    input  logic [2:0]                            s_axi_arprot,
    input  logic                                  s_axi_arvalid,
    output logic                                  s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [C_S_AXI_DATA_WIDTH-1:0]         s_axi_rdata,
    output logic [1:0]                            s_axi_rresp,
    output logic                                  s_axi_rvalid,
    input  logic                                  s_axi_rready
);

    // Register Offsets
    localparam ADDR_CONTROL     = 6'h00;
    localparam ADDR_MODE        = 6'h04;
    localparam ADDR_OPERAND_A   = 6'h08;
    localparam ADDR_OPERAND_B   = 6'h0C;
    localparam ADDR_STATUS      = 6'h10;
    localparam ADDR_RESULT_LOW  = 6'h14;
    localparam ADDR_RESULT_HIGH = 6'h18;

    // Internal Slave Registers
    logic [31:0] slv_reg_control;
    logic [31:0] slv_reg_mode;
    logic [31:0] slv_reg_op_a;
    logic [31:0] slv_reg_op_b;

    // Handshake and State Signals
    logic aw_en;
    logic axi_awready_reg;
    logic axi_wready_reg;
    logic [1:0] axi_bresp_reg;
    logic axi_bvalid_reg;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr_reg;
    logic axi_arready_reg;
    logic [C_S_AXI_DATA_WIDTH-1:0] axi_rdata_reg;
    logic [1:0] axi_rresp_reg;
    logic axi_rvalid_reg;

    assign s_axi_awready = axi_awready_reg;
    assign s_axi_wready  = axi_wready_reg;
    assign s_axi_bresp   = axi_bresp_reg;
    assign s_axi_bvalid  = axi_bvalid_reg;
    assign s_axi_arready = axi_arready_reg;
    assign s_axi_rdata   = axi_rdata_reg;
    assign s_axi_rresp   = axi_rresp_reg;
    assign s_axi_rvalid  = axi_rvalid_reg;

    // MAC Core Interconnect Signals
    logic        mac_rst;
    logic        mac_enable;
    logic        mac_in_valid;
    logic        mac_precision_mode;
    logic [15:0] mac_operand_a;
    logic [15:0] mac_operand_b;
    logic        mac_acc_clear;
    logic signed [39:0] mac_result;
    logic        mac_out_valid;
    logic        mac_overflow;

    // Auto-clearing trigger for in_valid and acc_clear
    logic in_valid_pulse;
    logic acc_clear_pulse;

    assign mac_rst            = ~s_axi_aresetn | slv_reg_control[2];
    assign mac_enable         = slv_reg_control[0];
    assign mac_acc_clear      = acc_clear_pulse;
    assign mac_in_valid       = in_valid_pulse;
    assign mac_precision_mode = slv_reg_mode[0];
    assign mac_operand_a      = slv_reg_op_a[15:0];
    assign mac_operand_b      = slv_reg_op_b[15:0];

    // Instantiate MAC Core
    mac_top #(
        .ENABLE_ISOLATION (1'b1),
        .SATURATION_ENABLE(1'b0),
        .USE_DSP          ("yes")
    ) u_mac_core (
        .clk               (s_axi_aclk),
        .rst               (mac_rst),
        .enable            (mac_enable),
        .in_valid          (mac_in_valid),
        .precision_mode    (mac_precision_mode),
        .operand_a         (mac_operand_a),
        .operand_b         (mac_operand_b),
        .acc_clear         (mac_acc_clear),
        .accumulator_result(mac_result),
        .out_valid         (mac_out_valid),
        .overflow_status   (mac_overflow)
    );

    // Write Address Channel Handshake
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            axi_awready_reg <= 1'b0;
            aw_en           <= 1'b1;
            axi_awaddr_reg  <= '0;
        end else begin
            if (~axi_awready_reg && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                axi_awready_reg <= 1'b1;
                aw_en           <= 1'b0;
                axi_awaddr_reg  <= s_axi_awaddr;
            end else if (s_axi_bready && axi_bvalid_reg) begin
                aw_en           <= 1'b1;
                axi_awready_reg <= 1'b0;
            end else begin
                axi_awready_reg <= 1'b0;
            end
        end
    end

    // Write Data Channel Handshake
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            axi_wready_reg <= 1'b0;
        end else begin
            if (~axi_wready_reg && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                axi_wready_reg <= 1'b1;
            end else begin
                axi_wready_reg <= 1'b0;
            end
        end
    end

    // Register Writes and Pulse Generation
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            slv_reg_control <= 32'h00000001; // Enable by default
            slv_reg_mode    <= 32'h00000000;
            slv_reg_op_a    <= 32'h00000000;
            slv_reg_op_b    <= 32'h00000000;
            in_valid_pulse  <= 1'b0;
            acc_clear_pulse <= 1'b0;
        end else begin
            // Pulses default to 0 every clock cycle
            in_valid_pulse  <= 1'b0;
            acc_clear_pulse <= 1'b0;

            if (axi_wready_reg && s_axi_wvalid && axi_awready_reg && s_axi_awvalid) begin
                case (axi_awaddr_reg[5:0])
                    ADDR_CONTROL: begin
                        slv_reg_control <= s_axi_wdata;
                        if (s_axi_wdata[1]) acc_clear_pulse <= 1'b1;
                        if (s_axi_wdata[3]) in_valid_pulse  <= 1'b1;
                    end
                    ADDR_MODE: begin
                        slv_reg_mode <= s_axi_wdata;
                    end
                    ADDR_OPERAND_A: begin
                        slv_reg_op_a <= s_axi_wdata;
                    end
                    ADDR_OPERAND_B: begin
                        slv_reg_op_b <= s_axi_wdata;
                        // Trigger computation automatically upon writing OPERAND_B
                        in_valid_pulse <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Write Response Channel
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            axi_bvalid_reg <= 1'b0;
            axi_bresp_reg  <= 2'b00; // OKAY
        end else begin
            if (axi_awready_reg && s_axi_awvalid && ~axi_bvalid_reg && axi_wready_reg && s_axi_wvalid) begin
                axi_bvalid_reg <= 1'b1;
                axi_bresp_reg  <= 2'b00;
            end else if (s_axi_bready && axi_bvalid_reg) begin
                axi_bvalid_reg <= 1'b0;
            end
        end
    end

    // Read Address Channel Handshake
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            axi_arready_reg <= 1'b0;
        end else begin
            if (~axi_arready_reg && s_axi_arvalid) begin
                axi_arready_reg <= 1'b1;
            end else begin
                axi_arready_reg <= 1'b0;
            end
        end
    end

    // Read Data Channel
    always_ff @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            axi_rvalid_reg <= 1'b0;
            axi_rresp_reg  <= 2'b00;
            axi_rdata_reg  <= 32'd0;
        end else begin
            if (axi_arready_reg && s_axi_arvalid && ~axi_rvalid_reg) begin
                axi_rvalid_reg <= 1'b1;
                axi_rresp_reg  <= 2'b00; // OKAY
                case (s_axi_araddr[5:0])
                    ADDR_CONTROL:     axi_rdata_reg <= slv_reg_control;
                    ADDR_MODE:        axi_rdata_reg <= slv_reg_mode;
                    ADDR_OPERAND_A:   axi_rdata_reg <= slv_reg_op_a;
                    ADDR_OPERAND_B:   axi_rdata_reg <= slv_reg_op_b;
                    ADDR_STATUS:      axi_rdata_reg <= {29'd0, mac_overflow, mac_out_valid, 1'b0};
                    ADDR_RESULT_LOW:  axi_rdata_reg <= mac_result[31:0];
                    ADDR_RESULT_HIGH: axi_rdata_reg <= {{24{mac_result[39]}}, mac_result[39:32]};
                    default:          axi_rdata_reg <= 32'hDEADBEEF;
                endcase
            end else if (axi_rvalid_reg && s_axi_rready) begin
                axi_rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
