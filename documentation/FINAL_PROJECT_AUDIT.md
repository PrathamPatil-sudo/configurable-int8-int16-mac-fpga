# Final Engineering Audit & Verification Report

**Project Title:** Design and FPGA Implementation of a High-Throughput Configurable INT8/INT16 Multiply-Accumulate Architecture  
**Target Hardware:** Digilent PYNQ-Z2 (AMD/Xilinx Zynq-7000 SoC `xc7z020clg400-1`)  
**EDA Tools:** AMD Vivado 2025.1, Vivado Simulator (XSim), Python 3.14 (Host), Python 3.10.4 & PYNQ 3.1.1 (Board)  
**Project Workspace:** `D:\iswdp_tcad\Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture`  
**Audit Date:** 2026-11-10  
**Audit Status:** **PASSED (ALL VERIFICATION & IMPLEMENTATION CRITERIA SATISFIED)**

---

## 1. Executive Summary & Verification Matrix

Every technical claim, architectural trade-off, simulation assertion, synthesis/implementation metric, and physical hardware result has been audited against genuine experimental evidence generated in AMD Vivado 2025.1 and verified on physical PYNQ-Z2 silicon.

| Audit Item | Scope | Status | Supporting Evidence / File Path | Key Findings / Metrics |
|:---|:---|:---:|:---|:---|
| **1. File & Revision Consistency** | RTL to Bitstream Pipeline | **PASSED** | `vivado/pynq_overlay/pynq_mac.bit`<br>`vivado/pynq_overlay/pynq_mac.hwh`<br>`rtl/mac_top.sv`<br>`rtl/axi_lite_mac_ip.sv` | Bitstream and `.hwh` generated from exact top-level revision (V6_DSP) integrated into Zynq PS7 block design. Identical MD5 hashes in `vivado/pynq_overlay` and board deployment directory. |
| **2. Signed INT8 Arithmetic** | Dynamic Range & Products | **PASSED** | `rtl/precision_controller.sv`<br>`python/golden_model.py`<br>`documentation/technical_report.md` | Range strictly verified: Min product $-128 \times +127 = -16,256$; Max product $-128 \times -128 = +16,384$. Corrected typographical $-16,129$ error in documentation. |
| **3. Signed INT16 Arithmetic** | Dynamic Range & Headroom | **PASSED** | `rtl/mac_multiplier.sv`<br>`python/golden_model.py` | Min product $-32,768 \times +32,767 = -1,073,709,056$; Max product $-32,768 \times -32,768 = +1,073,741,824$. 40-bit accumulator provides 8 guard bits (256 additions). |
| **4. Accumulator & Clear Control** | Modulo-$2^{40}$, Clear, Overflow | **PASSED** | `rtl/mac_accumulator.sv`<br>`rtl/overflow_detector.sv`<br>`reports/simulation/sim_V6_top.log` | Synchronous clear pulse (`acc_clear=1`) clears accumulator in 1 cycle. Invariant `acc_next = acc + prod` verified under full streaming. |
| **5. Pipeline Alignment & Throughput** | Latency & Initiation Interval | **PASSED** | `rtl/mac_pipelined_isolated.sv`<br>`reports/timing/V5_timing_route.rpt` | Latency = 2 cycles (`MREG` forward register). Initiation Interval ($II$) = 1 cycle/MAC. Peak datapath throughput = **100.0 MMAC/s** at configured 100.0 MHz PL clock ($F_{\text{max}} = 145.88\text{ MHz}$ is STA estimate). |
| **6. RTL Functional Simulation** | Multi-Phase Stimulus | **PASSED** | `reports/simulation/sim_V*.log`<br>`results/experimental_data/sim_results_summary.csv` | 100% pass across all testbenches: `tb_mac_basic` (20/20), `tb_mac_configurable` (40/40), `tb_mac_pipelined` (60/60), `tb_mac_top` (2,362/2,362). Zero mismatches. |
| **7. Simulation Assertions** | SVA Protocol Checking | **PASSED** | `tb/tb_mac_top.sv`<br>`tb/tb_mac_pipelined.sv` | Dynamic simulation assertions checked output latency, enable freeze, and clear behavior. Clarified in documentation as simulation assertions (not formal proof). |
| **8. Multi-Architecture Synthesis** | 7 Architectural Variants | **PASSED** | `reports/synthesis/*_route.rpt`<br>`results/comparison_tables/mac_architectures_comparison.csv` | All 7 variants (V1 through V6_LUT) synthesized and routed. Hardware sharing demonstrates **8.67x LUT reduction with 1 additional DSP** (V3 vs V4). Soft LUT mapping consumes **14.18x more LUTs** (V6_LUT vs V6_DSP). |
| **9. Post-Route Timing Closure** | Static Timing Analysis (STA) | **PASSED** | `reports/timing/*_route.rpt` | All architectures met 100.0 MHz constraint with 0 failing endpoints ($TNS = 0.000\text{ ns}$). V5/V6_DSP achieved $WNS = +3.145\text{ ns}$ ($F_{\text{max}} = 145.88\text{ MHz}$ STA estimate). |
| **10. Switching Power Experiment** | Dynamic Gating Evaluation | **PASSED** | `reports/power/V3_unisolated_switching_activity_power.rpt`<br>`reports/power/V5_isolated_switching_activity_power.rpt` | Actual activity-based power reports confirm 0.003 W dynamic / 0.103 W static for both V3 and V5. At 1 mW report precision, data does not establish numerical power reduction; isolation suppresses internal switching activity. |
| **11. AXI4-Lite SoC Integration** | Memory Map & Interconnect | **PASSED** | `rtl/axi_lite_mac_ip.sv`<br>`reports/hardware/pynq_soc_timing.rpt`<br>`reports/hardware/pynq_soc_utilization.rpt` | IP mapped at `0x43C00000`. SoC fabric timing: $WNS = +3.181\text{ ns}$ (100.0 MHz clock). SoC uses 495 LUTs, 677 FFs, 2 DSPs. |
| **12. Physical FPGA Validation** | Real Hardware Execution | **PASSED** | `reports/hardware/physical_fpga_validation.md`<br>`python/pynq_mac_test.py` | Executed directly on PYNQ-Z2 (`192.168.2.99`). 2,379 tests passed, 0 failed. Operational regression: 2,361/2,361 passed (1 reset cycle + 2,361 operational vectors = 2,362 total vectors). |
| **13. Throughput Qualification** | Datapath vs MMIO | **PASSED** | `documentation/technical_report.md`<br>`reports/hardware/physical_fpga_validation.md` | Theoretical peak throughput at configured 100 MHz clock: **100.0 MMAC/s**. STA-derived $F_{\text{max}}$ estimate: 145.88 MHz. Software MMIO throughput: **~3,610 transactions/s** ($0.277\text{ ms/tx}$). |
| **14. Board Security & sudoers** | Privileged Access Audit | **PASSED** | Live SSH audit on PYNQ board | Exact outputs verified: `/etc/sudoers.d/` contains only `README`, zero NOPASSWD rules found, `sudo visudo -c` parsed OK. Stock configuration intact. |

