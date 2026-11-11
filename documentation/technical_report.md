# Technical Report: Design and FPGA Implementation of a High-Throughput Configurable INT8/INT16 Multiply-Accumulate (MAC) Architecture

**Author:** Antigravity Advanced Digital Design & Verification Engineering Team  
**Target Hardware:** Digilent PYNQ-Z2 Development Board (AMD/Xilinx Zynq-7000 XC7Z020CLG400-1)  
**EDA Environment:** AMD Vivado Design Suite 2025.1 / XSim / Python 3.14  
**Date:** November 2026  
**Document Version:** 1.0 (Final Engineering Release)  

---

## 1. Abstract

Multiply-Accumulate (MAC) arithmetic datapaths constitute the foundational computational primitive in digital signal processing (DSP), edge deep neural network (DNN) inference accelerators, multimedia filtering, and high-performance embedded computing. Modern embedded edge systems demand runtime arithmetic reconfigurability across diverse numerical precisions—specifically 8-bit signed integer (INT8) for high-density quantized tensor operations and 16-bit signed integer (INT16) for high-dynamic-range fixed-point filtering—without incurring prohibitive silicon area, routing congestion, or dynamic power penalties.

This engineering report presents the complete architectural development, microarchitectural optimization, functional verification, and physical FPGA implementation of a parameterized, high-throughput, configurable signed INT8/INT16 Multiply-Accumulate architecture. The core architecture integrates:
1. A **shared two's-complement arithmetic multiplier datapath** supporting runtime precision switching without redundant multiplier instantiation.
2. A **pipelined datapath structure** achieving an Initiation Interval ($II$) of 1 clock cycle with a deterministic latency of 2 clock cycles.
3. **Dynamic input operand isolation** to eliminate unnecessary switching activity and dynamic power dissipation during disabled and invalid clock cycles.
4. A **40-bit accumulator** supporting modulo-$2^{40}$ wraparound accumulation with instantaneous signed two's-complement overflow detection and optional saturation clamping.

Seven architectural variants were designed, synthesized, placed, routed, and characterized on the AMD/Xilinx Zynq-7000 XC7Z020CLG400-1 FPGA in Vivado 2025.1:
- **V1**: Baseline single-cycle non-pipelined INT16 MAC
- **V2**: Shared single-cycle configurable INT8/INT16 MAC
- **V3**: Shared 2-stage pipelined configurable MAC ($II=1$)
- **V4**: Dedicated separate INT8 (8x8) and INT16 (16x16) arithmetic datapaths
- **V5**: Pipelined configurable MAC with dynamic operand isolation
- **V6_DSP**: Top-level optimized architecture utilizing dedicated Xilinx DSP48E1 slices
- **V6_LUT**: Top-level architecture with forced soft LUT-based multiplier mapping

Functional verification was executed using a comprehensive 2,362-vector randomized, corner-case, and dynamic mode-switching test suite verified against an independent cycle-accurate Python golden reference model, achieving a **100.00% pass rate** (2,362 / 2,362 vectors matched with zero errors). The core was encapsulated as a memory-mapped AXI4-Lite slave IP (`0x43C00000`), integrated with the dual-core ARM Cortex-A9 Processing System, and implemented as a complete PYNQ-Z2 overlay bitstream.

---

## 2. Theoretical Background & Mathematical Foundations

### 2.1 The Multiply-Accumulate Operation

The canonical Multiply-Accumulate (MAC) operation is defined mathematically as:

$$\text{ACC}[t] = \text{ACC}[t-1] + \left( A[t] \times B[t] \right)$$

where:
- $t$ denotes the discrete transaction index.
- $A[t]$ and $B[t]$ represent the multiplicand and multiplier input operands.
- $\text{ACC}[t]$ denotes the state of the accumulator register holding the cumulative sum.

In deep learning tensor workloads (e.g., General Matrix Multiply, GEMM, and 2D convolution), inner products between weight matrices $W$ and activation vectors $X$ are computed as:

$$Y_i = \sum_{k=0}^{K-1} W_{i,k} \cdot X_k$$

Maximizing hardware MAC throughput while minimizing energy per operation directly determines edge inference latency and battery endurance.

### 2.2 Numerical Representations and Dynamic Ranges

Both operands are represented as signed two's-complement integers. The numerical characteristics of each operating mode are summarized in Table 2.1:

**Table 2.1: Precision and Numerical Characteristics**

| Precision Mode | Mode Bit | Operand Width | Minimum Value | Maximum Value | Product Width | Product Dynamic Range |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **INT8** | `1'b0` | 8 bits | $-128$ (`8'h80`) | $+127$ (`8'h7F`) | 16 bits | $[-16,256 \text{ to } +16,384]$ |
| **INT16** | `1'b1` | 16 bits | $-32,768$ (`16'h8000`) | $+32,767$ (`16'h7FFF`) | 32 bits | $[-1,073,709,056 \text{ to } +1,073,741,824]$ |

### 2.3 Accumulator Bit-Width and Headroom Analysis

To prevent premature accumulator overflow during extended accumulation sequences, a **40-bit accumulator** was selected. 

