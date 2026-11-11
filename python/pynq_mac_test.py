"""
PYNQ-Z2 Physical FPGA Validation Suite for High-Throughput Configurable INT8/INT16 MAC.
Controls the Custom AXI4-Lite MAC IP on the Xilinx Zynq-7000 XC7Z020 FPGA from the ARM Processing System.
Executes actual hardware transactions, measures timing, and validates functional correctness.
"""

import sys
import os
import time

# AXI4-Lite Register Map Offsets
REG_CONTROL     = 0x00  # bit 0: enable, bit 1: acc_clear, bit 2: rst_soft, bit 3: in_valid
REG_MODE        = 0x04  # bit 0: precision_mode (0: INT8, 1: INT16)
REG_OPERAND_A   = 0x08  # [15:0]: Operand A
REG_OPERAND_B   = 0x0C  # [15:0]: Operand B (triggers compute upon write)
REG_STATUS      = 0x10  # bit 0: busy, bit 1: out_valid, bit 2: overflow
REG_RESULT_LOW  = 0x14  # [31:0]: Lower 32 bits of accumulator
REG_RESULT_HIGH = 0x18  # [39:32]: Upper 8 bits of accumulator (sign-extended to 32 bits)

class PynqMACDriver:
    def __init__(self, overlay_path=None, base_addr=0x43C00000):
        self.base_addr = base_addr
        self.overlay = None
        self.mmio = None
        self.is_hardware = False

        try:
            from pynq import Overlay, MMIO
            if overlay_path and os.path.exists(overlay_path):
                print(f"[PYNQ] Programming FPGA PL Fabric with Overlay: {overlay_path}...")
                t0 = time.time()
                self.overlay = Overlay(overlay_path)
                t_load = time.time() - t0
                print(f"[PYNQ] Bitstream programmed successfully in {t_load*1000:.2f} ms!")
                
                # Check IP dictionary
                print(f"[PYNQ] Inspecting IP dictionary in overlay:")
                for ip_name, ip_info in self.overlay.ip_dict.items():
                    addr = ip_info.get('phys_addr') if isinstance(ip_info, dict) else getattr(ip_info, 'phys_addr', None)
                    print(f"       -> IP: {ip_name} at base_address {hex(addr) if addr else 'N/A'}")
                
                if hasattr(self.overlay, 'axi_lite_mac_ip_0'):
                    self.mmio = self.overlay.axi_lite_mac_ip_0.mmio
                    print(f"[PYNQ] Connected via overlay.axi_lite_mac_ip_0.mmio at 0x43c00000")
                else:
                    self.mmio = MMIO(base_addr, 0x10000)
                    print(f"[PYNQ] Connected via direct MMIO at {hex(base_addr)}")
            else:
                self.mmio = MMIO(base_addr, 0x10000)
                print(f"[PYNQ] Connected via direct MMIO at {hex(base_addr)}")
            self.is_hardware = True
        except Exception as e:
            print(f"[WARNING] Native PYNQ hardware access failed: {e}")
            raise RuntimeError(f"Physical FPGA hardware initialization failed: {e}")

    def write_reg(self, offset, value):
        self.mmio.write(offset, int(value) & 0xFFFFFFFF)

    def read_reg(self, offset):
        return self.mmio.read(offset)

    def reset(self):
        # Assert soft reset bit (bit 2)
        self.write_reg(REG_CONTROL, 0x04)
        time.sleep(0.0001)
        # Enable core (bit 0)
        self.write_reg(REG_CONTROL, 0x01)
        time.sleep(0.0001)

    def clear_accumulator(self):
        # Assert enable (bit 0) and acc_clear (bit 1)
        self.write_reg(REG_CONTROL, 0x03)
        time.sleep(0.00005)
        # De-assert acc_clear
        self.write_reg(REG_CONTROL, 0x01)

    def set_precision(self, mode):
        # 0: INT8, 1: INT16
        self.write_reg(REG_MODE, 0x01 if mode == 1 else 0x00)

    def set_enable(self, en):
        curr = self.read_reg(REG_CONTROL)
        if en:
            self.write_reg(REG_CONTROL, curr | 0x01)
        else:
            self.write_reg(REG_CONTROL, curr & ~0x01)

    def mac_operation(self, op_a, op_b):
        self.write_reg(REG_OPERAND_A, int(op_a) & 0xFFFF)
        self.write_reg(REG_OPERAND_B, int(op_b) & 0xFFFF)  # Triggers compute

    def read_result(self):
        low = self.read_reg(REG_RESULT_LOW)
        high = self.read_reg(REG_RESULT_HIGH)
        raw_40 = ((high & 0xFF) << 32) | (low & 0xFFFFFFFF)
        if raw_40 & (1 << 39):
            signed_40 = raw_40 - (1 << 40)
        else:
            signed_40 = raw_40

        status = self.read_reg(REG_STATUS)
        out_valid = bool(status & 0x02)
        overflow = bool(status & 0x04)
        return signed_40, out_valid, overflow


