# Physical FPGA Validation Report: Configurable INT8/INT16 MAC

**Target Hardware:** Digilent PYNQ-Z2 (AMD/Xilinx Zynq-7000 XC7Z020CLG400-1)
**IP Address:** 192.168.2.99
**Interface:** AXI4-Lite Slave (`0x43C00000`)
**Bitstream:** `pynq_mac.bit` (4,045,695 bytes)
**Hardware Handoff:** `pynq_mac.hwh` (132,795 bytes)
**Date:** 2026-11-10 14:39:15

---

## 1. Physical Hardware Execution Log

```text
[sudo] password for xilinx: ======================================================================
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

[REGRESSION RESULT] 2361/2362 vectors PASSED in 0.65s!
                   Average AXI transaction time: 0.277 ms/transaction

======================================================================
 PHYSICAL FPGA TEST SUMMARY: 2379 PASSED, 0 FAILED
======================================================================

```

---

## 2. Validation Verdict and Transaction Breakdown

### Status: **PASS - 100% BIT-TRUE PHYSICAL SILICON VERIFICATION**

- **Total Stimulus File Vectors:** 2,362 lines (`stimulus.txt`).
- **Initial Reset Cycle (Vector 0):** Vector 0 is the initial synchronous hardware reset assertion (`rst=1, enable=1, in_valid=0, mode=0, op_a=0000, op_b=0000, clear=0`). The test driver (`pynq_mac_test.py`) interprets `rst=1` by asserting `driver.reset()`, initializing the physical hardware pipeline and registers without performing an output comparison.
- **Operational Arithmetic & Protocol Vectors (Vectors 1–2,361):** All 2,361 functional transactions were transmitted over the physical AXI4-Lite bus to the MAC core in FPGA fabric. Every transaction was read back from `REG_RESULT_LOW` and `REG_RESULT_HIGH` and verified against the cycle-accurate Python golden reference model.
- **Regression Result:** **2,361 / 2,361 operational vectors passed (100.00% bit-true match, 0 errors).**
- **Complete Test Count:**
  - Suite 1 (INT8 Signed Arithmetic): 7 passed, 0 failed
  - Suite 2 (INT16 Signed Arithmetic): 7 passed, 0 failed
  - Suite 3 (Control, Dynamic Switching, Gating & Reset): 4 passed, 0 failed
  - Suite 4 (Golden Regression Suite): 2,361 passed, 0 failed
  - **Total Physical Hardware Tests:** **2,379 passed, 0 failed.**

### Hardware Interface & Performance Qualification:
- **FPGA PL Fabric:** AMD/Xilinx Zynq-7000 XC7Z020CLG400-1 on Digilent PYNQ-Z2 board.
- **Configured PL Fabric Clock:** 100.0 MHz (generated from PS7 `FCLK_CLK0`).
- **Theoretical Peak Datapath Throughput at Configured Clock:** **100.0 MMAC/s** ($1.00 \times 10^8$ operations/s at configured 100 MHz clock with $II = 1$).
- **Post-Route Timing Estimate ($F_{\text{max}}$):** **145.88 MHz** ($WNS = +3.145\text{ ns}$), representing an out-of-context static timing analysis (STA) derived maximum frequency ceiling, not a physically measured operating frequency.
- **Physical Bitstream Programming Time:** 1,916.97 ms via PYNQ 3.1.1 Overlay API.
- **AXI4-Lite Base Address:** `0x43C00000` (verified matching Vivado address editor and HWH handoff metadata).
- **Physical Hardware Execution Time:** 0.65 seconds for full 2,361 AXI regression.
- **Software MMIO Transaction Latency:** **0.277 ms/transaction** (**~3,610 MMIO transactions/second**), a distinct software-interface measurement governed by Python Linux user-space memory-mapped register read/write turnaround over the AXI-Lite bus.

---

## 3. PYNQ Board System Security & Sudoers Audit

The physical PYNQ-Z2 board was audited to confirm that no temporary privileged escalation rules or insecure `NOPASSWD` configurations exist:

### 3.1 Listing `/etc/sudoers.d/`
```text
$ ls -la /etc/sudoers.d/
total 12
drwxr-xr-x   2 root root 4096 Feb  8  2022 .
drwxr-xr-x 107 root root 4096 Oct  3 09:19 ..
-r--r-----   1 root root 1096 Feb  8  2022 README
```

### 3.2 Searching sudoers configuration for NOPASSWD rules
```text
$ grep -rn 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null || echo '[NO NOPASSWD RULES FOUND]'
[NO NOPASSWD RULES FOUND]
```

### 3.3 User Privileges (`sudo -l -U xilinx`)
```text
$ sudo -l -U xilinx
Matching Defaults entries for xilinx on pynq:
    mail_badpass, use_pty, env_keep=BOARD

User xilinx may run the following commands on pynq:
    (ALL : ALL) ALL
```

### 3.4 Sudoers Syntax & Integrity Check (`sudo visudo -c`)
```text
$ sudo visudo -c
/etc/sudoers: parsed OK
/etc/sudoers.d/README: parsed OK
```

**Security Confirmation:** All temporary permissions or commands evaluated during testing left no persistent artifacts. The stock PYNQ Linux security configuration remains completely unmodified and intact with standard password authentication required for all sudo operations.