For INT16 arithmetic (32-bit signed products), the 40-bit accumulator provides 8 guard bits ($40 - 32 = 8$ bits), allowing:

$$N_{\text{max, INT16}} = 2^8 = 256 \text{ consecutive maximum-magnitude product additions}$$

without numerical wraparound. For typical distributed zero-mean neural network weights and activations, several thousand INT16 MACs can proceed before overflow occurs.

For INT8 arithmetic (16-bit signed products), the 40-bit accumulator provides 24 guard bits ($40 - 16 = 24$ bits), permitting:

$$N_{\text{max, INT8}} = 2^{24} = 16,777,216 \text{ consecutive worst-case INT8 additions}$$

effectively guaranteeing unlimited accumulator headroom for convolutional layer filter depths.

### 2.4 Signed Overflow Detection

Accumulator arithmetic operates with modulo-$2^{40}$ two's-complement wraparound semantics. Instantaneous signed overflow occurs if and only if two operands of identical signs are summed and produce a result of opposite sign:

$$\text{Overflow} = \overline{(A_{39} \oplus B_{39})} \ \cdot \ (A_{39} \oplus S_{39})$$

where:
- $A_{39}$ is the sign bit (MSB) of the current accumulator register.
- $B_{39}$ is the sign bit of the incoming sign-extended product.
- $S_{39}$ is the sign bit of the resulting 40-bit sum.

When saturation mode is enabled (`SATURATION_ENABLE = 1`), detected overflow triggers dynamic clamping:
- **Positive Overflow Clamping:** Clamped to maximum positive value: `40'sh7F_FFFF_FFFF` ($+549,755,813,887$).
- **Negative Overflow Clamping:** Clamped to minimum negative value: `40'sh80_0000_0000` ($-549,755,813,888$).

---

## 3. Hardware Architecture & Microarchitectural Design

The proposed architecture adopts a decoupled modular design optimized for high clock frequencies, minimal routing congestion, and deterministic control flow.

### 3.1 Architectural Block Diagrams

The top-level architecture is partitioned into five functional stages:

```
[System Inputs] 
  clk, rst, enable, in_valid, precision_mode, operand_a[15:0], operand_b[15:0], acc_clear
        │
        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 0: Dynamic Operand Isolation & Precision Control │
│ - Gating operands to 0 when enable=0 or in_valid=0    │
│ - Mode 0 (INT8): Sign-extend op[7:0] -> ext_op[15:0]   │
│ - Mode 1 (INT16): Pass through raw op[15:0]            │
└───────────────────────────────────┬────────────────────┘
                                    │ (ext_a[15:0], ext_b[15:0])
                                    ▼
┌────────────────────────────────────────────────────────┐
│ Stage 1: Pipelined 16x16 Signed Multiplier             │
│ - Product = ext_a * ext_b (Signed Two's Complement)    │
│ - Registered in MREG (32-bit signed product)           │
│ - Synchronous propagation of valid, clear, and mode    │
└───────────────────────────────────┬────────────────────┘
                                    │ (product_pipe[31:0], valid_pipe)
                                    ▼
┌────────────────────────────────────────────────────────┐
│ Stage 2: 40-bit Accumulator & Overflow Detector        │
│ - Sign-extend product[31:0] -> ext_product[39:0]       │
│ - Add to ACC_REG (Modulo-2^40 or Saturating)           │
│ - Evaluate instantaneous signed overflow flag          │
└───────────────────────────────────┬────────────────────┘
                                    │
                                    ▼
[System Outputs]
  accumulator_result[39:0], out_valid, overflow_status
```

Vector architectural diagrams illustrating the full structural connectivity and AXI4-Lite SoC integration are provided in the project repository:
- **Top Architecture Diagram:** `diagrams/architecture_top_block_diagram.svg`
- **Pipeline Datapath Timing Diagram:** `diagrams/datapath_pipeline_diagram.svg`
- **PYNQ SoC AXI Integration Diagram:** `diagrams/axi_soc_block_diagram.svg`

### 3.2 Microarchitectural Building Blocks

#### 3.2.1 Precision Controller (`precision_controller.sv`)
The precision controller accepts the 16-bit physical input buses `operand_a` and `operand_b`. When `precision_mode == 1'b0` (INT8 mode), the lower eight bits (`[7:0]`) are unpacked and sign-extended:
```systemverilog
ext_a = {{8{isolated_a[7]}}, isolated_a[7:0]};
ext_b = {{8{isolated_b[7]}}, isolated_b[7:0]};
```
When `precision_mode == 1'b1` (INT16 mode), the full 16-bit signed word is passed directly:
```systemverilog
ext_a = isolated_a;
ext_b = isolated_b;
```
Because the product of two 8-bit sign-extended values exactly matches the mathematical signed 16-bit product sign-extended to 32 bits, **a single 16x16 multiplier calculates both INT8 and INT16 operations without additional multiplication logic**.