def run_physical_fpga_validation():
    print("=" * 70)
    print("  PHYSICAL FPGA VALIDATION ON AMD/XILINX ZYNQ-7000 (PYNQ-Z2)")
    print("=" * 70)

    bit_path = "pynq_mac.bit"
    if not os.path.exists(bit_path):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        bit_path = os.path.join(script_dir, "pynq_mac.bit")

    driver = PynqMACDriver(overlay_path=bit_path)
    driver.reset()

    results_log = []
    total_passed = 0
    total_failed = 0

    def record_test(suite_name, test_name, a, b, exp_res, act_res, vld, ovf):
        nonlocal total_passed, total_failed
        passed = (exp_res == act_res)
        status_str = "PASS" if passed else "FAIL"
        if passed:
            total_passed += 1
        else:
            total_failed += 1
        entry = {
            "suite": suite_name,
            "test": test_name,
            "op_a": a,
            "op_b": b,
            "expected": exp_res,
            "actual": act_res,
            "valid": vld,
            "overflow": ovf,
            "status": status_str
        }
        results_log.append(entry)
        print(f"[{status_str}] {suite_name} - {test_name}: A={a}, B={b} => Result={act_res} (Exp: {exp_res})")
        return passed

    # =========================================================================
    # SUITE 1: INT8 ARITHMETIC CORNER CASES & ACCUMULATION
    # =========================================================================
    print("\n--- Running Suite 1: INT8 Signed Arithmetic Tests ---")
    driver.set_precision(0)
    driver.clear_accumulator()

    # 1. Pos x Pos
    driver.mac_operation(12, 10)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Positive x Positive", 12, 10, 120, res, vld, ovf)

    # 2. Pos x Neg (Accumulating)
    driver.mac_operation(15, -4)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Positive x Negative (Acc)", 15, -4, 60, res, vld, ovf)

    # 3. Neg x Pos (Accumulating)
    driver.mac_operation(-20, 3)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Negative x Positive (Acc)", -20, 3, 0, res, vld, ovf)

    # 4. Neg x Neg (Accumulating)
    driver.mac_operation(-16, -5)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Negative x Negative (Acc)", -16, -5, 80, res, vld, ovf)

    # 5. INT8 Minimum Boundary: -128 x -128
    driver.clear_accumulator()
    driver.mac_operation(-128, -128)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Min Neg x Min Neg (-128*-128)", -128, -128, 16384, res, vld, ovf)

    # 6. INT8 Maximum Boundary: +127 x +127
    driver.clear_accumulator()
    driver.mac_operation(127, 127)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "Max Pos x Max Pos (+127*+127)", 127, 127, 16129, res, vld, ovf)

    # 7. Consecutive 100 INT8 Operations
    driver.clear_accumulator()
    acc_sw = 0
    for i in range(1, 101):
        a = (i % 25) - 12
        b = ((i * 3) % 25) - 12
        acc_sw += (a * b)
        driver.mac_operation(a, b)
    res, vld, ovf = driver.read_result()
    record_test("INT8", "100-Cycle Consecutive Stream", "var", "var", acc_sw, res, vld, ovf)

    # =========================================================================
    # SUITE 2: INT16 ARITHMETIC CORNER CASES & ACCUMULATION
    # =========================================================================
    print("\n--- Running Suite 2: INT16 Signed Arithmetic Tests ---")
    driver.set_precision(1)
    driver.clear_accumulator()

    # 1. Pos x Pos
    driver.mac_operation(1000, 2000)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Positive x Positive", 1000, 2000, 2000000, res, vld, ovf)

    # 2. Pos x Neg
    driver.mac_operation(5000, -300)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Positive x Negative (Acc)", 5000, -300, 500000, res, vld, ovf)

    # 3. Neg x Pos
    driver.mac_operation(-4000, 250)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Negative x Positive (Acc)", -4000, 250, -500000, res, vld, ovf)

    # 4. Neg x Neg
    driver.mac_operation(-3000, -500)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Negative x Negative (Acc)", -3000, -500, 1000000, res, vld, ovf)

    # 5. INT16 Minimum Boundary: -32768 x 1
    driver.clear_accumulator()
    driver.mac_operation(-32768, 1)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Min Neg x 1 (-32768*1)", -32768, 1, -32768, res, vld, ovf)

    # 6. INT16 Maximum Boundary: +32767 x +32767
    driver.clear_accumulator()
    driver.mac_operation(32767, 32767)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "Max Pos x Max Pos (+32767*+32767)", 32767, 32767, 1073676289, res, vld, ovf)

    # 7. Consecutive 100 INT16 Operations
    driver.clear_accumulator()
    acc_sw16 = 0
    for i in range(1, 101):
        a16 = (i * 17) - 850
        b16 = (i * 23) - 1150
        acc_sw16 += (a16 * b16)
        driver.mac_operation(a16, b16)
    res, vld, ovf = driver.read_result()
    record_test("INT16", "100-Cycle Consecutive Stream", "var", "var", acc_sw16, res, vld, ovf)

    # =========================================================================
    # SUITE 3: CONTROL, PIPELINE, & PRECISION SWITCHING TESTS
    # =========================================================================
    print("\n--- Running Suite 3: Control & Precision Switching Tests ---")

    # 1. Accumulator Clear Test
    driver.clear_accumulator()
    res, vld, ovf = driver.read_result()
    record_test("Pipeline", "Synchronous Acc Clear", 0, 0, 0, res, vld, ovf)

    # 2. Precision Switching Interleaving (INT8 -> INT16 -> INT8)
    driver.clear_accumulator()
    driver.set_precision(0)  # INT8
    driver.mac_operation(10, 10)  # +100
    driver.set_precision(1)  # INT16
    driver.mac_operation(500, 20)  # +10000 => 10100
    driver.set_precision(0)  # INT8
    driver.mac_operation(-10, 5)   # -50 => 10050
    res, vld, ovf = driver.read_result()
    record_test("Pipeline", "Dynamic INT8/INT16 Interleaving", "mixed", "mixed", 10050, res, vld, ovf)

    # 3. Core Enable / Disable State Preservation
    driver.set_enable(False)
    # Write operands while disabled (should NOT accumulate)
    driver.mac_operation(100, 100)
    res, vld, ovf = driver.read_result()
    record_test("Pipeline", "Disabled State Hold", 100, 100, 10050, res, vld, ovf)
    driver.set_enable(True)

    # 4. Soft Reset Test
    driver.reset()
    res, vld, ovf = driver.read_result()
    record_test("Pipeline", "Soft Reset Verification", 0, 0, 0, res, vld, ovf)

    # =========================================================================
    # SUITE 4: FULL 2,362-VECTOR BIT-TRUE REGRESSION TEST
    # =========================================================================
    print("\n--- Running Suite 4: Complete 2,362-Vector Golden Regression ---")
    vec_path = "stimulus.txt"
    exp_path = "expected_l2.txt"
    if not os.path.exists(vec_path):
        vec_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stimulus.txt")
        exp_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "expected_l2.txt")

    if os.path.exists(vec_path):
        from golden_model import GoldenMAC
        golden = GoldenMAC(latency=1)
        driver.reset()
        golden.reset()
        driver.clear_accumulator()
        golden.clear()
        
        with open(vec_path, "r") as f:
            stim_lines = [l.strip().split() for l in f if l.strip()]

        reg_passed = 0
        reg_failed = 0
        t_start = time.time()

        for idx, stim in enumerate(stim_lines):
            # stim: [rst, enable, in_valid, mode, op_a, op_b, clear]
            rst_in = int(stim[0])
            en_in = int(stim[1])
            vld_in = int(stim[2])
            mode_in = int(stim[3])
            op_a = int(stim[4], 16)
            op_b = int(stim[5], 16)
            clr_in = int(stim[6])

            if rst_in:
                driver.reset()
                golden.reset()
                continue

            if clr_in:
                driver.clear_accumulator()

            driver.set_precision(mode_in)
            driver.set_enable(bool(en_in))

            # Golden reference calculation
            expected = golden.step(
                enable=bool(en_in),
                in_valid=bool(vld_in),
                precision_mode=mode_in,
                op_a=op_a,
                op_b=op_b,
                acc_clear=bool(clr_in)
            )

            # Physical FPGA operation
            if vld_in and en_in:
                driver.mac_operation(op_a, op_b)
            
            act_acc, act_vld, act_ovf = driver.read_result()
            exp_acc = expected["result"]

            if act_acc == exp_acc:
                reg_passed += 1
            else:
                reg_failed += 1
                if reg_failed <= 5:
                    print(f"[REG_FAIL @ Vec {idx}] A={hex(op_a)}, B={hex(op_b)}, Mode={mode_in} | Expected={exp_acc}, Got={act_acc}")

        t_total = time.time() - t_start
        print(f"\n[REGRESSION RESULT] {reg_passed}/{len(stim_lines)} vectors PASSED in {t_total:.2f}s!")
        print(f"                   Average AXI transaction time: {(t_total / len(stim_lines))*1000:.3f} ms/transaction")
        total_passed += reg_passed
        total_failed += reg_failed
    else:
        print("[NOTE] stimulus.txt not found. Skipping file-based regression.")

    # =========================================================================
    # SUMMARY & FINAL VERDICT
    # =========================================================================
    print("\n" + "=" * 70)
    print(f" PHYSICAL FPGA TEST SUMMARY: {total_passed} PASSED, {total_failed} FAILED")
    print("=" * 70)
    
    return total_failed == 0, results_log


if __name__ == "__main__":
    success, log = run_physical_fpga_validation()
    sys.exit(0 if success else 1)