---

## 2. Detailed Technical Audit Findings

### 2.1 File & Hardware Revision Correspondence
- **RTL Source Files:** Located in `rtl/`. All 12 synthesizable SystemVerilog modules have clean syntax, explicit sensitivity lists, and synchronous resets.
- **Top-Level IP (`mac_top.sv`):** Combines operand isolation (`operand_isolation.sv`), precision steering (`precision_controller.sv`), pipelined multiplication (`mac_multiplier.sv`), 40-bit accumulation (`mac_accumulator.sv`), and overflow detection (`overflow_detector.sv`).
- **AXI4-Lite Wrapper (`axi_lite_mac_ip.sv`):** Implements standard AXI4-Lite register bank with byte-enable handling, address decoding for 7 memory-mapped registers, and synchronous valid generation.
- **Bitstream and Metadata:** `vivado/pynq_overlay/pynq_mac.bit` (4,045,695 bytes) and `vivado/pynq_overlay/pynq_mac.hwh` (132,795 bytes) correspond directly to the Vivado block design implementing `axi_lite_mac_ip_0` connected to `processing_system7_0`. Both files were transferred to `/home/xilinx/Design_and_FPGA_Implementation_of_a_High_Throughput_Configurable_INT8_INT16_MAC_Architecture` on the PYNQ-Z2 board and loaded into PL silicon.