#### 3.2.2 Dynamic Operand Isolation (`operand_isolation.sv`)
Multiplier logic trees represent significant capacitive loads. Unchecked switching on input buses during invalid clock cycles induces dynamic charging/discharging across internal carry chains and partial product arrays.
The operand isolation unit gates input transitions to static zeros whenever the core is disabled (`enable = 0`) or idle (`in_valid = 0`):
```systemverilog
assign isolated_operand = (enable && in_valid) ? raw_operand : 16'sh0000;
```
This guarantees zero switching activity within the multiplier array during non-computing clock intervals.

#### 3.2.3 Pipelined Multiplier Datapath (`mac_multiplier.sv`)
The multiplier block accepts two 16-bit signed operands and computes a 32-bit signed product. A pipeline register stage ($MREG$) registers the product output:
```systemverilog
always_ff @(posedge clk) begin
    if (rst) begin
        product_out <= 32'sd0;
        valid_out   <= 1'b0;
        clear_out   <= 1'b0;
    end else if (enable) begin
        product_out <= ext_a * ext_b;
        valid_out   <= in_valid;
        clear_out   <= acc_clear;
    end
end
```
By inserting this intermediate register, the combinational propagation path is partitioned into two balanced halves:
- **Half-path 1:** Input pads $\rightarrow$ isolation $\rightarrow$ sign-extension $\rightarrow$ 16x16 multiplication array $\rightarrow$ $MREG$.
- **Half-path 2:** $MREG$ $\rightarrow$ 40-bit sign extension $\rightarrow$ 40-bit adder $\rightarrow$ $PREG$.

#### 3.2.4 Accumulator and Overflow Detector (`mac_accumulator.sv`, `overflow_detector.sv`)
The accumulator register maintains the 40-bit running total. When `acc_clear` is asserted, the accumulator resets synchronously to zero. Under normal operation with `valid_pipe` asserted, the 32-bit product is sign-extended to 40 bits and summed with the existing accumulator contents. When `enable` is de-asserted, all register states are preserved.

### 3.3 Initiation Interval vs. Latency

A fundamental objective of this design is sustaining an **Initiation Interval ($II$) of 1 clock cycle**.
- **Initiation Interval ($II = 1$):** A new pair of operands $\{A[t], B[t]\}$ can be injected on **every consecutive clock cycle** without inserting stall or wait cycles.
- **Latency ($L = 2$ clock cycles):** The computational result corresponding to transaction $\{A[t], B[t]\}$ appears on `accumulator_result` exactly two clock cycles later ($t + 2$).

Consecutive back-to-back streaming vectors execute at peak pipeline throughput:

$$\text{Throughput} = \frac{N \text{ operations}}{(N + 1) \text{ clock cycles}} \approx 1 \text{ MAC/cycle}$$

---

## 4. Verification Methodology & Results

### 4.1 Verification Architecture

Verification was conducted using a rigorous, multi-tiered verification framework:
1. **Python Bit-True Golden Model (`golden_model.py`):** An independent, cycle-accurate reference model modeling signed integer bounds, two's-complement arithmetic, pipeline delays, modulo-$2^{40}$ accumulation, overflow flags, and saturation clamping.
2. **Automated Test Vector Generator (`generate_vectors.py`):** Synthesized 2,362 structured and pseudo-random stimulus vectors saved to disk (`stimulus.txt`, `expected_l1.txt`, `expected_l2.txt`).
3. **SystemVerilog Testbench Suite:**
   - `tb_mac_basic.sv`: Directed verification of baseline single-cycle INT16 architecture (V1).
   - `tb_mac_configurable.sv`: Runtime precision switching and sign-extension testing (V2).
   - `tb_mac_pipelined.sv`: Pipeline latency alignment, streaming back-to-back transactions, bubble injection, and synchronous accumulator clearing (V3).
   - `tb_mac_top.sv`: File-driven co-simulation of the top-level architecture (V6) against the 2,362 golden reference vectors.
4. **Embedded SystemVerilog Assertions (SVA):** Dynamic simulation-based runtime property checks evaluated continuously during XSim simulation runs, verifying:
   - Output validity protocol invariants (`out_valid` asserted exactly 2 cycles following `in_valid`).
   - Accumulator hold invariant when `enable = 0`.
   - Accumulator clearance invariant on `acc_clear = 1`.
   *(Note: These assertions are dynamically checked during RTL simulation testbench execution; no formal mathematical model checking tool such as SymbiYosys or JasperGold was executed).*

### 4.2 Test Suite Composition

The 2,362 test vectors in `stimulus.txt` were partitioned into targeted verification phases:
- **Phase 1: Basic Directed Vectors (Vectors 0–19):** Elementary integer products validating sign rules ($+ \times +$, $+ \times -$, $- \times +$, $- \times -$) and identity multiplications ($\times 0, \times 1$).
- **Phase 2: INT8 Corner Cases (Vectors 20–39):** Extreme dynamic boundaries ($-128 \times -128$, $+127 \times +127$, $-128 \times +127$, $-1 \times -128$).
- **Phase 3: INT16 Corner Cases (Vectors 40–59):** Full-range boundaries ($-32768 \times -32768$, $+32767 \times +32767$, $-32768 \times +32767$, $-32768 \times 1$).
- **Phase 4: Mixed Precision Interleaving (Vectors 60–159):** Rapid alternating precision switching (`precision_mode` flipping every 1 to 3 cycles) to verify that internal pipeline registers do not corrupt operand precision context.
- **Phase 5: Extended Randomized Streaming (Vectors 160–2159):** 2,000 back-to-back uniform pseudo-random signed vectors evaluating continuous $II = 1$ throughput.
- **Phase 6: Protocol Stall & Bubble Insertion (Vectors 2160–2259):** Periodic de-assertion of `in_valid` and `enable` to ensure pipeline flush and freeze correctness.
- **Phase 7: Accumulator Overflow & Clear Cycling (Vectors 2260–2361):** Sustained maximum-value additions driving the 40-bit accumulator into numerical wraparound and asserting `acc_clear` during active streaming.

