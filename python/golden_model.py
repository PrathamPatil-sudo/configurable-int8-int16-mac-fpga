"""
Python Golden Reference Model for Configurable INT8/INT16 MAC Architecture.
Models exact signed two's-complement arithmetic, 40-bit accumulation semantics,
overflow detection, saturation clamping, and pipeline timing.
"""

import sys

MASK_40 = (1 << 40) - 1
SIGN_BIT_40 = 1 << 39
MAX_INT40 = (1 << 39) - 1
MIN_INT40 = -(1 << 39)


def to_signed(val: int, bits: int) -> int:
    val = val & ((1 << bits) - 1)
    if val & (1 << (bits - 1)):
        return val - (1 << bits)
    return val


def to_unsigned(val: int, bits: int) -> int:
    return val & ((1 << bits) - 1)


class GoldenMAC:
    def __init__(self, latency: int = 2, saturation: bool = False):
        self.latency = latency
        self.saturation = saturation
        self.accumulator = 0  # 40-bit signed value
        self.overflow = False
        self.pipeline = []  # List of pending products

    def reset(self):
        self.accumulator = 0
        self.overflow = False
        self.pipeline = []

    def clear(self):
        self.accumulator = 0
        self.overflow = False

    def step(self, enable: bool, in_valid: bool, precision_mode: int,
             op_a: int, op_b: int, acc_clear: bool):
        """
        Executes one clock cycle step.
        precision_mode: 0 for INT8, 1 for INT16
        op_a, op_b: raw 16-bit integer values
        """
        if not enable:
            return {
                "result": self.accumulator,
                "out_valid": False,
                "overflow": self.overflow
            }

        # Handle input transaction
        if in_valid:
            if precision_mode == 0:
                # INT8: lower 8 bits signed
                s_a = to_signed(op_a & 0xFF, 8)
                s_b = to_signed(op_b & 0xFF, 8)
            else:
                # INT16: full 16 bits signed
                s_a = to_signed(op_a, 16)
                s_b = to_signed(op_b, 16)

            prod = s_a * s_b  # Mathematically exact signed product
            item = {"valid": True, "prod": prod, "acc_clear": acc_clear}
        else:
            item = {"valid": False, "prod": 0, "acc_clear": acc_clear}

        if self.latency == 1:
            # Single-cycle MAC (V1, V2)
            retired = item
        else:
            # Pipelined MAC (latency >= 2)
            self.pipeline.append(item)
            if len(self.pipeline) >= self.latency:
                retired = self.pipeline.pop(0)
            else:
                retired = {"valid": False, "prod": 0, "acc_clear": False}

        out_valid = False
        if retired["valid"] or retired["acc_clear"]:
            base = 0 if retired["acc_clear"] else self.accumulator
            if retired["valid"]:
                prod = retired["prod"]
                raw_sum = base + prod

                # Overflow detection in signed 40-bit arithmetic:
                # If base and prod have same sign, but raw_sum has opposite sign
                sign_base = (base < 0)
                sign_prod = (prod < 0)
                sign_sum = (raw_sum < 0)

                # Check if raw_sum exceeds [-2^39, 2^39 - 1]
                ovf = (raw_sum > MAX_INT40) or (raw_sum < MIN_INT40)

                if self.saturation and ovf:
                    final_sum = MAX_INT40 if not sign_base else MIN_INT40
                else:
                    # Modulo-2^40 wraparound
                    final_sum = to_signed(to_unsigned(raw_sum, 40), 40)

                self.accumulator = final_sum
                self.overflow = ovf
                out_valid = True
            else:
                # Clear without valid product
                self.accumulator = 0
                self.overflow = False
                out_valid = False

        return {
            "result": self.accumulator,
            "out_valid": out_valid,
            "overflow": self.overflow
        }


if __name__ == "__main__":
    mac = GoldenMAC(latency=2, saturation=False)
    print("Golden Model Self-Test:")
    # Test 1: INT8 positive x negative
    res1 = mac.step(enable=True, in_valid=True, precision_mode=0, op_a=10, op_b=to_unsigned(-5, 8), acc_clear=True)
    res2 = mac.step(enable=True, in_valid=False, precision_mode=0, op_a=0, op_b=0, acc_clear=False)
    res3 = mac.step(enable=True, in_valid=False, precision_mode=0, op_a=0, op_b=0, acc_clear=False)
    print(f"Cycle 0 retired: {res1}")
    print(f"Cycle 1 retired: {res2}")
    print(f"Cycle 2 retired: {res3}")
    assert res3["result"] == -50, f"Expected -50, got {res3['result']}"
    print("Golden Model basic test passed!")