### 2.2 Mathematical & Functional Correctness
1. **INT8 Multiplication Bounds:**
   - Evaluated range: $[-128, +127]$.
   - Negative extreme product: $-128 \times +127 = -16,256$ (`16'hC080`).
   - Positive extreme product: $-128 \times -128 = +16,384$ (`16'h4000`).
   - The typographical error in Section 2.2 of the technical report (reporting $-16,129$) has been corrected to $-16,256$.
2. **INT16 Multiplication Bounds:**
   - Evaluated range: $[-32,768, +32,767]$.
   - Extreme product: $-32,768 \times -32,768 = +1,073,741,824$ (`32'h40000000`).
   - Extended to 40 bits: `40'sh00_4000_0000`.
3. **Accumulator Headroom & Overflow Detection:**
   - Accumulator bit width: 40 bits signed (`signed [39:0]`).
   - Minimum value: $-2^{39} = -549,755,813,888$ (`40'h80_0000_0000`).
   - Maximum value: $+2^{39} - 1 = +549,755,813,887$ (`40'h7F_FFFF_FFFF`).
   - Overflow detection logic in `overflow_detector.sv`:
     `overflow_status = (~acc_current[39] & ~product[39] & sum[39]) | (acc_current[39] & product[39] & ~sum[39]);`
     Accurately identifies two's-complement overflow when two positive numbers sum to negative, or two negative numbers sum to positive.

### 2.3 Verification & Assertions Audit
- **Simulation Regression:** All testbenches in `tb/` were compiled and simulated in AMD Vivado XSim 2025.1.
- **Test Vectors:** `stimulus.txt` contains 2,362 vectors spanning elementary operations, dynamic INT8/INT16 switching, extreme corner cases, pipeline bubble injections, and accumulator overflow sequences.
- **Scorecard:** 2,362 / 2,362 vectors passed in `tb_mac_top.sv` with zero errors.
- **Assertion Engine Clarification:** The SystemVerilog Assertions (`assert property`) in `tb_mac_pipelined.sv` and `tb_mac_top.sv` check protocol invariants (2-cycle output validity, clear latency, freeze hold). These were evaluated dynamically during XSim simulation runs. No formal model checking tools (e.g. SymbiYosys, JasperGold) were utilized, and the documentation explicitly states simulation assertions.

### 2.4 Multi-Architecture Synthesis & Implementation Comparison
Data audited against raw Vivado 2025.1 post-route reports in `reports/synthesis/`, `reports/timing/`, and `reports/power/`:

| Arch ID | Architecture Description | LUTs | FFs | DSPs | Target Clock | WNS (ns) | TNS (ns) | STA Est. Fmax (MHz) | Latency | II | Configured Throughput | Dynamic Power | Static Power | Total Power |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **V1** | Basic Non-Pipelined INT16 | 3 | 42 | 2 | 100.0 MHz | +2.831 | 0.000 | 139.49 | 1 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V2** | Shared Single-Cycle INT8/INT16 | 11 | 42 | 2 | 100.0 MHz | +1.575 | 0.000 | 118.69 | 1 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V3** | Pipelined Configurable (Unisolated) | 12 | 44 | 2 | 100.0 MHz | +2.666 | 0.000 | 136.35 | 2 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V4** | Separate INT8/INT16 Multipliers | 104 | 61 | 1 | 100.0 MHz | +2.913 | 0.000 | 141.10 | 2 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V5** | Pipelined MAC with Operand Isolation | 28 | 44 | 2 | 100.0 MHz | +3.145 | 0.000 | 145.88 | 2 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V6_DSP**| Final Optimized Core (DSP Inferred) | 28 | 44 | 2 | 100.0 MHz | +3.145 | 0.000 | 145.88 | 2 | 1 | 100.0 MMAC/s | 0.003 W | 0.103 W | 0.106 W |
| **V6_LUT**| Optimized Core (Forced Soft LUTs) | 397 | 76 | 0 | 100.0 MHz | +0.116 | 0.000 | 101.17 | 2 | 1 | 100.0 MMAC/s | 0.004 W | 0.103 W | 0.107 W |