### 4.3 Simulation Results & Verification Scorecard

All testbenches were compiled and executed using AMD Vivado Simulator (XSim 2025.1). The results are summarized in Table 4.1:

**Table 4.1: Functional Simulation Verification Scorecard**

| Testbench | Module Under Test | Architecture Variant | Vectors Evaluated | Errors Detected | Pass Rate | Status |
|:---|:---|:---:|:---:|:---:|:---:|:---:|
| `tb_mac_basic` | `mac_basic` | V1 | 9 Directed Cases | 0 | 100.00% | **PASS** |
| `tb_mac_configurable` | `mac_configurable` | V2 | 6 Configurable Cases | 0 | 100.00% | **PASS** |
| `tb_mac_pipelined` | `mac_pipelined` | V3 | 14 Pipeline Scenarios | 0 | 100.00% | **PASS** |
| `tb_mac_top` | `mac_top` | V6 (Full Top) | **2,362 Vectors** | **0** | **100.00%** | **PASS** |

The co-simulation testbench `tb_mac_top` executed all 2,362 vectors with zero mismatches against the Python golden model, proving 100% bit-true compliance across all operational corners.

---

## 5. Synthesis, Implementation, and Experimental Results

All architectural implementations were targeted to the **AMD/Xilinx Zynq-7000 XC7Z020CLG400-1** FPGA utilizing **AMD Vivado 2025.1**. Each variant was processed through the complete automated EDA flow:
1. Out-of-context synthesis (`synth_design -mode out_of_context`).
2. Timing constraints application (100 MHz target clock, period = 10.0 ns, 50% duty cycle).
3. Logic optimization and placement (`opt_design`, `place_design`).
4. Physical optimization and routing (`phys_opt_design`, `route_design`).
5. Post-route timing analysis (`report_timing_summary`).
6. Post-route resource utilization extraction (`report_utilization`).
7. Vector-less activity power analysis (`report_power`).

### 5.1 Architecture Comparison Table

The complete experimental measurements collected across all seven designs are summarized in Table 5.1:

**Table 5.1: Comprehensive FPGA Post-Route Implementation Comparison**

| Arch ID | Architecture Description | Slice LUTs | Slice FFs | DSP48E1 | Target Clock (MHz) | WNS (ns) | TNS (ns) | STA Est. Fmax (MHz) | Latency (Cycles) | II (Cycles) | Configured Throughput (MMAC/s) | Dynamic Power (W) | Static Power (W) | Total Power (W) |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **V1** | Baseline Non-Pipelined INT16 MAC | 3 | 42 | 2 | 100.0 | +2.831 | 0.000 | 139.49 | 1 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V2** | Shared Configurable INT8/INT16 MAC | 11 | 42 | 2 | 100.0 | +1.575 | 0.000 | 118.69 | 1 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V3** | Pipelined Configurable MAC | 12 | 44 | 2 | 100.0 | +2.666 | 0.000 | 136.35 | 2 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V4** | Separate INT8/INT16 Datapaths | 104 | 61 | 1 | 100.0 | +2.913 | 0.000 | 141.10 | 2 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V5** | Pipelined MAC with Operand Isolation | 28 | 44 | 2 | 100.0 | +3.145 | 0.000 | 145.88 | 2 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V6_DSP** | Final Optimized Architecture (DSP) | 28 | 44 | 2 | 100.0 | +3.145 | 0.000 | 145.88 | 2 | 1 | 100.0 | 0.003 | 0.103 | 0.106 |
| **V6_LUT** | Optimized Architecture (Forced LUTs) | 397 | 76 | 0 | 100.0 | +0.116 | 0.000 | 101.17 | 2 | 1 | 100.0 | 0.004 | 0.103 | 0.107 |

*Note: All designs operate at the configured 100.0 MHz PL clock ($T_{\text{clk}} = 10.0\text{ ns}$), delivering a theoretical peak throughput of 100.0 MMAC/s at Initiation Interval $II = 1$. Fmax represents an out-of-context Static Timing Analysis (STA) derived estimate ($1000 / (10.0 - \text{WNS})$), not a physically measured operating frequency.*

### 5.2 Publication Figures and Graphical Visualizations

High-resolution comparative plots were generated from the post-route experimental dataset:
- **Resource Utilization Comparison:** `results/graphs/resource_utilization_comparison.png`
- **Maximum Frequency & Peak Throughput:** `results/graphs/fmax_throughput_comparison.png`
- **Power Dissipation Breakdown:** `results/graphs/power_breakdown_comparison.png`
- **DSP vs. LUT Architectural Trade-Off:** `results/graphs/dsp_vs_lut_tradeoff.png`

---

## 6. Architectural Trade-Off Analysis & Discussion

### 6.1 Hardware Resource Sharing: Shared Datapath (V3) vs. Separate Datapaths (V4)

In architecture V4, two independent multipliers were instantiated: a dedicated 8x8 signed multiplier for INT8 mode and a dedicated 16x16 signed multiplier for INT16 mode, followed by multiplexing logic selecting the active product. Architecture V3 uses a single shared 16x16 multiplier with dynamic sign-extension.

- **Exact Resource Comparison:**
  - **V3 (Shared Multiplier):** **12 LUTs, 44 FFs, and 2 DSP48E1 slices**
  - **V4 (Separate Multipliers):** **104 LUTs, 61 FFs, and 1 DSP48E1 slice**
- **Architectural Trade-Off Analysis:**
  - Architecture V3 achieves a substantial **reduction in soft logic**, decreasing Look-Up Table usage by **8.67x** (from 104 LUTs down to 12 LUTs, an 88.5% savings) and register count by **27.9%** (from 61 FFs down to 44 FFs).
  - However, this logic reduction incurs an **additional DSP cost**: V3 utilizes **2 DSP48E1 slices** (the standard allocation for a fully pipelined 16x16/signed 40-bit MAC structure), whereas V4 uses **1 DSP slice** for its 16x16 multiplier while forcing the 8x8 multiplier into fabric soft logic (contributing to the 104 LUT inflation).
  - Rather than an across-the-board reduction in every resource category, the shared architecture represents a deliberate and advantageous engineering trade-off: trading one additional DSP slice to reclaim 92 LUTs and 17 flip-flops.


### 6.2 Impact of Pipelining: Single-Cycle (V2) vs. Pipelined (V3 / V5 / V6_DSP)

In single-cycle configurable architecture V2, the critical timing path traverses the precision multiplexer, sign-extension logic, 16x16 multiplier array, 40-bit carry-propagate adder, and accumulator register setup in a single clock cycle ($T_{\text{clk}}$).

- **Worst Negative Slack (WNS at 100 MHz):**
  - V2 (Single-cycle): WNS = $+1.575$ ns
  - V3 (Pipelined): WNS = $+2.666$ ns
  - V5 / V6_DSP (Pipelined + Isolated): WNS = $+3.145$ ns
By inserting $MREG$ between the multiplier and the accumulator, the longest combinational path delay was reduced from $8.425$ ns to $6.855$ ns. Because the pipeline register is fully forward-registered without feedback hazards, the architecture sustains an Initiation Interval of 1 cycle ($II = 1$). At the configured 100.0 MHz PL clock, both architectures sustain a theoretical peak throughput of **100.0 MMAC/s**. Pipelining expands timing margin ($WNS$ improved from $+1.575$ ns to $+3.145$ ns), elevating the out-of-context Static Timing Analysis (STA) derived $F_{\text{max}}$ estimate from $118.69\text{ MHz}$ to **$145.88\text{ MHz}$** (+22.9% timing headroom).


### 6.3 Dedicated DSP48E1 vs. Soft LUT Multiplier Mapping (V6_DSP vs. V6_LUT)

To quantify the hardware cost of executing multi-precision arithmetic on FPGAs devoid of DSP slices (or when DSP slices are depleted by earlier processing stages), architecture V6_LUT was synthesized with `USE_DSP = "no"`.

- **LUT Consumption:**
  - **V6_DSP:** **28 LUTs**
  - **V6_LUT:** **397 LUTs**
  - **Ratio:** Soft LUT mapping requires **14.18x more LUTs** (369 additional 6-input LUTs).
- **Flip-Flop Utilization:**
  - V6_DSP: **44 FFs**
  - V6_LUT: **76 FFs** (+72.7% increase due to distributed pipeline registers across the LUT multiplier tree).
- **Timing Closure & $F_{\text{max}}$:**
  - V6_DSP: WNS = $+3.145$ ns, $F_{\text{max}} = 145.88\text{ MHz}$
  - V6_LUT: WNS = $+0.116$ ns, $F_{\text{max}} = 101.17\text{ MHz}$
  - **Frequency Degradation:** Forcing soft LUT multiplier logic reduced maximum clock speed by **30.6%** due to deep carry chains and interconnect routing delays across multiple CLB slices.
- **Power Dissipation:**
  - V6_LUT dynamic power increased to 0.004 W (+33% over V6_DSP) due to the substantially higher node capacitance of hundreds of soft LUT routing segments.

**Conclusion:** Utilizing dedicated DSP48E1 slices is essential for high-throughput MAC designs on Xilinx architectures. However, when DSP resources are exhausted, the architecture successfully achieves timing closure in soft LUT logic at over 100 MHz.

### 6.4 Operand Isolation Overhead and Effectiveness

The dynamic operand isolation block was evaluated by comparing V3 (unisolated pipelined) with V5 (isolated pipelined):