**Audited Findings:**
1. **Resource Sharing (V3 vs. V4 Trade-Off):**
   - V3 uses **12 LUTs, 44 FFs, and 2 DSPs**.
   - V4 uses **104 LUTs, 61 FFs, and 1 DSP**.
   - Rather than an improvement in every category, V3 represents an **LUT and FF reduction with an additional DSP cost**: Look-Up Table usage decreases by **8.67x** (from 104 to 12 LUTs) and register count decreases by **27.9%** (from 61 to 44 FFs), in exchange for consuming **1 additional DSP slice** (2 DSPs vs. 1 DSP).
2. **DSP vs Soft LUT Mapping:** Forcing multiplier logic into soft LUTs (V6_LUT: 397 LUTs) consumes **14.18x more LUTs** than dedicated DSP mapping (V6_DSP: 28 LUTs) and reduces maximum operating frequency from $145.88\text{ MHz}$ to $101.17\text{ MHz}$ (-30.6% timing penalty).
3. **Pipelining Benefit:** Adding intermediate pipeline registers ($MREG$) between multiplier and accumulator improves timing margin ($WNS$ from $+1.575$ ns in V2 to $+3.145$ ns in V5/V6_DSP), boosting STA-estimated $F_{\text{max}}$ from $118.69\text{ MHz}$ to $145.88\text{ MHz}$.

### 2.5 Dynamic Power & Switching Activity Experiment
- Executed `vivado/eval_switching_power.tcl` on the routed design checkpoints (`vivado/V3_routed.dcp` and `vivado/V5_routed.dcp`).
- Generated detailed post-route power reports:
  - `reports/power/V3_unisolated_switching_activity_power.rpt`
  - `reports/power/V5_isolated_switching_activity_power.rpt`
- **Measurement Assumptions & Activity Annotation Coverage:**
  - Clock nodes activity: High (>95% user specified).
  - I/O port activity: High (>95% user specified with toggle rate and static probability).
  - Internal nodes activity: Medium (<25% internal nodes directly annotated; internal node activity derived via vectorless propagation).
  - Overall Power Confidence Level: **Medium** (Production device models, typical process).
- **Actual Measured Post-Route Power Values:**
  - **Active Workload (`in_valid=1`, 50% toggle rate):**
    - V3: Dynamic = $0.001\text{ W}$ (no propagation) / $0.003\text{ W}$ (full propagation) | Static = $0.103\text{ W}$
    - V5: Dynamic = $0.001\text{ W}$ (no propagation) / $0.003\text{ W}$ (full propagation) | Static = $0.103\text{ W}$
  - **Idle Workload with Input Switching (`in_valid=0`, 100% toggle rate):**
    - V3 (Unisolated): Dynamic = **$0.003\text{ W}$** | Static = **$0.103\text{ W}$** | Total = **$0.106\text{ W}$**
    - V5 (Isolated): Dynamic = **$0.003\text{ W}$** | Static = **$0.103\text{ W}$** | Total = **$0.106\text{ W}$**
- **Power Findings:**
  - At Vivado's standard 1 mW (0.001 W) reporting precision, both architectures report identical dynamic power ($0.003\text{ W}$) for a single out-of-context MAC core on the XC7Z020 FPGA.
  - Because the numerical report values round to the nearest milliwatt and device static leakage ($0.103\text{ W}$) dominates, the available post-route data does not establish a measurable numerical power reduction for a single MAC instance.
  - Consequently, we state strictly from architectural design and RTL structure that operand isolation suppresses internal switching transitions inside the multiplier datapath during idle input conditions (`in_valid = 0` or `enable = 0`), preventing input bus activity from toggling internal multiplier nodes.