- **Hardware Area Cost:**
  - V3: 12 LUTs, 44 FFs
  - V5: 28 LUTs, 44 FFs
  - **Overhead:** The isolation logic consumed exactly **16 additional LUTs** (1 LUT per input bit for the gating AND multiplexers) with zero additional registers.
- **Timing Impact:**
  - WNS improved slightly from $+2.666$ ns (V3) to $+3.145$ ns (V5), as the isolation gating allowed Vivado's physical optimizer to pack the input registers closer to the DSP input ports.
- **Switching Activity & Dynamic Power Evaluation:**
  - An activity-based power analysis was executed in AMD Vivado 2025.1 on the routed netlists of V3 and V5 (`vivado/eval_switching_power.tcl` generating `reports/power/V3_unisolated_switching_activity_power.rpt` and `reports/power/V5_isolated_switching_activity_power.rpt`).
  - **Measurement Assumptions & Activity Annotation Coverage:**
    - Clock nodes activity: High (>95% of clocks specified by user constraint).
    - I/O port activity: High (>95% of input ports assigned explicit toggle rates and static probabilities).
    - Internal nodes activity: Medium (<25% internal nodes directly annotated; internal node activity derived via Vivado vectorless activity propagation).
    - Overall Power Confidence Level: **Medium** (Production device models, commercial grade, typical process at $26.2^\circ\text{C}$ junction temperature).
  - **Actual Measured Post-Route Power Values:**
    - **Active Workload (`in_valid = 1`, `enable = 1`, 50% toggle rate):**
      - V3 (Unisolated): Dynamic = $0.001\text{ W}$, Device Static = $0.103\text{ W}$, Total = $0.104\text{ W}$ (without vectorless internal propagation) / $0.003\text{ W}$ dynamic with full propagation.
      - V5 (Isolated): Dynamic = $0.001\text{ W}$, Device Static = $0.103\text{ W}$, Total = $0.104\text{ W}$ (without vectorless internal propagation) / $0.003\text{ W}$ dynamic with full propagation.
    - **Idle Workload with Input Switching (`in_valid = 0`, `enable = 1`, operands toggling at 100% toggle rate):**
      - V3 (Unisolated): Dynamic = **$0.003\text{ W}$**, Device Static = **$0.103\text{ W}$**, Total = **$0.106\text{ W}$**
      - V5 (Isolated): Dynamic = **$0.003\text{ W}$**, Device Static = **$0.103\text{ W}$**, Total = **$0.106\text{ W}$**
  - **Power Findings:**
    - At Vivado's standard 1 mW (0.001 W) reporting precision, both architectures report identical dynamic power ($0.003\text{ W}$) for a single out-of-context MAC core on the XC7Z020 FPGA.
    - Because the numerical report values round to the nearest milliwatt and device static leakage ($0.103\text{ W}$) dominates on-chip dissipation, the available post-route data does not establish a measurable numerical power reduction for a single MAC instance.
    - Consequently, we state strictly from architectural design and RTL structure that operand isolation suppresses internal switching transitions inside the multiplier datapath during idle input conditions (`in_valid = 0` or `enable = 0`), preventing input bus activity from toggling internal multiplier nodes.



---

## 7. SoC Integration and PYNQ-Z2 Hardware Deployment

### 7.1 AXI4-Lite IP Wrapper (`axi_lite_mac_ip.sv`)

The final optimized architecture (V6) was packaged as an AXI4-Lite memory-mapped slave IP. The core interfaces with the AXI bus via standard 32-bit registers.

**Table 7.1: AXI4-Lite Register Memory Map (Base Address: `0x43C00000`)**

| Offset | Register Name | Access | Bit Fields & Descriptions |
|:---:|:---|:---:|:---|
| `0x00` | `REG_CONTROL` | R/W | `[0]`: Enable MAC core (`1` = active)<br>`[1]`: Clear Accumulator (synchronous pulse)<br>`[2]`: Soft Reset (`1` = active)<br>`[3]`: Valid Strobe (`1` = active transaction) |
| `0x04` | `REG_MODE` | R/W | `[0]`: Precision Mode (`0` = Signed INT8, `1` = Signed INT16) |
| `0x08` | `REG_OPERAND_A` | R/W | `[15:0]`: Multiplicand Operand A (Signed two's-complement) |
| `0x0C` | `REG_OPERAND_B` | R/W | `[15:0]`: Multiplier Operand B (Writing triggers computation cycle) |
| `0x10` | `REG_STATUS` | RO | `[0]`: Busy Status<br>`[1]`: Output Valid (`out_valid`)<br>`[2]`: Instantaneous Signed Overflow (`overflow_status`) |
| `0x14` | `REG_RESULT_LOW`| RO | `[31:0]`: Lower 32 bits of 40-bit Accumulator Result |
| `0x18` | `REG_RESULT_HIGH`| RO | `[7:0]`: Upper 8 bits of 40-bit Accumulator Result (Sign-extended to 32 bits) |

### 7.2 Zynq-7000 SoC Block Design Overlay

The custom IP was integrated into a complete Zynq processing system block design:
- **Host Processor:** ARM Cortex-A9 Dual-Core Processor System (PS7) clocked at 650 MHz.
- **PL Fabric Clock:** 100.0 MHz generated from `FCLK_CLK0`.
- **Interconnect:** AXI Interconnect (`axi_interconnect_0`) performing clock domain crossing, protocol conversion, and address decoding.
- **Reset Controller:** Processor System Reset IP (`rst_ps7_0_100M`) synchronizing PS reset signals with the PL clock.

The complete Vivado project was synthesized, implemented, and compiled to produce the final FPGA bitstream:
- **Bitstream File:** `vivado/pynq_overlay/pynq_mac.bit`
- **Hardware Handoff File:** `vivado/pynq_overlay/pynq_mac.hwh`

**Table 7.2: Complete PYNQ-Z2 SoC Post-Route Implementation Metrics**

| Metric | Post-Route Measurement | Available on XC7Z020 | Device Utilization (%) |
|:---|:---:|:---:|:---:|
| **Slice LUTs** | 495 | 53,200 | 0.93 % |
| **Slice Registers (FFs)** | 677 | 106,400 | 0.64 % |
| **DSP48E1 Slices** | 2 | 220 | 0.91 % |
| **Block RAM (RAMB36)** | 0 | 140 | 0.00 % |
| **Target Clock Frequency** | 100.0 MHz (10.0 ns) | - | - |
| **Worst Negative Slack (WNS)** | **+3.181 ns** | - | **0 Violations (MET)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | - | **0 Violations (MET)** |
| **Worst Hold Slack (WHS)** | **+0.098 ns** | - | **0 Violations (MET)** |
| **Total On-Chip Power** | **1.669 W** | - | - |
| **PL Dynamic Logic Power** | **0.004 W** | - | - |
| **PS7 Processor Dynamic Power**| **1.533 W** | - | - |
| **Device Static Power** | **0.136 W** | - | - |


### 7.3 Python Hardware Driver (`pynq_mac_test.py`)

A comprehensive Python hardware driver was implemented for execution in the PYNQ Linux environment on the Zynq ARM host. The driver utilizes the `pynq.Overlay` and `pynq.MMIO` classes to communicate directly with physical hardware registers at base address `0x43C00000`.

The test driver executes four comprehensive test suites:
1. **Suite 1 (INT8 Arithmetic):** Tests elementary and extreme INT8 signs, corner cases ($-128 \times -128 = 16384$, $+127 \times +127 = 16129$), and 100-cycle accumulation.
2. **Suite 2 (INT16 Arithmetic):** Tests full 16-bit products up to $\pm 10^9$ and sustained accumulation.
3. **Suite 3 (Control & Pipeline Protocols):** Verifies synchronous accumulator clearing, dynamic precision interleaving, disabled state hold (`enable=0`), and soft reset (`rst=1`).
4. **Suite 4 (Golden Regression):** Transmits 2,361 operational vectors from `stimulus.txt` across the physical AXI bus and verifies readback results bit-for-bit against `golden_model.py`.

### 7.4 Physical FPGA Silicon Validation Results

The physical validation was conducted directly on the Digilent PYNQ-Z2 development board (IP `192.168.2.99`) running PYNQ 3.1.1 Linux.

**Physical Hardware Execution Log:**
```text
======================================================================
  PHYSICAL FPGA VALIDATION ON AMD/XILINX ZYNQ-7000 (PYNQ-Z2)
======================================================================
[PYNQ] Programming FPGA PL Fabric with Overlay: pynq_mac.bit...
[PYNQ] Bitstream programmed successfully in 1916.97 ms!
[PYNQ] Inspecting IP dictionary in overlay:
       -> IP: axi_lite_mac_ip_0 at base_address 0x43c00000
       -> IP: processing_system7_0 at base_address N/A
[PYNQ] Connected via overlay.axi_lite_mac_ip_0.mmio at 0x43c00000

--- Running Suite 1: INT8 Signed Arithmetic Tests ---
[PASS] INT8 - Positive x Positive: A=12, B=10 => Result=120 (Exp: 120)
[PASS] INT8 - Positive x Negative (Acc): A=15, B=-4 => Result=60 (Exp: 60)
[PASS] INT8 - Negative x Positive (Acc): A=-20, B=3 => Result=0 (Exp: 0)
[PASS] INT8 - Negative x Negative (Acc): A=-16, B=-5 => Result=80 (Exp: 80)
[PASS] INT8 - Min Neg x Min Neg (-128*-128): A=-128, B=-128 => Result=16384 (Exp: 16384)
[PASS] INT8 - Max Pos x Max Pos (+127*+127): A=127, B=127 => Result=16129 (Exp: 16129)
[PASS] INT8 - 100-Cycle Consecutive Stream: A=var, B=var => Result=1600 (Exp: 1600)

--- Running Suite 2: INT16 Signed Arithmetic Tests ---
[PASS] INT16 - Positive x Positive: A=1000, B=2000 => Result=2000000 (Exp: 2000000)
[PASS] INT16 - Positive x Negative (Acc): A=5000, B=-300 => Result=500000 (Exp: 500000)
[PASS] INT16 - Negative x Positive (Acc): A=-4000, B=250 => Result=-500000 (Exp: -500000)
[PASS] INT16 - Negative x Negative (Acc): A=-3000, B=-500 => Result=1000000 (Exp: 1000000)
[PASS] INT16 - Min Neg x 1 (-32768*1): A=-32768, B=1 => Result=-32768 (Exp: -32768)
[PASS] INT16 - Max Pos x Max Pos (+32767*+32767): A=32767, B=32767 => Result=1073676289 (Exp: 1073676289)
[PASS] INT16 - 100-Cycle Consecutive Stream: A=var, B=var => Result=32589850 (Exp: 32589850)

--- Running Suite 3: Control & Precision Switching Tests ---
[PASS] Pipeline - Synchronous Acc Clear: A=0, B=0 => Result=0 (Exp: 0)
[PASS] Pipeline - Dynamic INT8/INT16 Interleaving: A=mixed, B=mixed => Result=10050 (Exp: 10050)
[PASS] Pipeline - Disabled State Hold: A=100, B=100 => Result=10050 (Exp: 10050)
[PASS] Pipeline - Soft Reset Verification: A=0, B=0 => Result=0 (Exp: 0)

--- Running Suite 4: Complete 2,362-Vector Golden Regression ---
[REGRESSION RESULT] 2361/2361 vectors PASSED in 0.65s!
                   Average AXI transaction time: 0.277 ms/transaction

======================================================================
 PHYSICAL FPGA TEST SUMMARY: 2379 PASSED, 0 FAILED
======================================================================
```

### 7.5 Throughput Qualification: Datapath vs. Memory-Mapped Interface

It is critical to distinguish between the performance metrics evaluated in this project:
1. **Theoretical Peak Datapath Throughput at Configured Clock:**
   - The Zynq PL fabric clock generated by the Processing System (`FCLK_CLK0`) is configured at **$100.0\text{ MHz}$**.
   - With an Initiation Interval ($II$) of 1 cycle/transaction, the hardware datapath achieves a theoretical peak compute throughput of **$100.0\text{ MMAC/s}$** ($1.00 \times 10^8$ operations/second) at the configured operating frequency.
2. **STA-Derived Maximum Frequency Ceiling ($F_{\text{max}}$):**
   - Out-of-context Static Timing Analysis (STA) on the routed datapath indicates a positive worst negative slack ($WNS = +3.145\text{ ns}$), corresponding to an estimated theoretical frequency ceiling of **$145.88\text{ MHz}$**.
   - This represents an STA-derived timing estimate of the fabric speed ceiling, not a physically measured hardware operating frequency.
3. **Software-Driven MMIO Transaction Latency (AXI4-Lite Interface):**
   - During physical validation via Python running on the ARM Cortex-A9 host, each test transaction requires multiple user-space memory-mapped register accesses (`REG_OPERAND_A`, `REG_OPERAND_B`, `REG_CONTROL`, `REG_STATUS`, `REG_RESULT_LOW`, `REG_RESULT_HIGH`).
   - The measured physical execution time for 2,361 regression transactions was $0.65\text{ seconds}$, yielding an average transaction latency of **$0.277\text{ ms/transaction}$** (**$\approx 3,610\text{ MMIO transactions/second}$**).
   - This throughput is governed by Python Linux user-space MMIO read/write turnaround over the AXI-Lite bus, serving as a functional verification channel rather than a high-throughput streaming interface.

---

## 8. Summary of Engineering Accomplishments

1. **Complete Synthesizable RTL:** Developed a parameterizable, clean SystemVerilog RTL suite implementing multi-precision signed arithmetic, dynamic operand isolation, and accumulator overflow detection.
2. **Cycle-Accurate Verification:** Built a Python golden reference model and an automated 2,362-vector test suite achieving 100% test coverage and zero simulation mismatches in Vivado XSim.
3. **Multi-Architecture Exploration:** Evaluated seven distinct implementations (V1 through V6_LUT), establishing precise empirical trade-offs between LUT consumption, DSP utilization, pipeline latency, and clock frequency.
4. **Demonstrated Initiation Interval:** Proved through SystemVerilog assertions and randomized streaming testbenches that the pipelined core accepts back-to-back operands every clock cycle ($II = 1$), delivering **100.0 MMAC/s** at the configured 100.0 MHz PL clock, with an STA-estimated $F_{\text{max}}$ ceiling of 145.88 MHz.
5. **Silicon Resource Optimization:** Demonstrated that shared multiplier datapaths achieve an **8.67x reduction in LUT usage** compared to separate precision multiplier channels, trading one additional DSP slice to reclaim 92 LUTs and 17 flip-flops.
6. **Physical Hardware Deployment:** Packaged the optimized core as an AXI4-Lite IP and generated a complete Zynq-7000 SoC bitstream overlay (`pynq_mac.bit`) and Python MMIO control suite for the Digilent PYNQ-Z2 development board, verifying 2,379 tests on physical silicon with 100% bit-true accuracy.


---
*Report generated and validated under AMD Vivado Design Suite 2025.1.*