### 2.6 Physical FPGA Validation on PYNQ-Z2
- **Board Environment:** Digilent PYNQ-Z2, IP `192.168.2.99`, running PYNQ 3.1.1 Linux.
- **Configured PL Clock:** 100.0 MHz.
- **Bitstream Loading:** `pynq_mac.bit` programmed into FPGA PL fabric via `pynq.Overlay` in 1,916.97 ms.
- **Physical Memory Map:** Custom IP detected at `0x43C00000`, matching Vivado address assignment.
- **Test Execution:**
  - Suite 1 (INT8): 7/7 passed
  - Suite 2 (INT16): 7/7 passed
  - Suite 3 (Control/Pipeline): 4/4 passed
  - Suite 4 (Golden Regression): 2,361/2,361 passed
  - **Total Tests Passed on Silicon: 2,379 / 2,379 (100.00% bit-true match, 0 errors).**
- **Discrepancy Resolution (2,361 vs 2,362):**
  - Total stimulus file lines: 2,362 (`stimulus.txt`).
  - Vector index 0 is the initial synchronous reset vector (`rst=1`). The test driver safely executes `driver.reset()` to initialize hardware state without an output comparison.
  - Exactly 2,361 operational vectors were transmitted over physical AXI memory-mapped IO and verified against the golden model.
- **Throughput Qualification:**
  - Theoretical Peak Datapath Throughput at Configured Clock: **100.0 MMAC/s** ($1.00 \times 10^8$ operations/s at configured 100.0 MHz clock with $II=1$).
  - STA-Derived $F_{\text{max}}$ Timing Estimate: **145.88 MHz** ($WNS = +3.145\text{ ns}$), representing an out-of-context static timing analysis estimate, not a physically measured operating frequency.
  - Software MMIO Transaction Rate: **0.277 ms/transaction** (**~3,610 MMIO transactions/second**), a distinct software-interface measurement governed by Python user-space AXI read/write turnaround.

### 2.7 Security & Operating System State
A live security audit was performed on the physical PYNQ-Z2 board:

1. **Listing `/etc/sudoers.d/`:**
   ```text
   $ ls -la /etc/sudoers.d/
   total 12
   drwxr-xr-x   2 root root 4096 Feb  8  2022 .
   drwxr-xr-x 107 root root 4096 Oct  3 09:19 ..
   -r--r-----   1 root root 1096 Feb  8  2022 README
   ```
2. **Searching sudoers configuration for NOPASSWD rules:**
   ```text
   $ grep -rn 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || echo '[NO NOPASSWD RULES FOUND]'
   [NO NOPASSWD RULES FOUND]
   ```
3. **User Privileges (`sudo -l -U xilinx`):**
   ```text
   $ sudo -l -U xilinx
   Matching Defaults entries for xilinx on pynq:
       mail_badpass, use_pty, env_keep=BOARD

   User xilinx may run the following commands on pynq:
       (ALL : ALL) ALL
   ```
4. **Sudoers Syntax & Integrity Check (`sudo visudo -c`):**
   ```text
   $ sudo visudo -c
   /etc/sudoers: parsed OK
   /etc/sudoers.d/README: parsed OK
   ```

**Security Confirmation:** All temporary permissions or commands evaluated during testing left no persistent artifacts. The stock PYNQ Linux security configuration remains completely unmodified and intact with standard password authentication required for all sudo operations.

---

## 3. Audit Verdict & Project Sign-Off

**Final Engineering Assessment:**
The Configurable INT8/INT16 Multiply-Accumulate Architecture project has completed all engineering phases from architectural specification, RTL authoring, simulation verification, Vivado synthesis, place-and-route implementation, timing closure, power analysis, Zynq SoC overlay assembly, to physical on-chip hardware validation on the Digilent PYNQ-Z2 board.

All deliverables, raw reports, scripts, and logs are preserved locally in the project repository with complete integrity.

**Project Status: APPROVED AND OFFICIALLY CLOSED.**
