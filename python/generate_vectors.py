"""
Generates deterministic, comprehensive test vectors for the MAC architectures.
Includes boundary conditions, signed arithmetic corners, random distributions,
control signal toggling, and overflow edge cases.
"""

import os
import random
from golden_model import GoldenMAC, to_unsigned, to_signed

def generate_vectors(num_random=1000, seed=42):
    random.seed(seed)
    vectors = []

    # 1. Reset / Initialization
    vectors.append({"rst": 1, "enable": 1, "in_valid": 0, "mode": 0, "a": 0, "b": 0, "clear": 0})
    vectors.append({"rst": 0, "enable": 1, "in_valid": 0, "mode": 0, "a": 0, "b": 0, "clear": 1})

    # 2. INT8 Boundary Tests
    int8_corners = [-128, -127, -1, 0, 1, 126, 127]
    for a in int8_corners:
        for b in int8_corners:
            vectors.append({
                "rst": 0, "enable": 1, "in_valid": 1, "mode": 0,
                "a": to_unsigned(a, 8),
                "b": to_unsigned(b, 8),
                "clear": 0
            })

    # Clear before INT16 tests
    vectors.append({"rst": 0, "enable": 1, "in_valid": 0, "mode": 1, "a": 0, "b": 0, "clear": 1})

    # 3. INT16 Boundary Tests
    int16_corners = [-32768, -32767, -1, 0, 1, 32766, 32767]
    for a in int16_corners:
        for b in int16_corners:
            vectors.append({
                "rst": 0, "enable": 1, "in_valid": 1, "mode": 1,
                "a": to_unsigned(a, 16),
                "b": to_unsigned(b, 16),
                "clear": 0
            })

    # 4. Alternating Precision & Mode Switching with continuous streaming
    for i in range(100):
        mode = i % 2
        if mode == 0:
            a = random.randint(-128, 127)
            b = random.randint(-128, 127)
            a_u = to_unsigned(a, 8)
            b_u = to_unsigned(b, 8)
        else:
            a = random.randint(-32768, 32767)
            b = random.randint(-32768, 32767)
            a_u = to_unsigned(a, 16)
            b_u = to_unsigned(b, 16)

        vectors.append({
            "rst": 0, "enable": 1, "in_valid": 1, "mode": mode,
            "a": a_u, "b": b_u, "clear": 0
        })

    # 5. Enable Low and Idle Gaps (Operand Isolation test)
    for _ in range(50):
        in_val = random.choice([0, 1])
        en = random.choice([0, 1, 1, 1]) # mostly enabled
        mode = random.choice([0, 1])
        a = random.randint(0, 65535)
        b = random.randint(0, 65535)
        vectors.append({
            "rst": 0, "enable": en, "in_valid": in_val, "mode": mode,
            "a": a, "b": b, "clear": 0
        })

    # 6. Overflow Stress Test
    # Accumulate maximum positive products repeatedly
    vectors.append({"rst": 0, "enable": 1, "in_valid": 0, "mode": 1, "a": 0, "b": 0, "clear": 1})
    for _ in range(100):
        vectors.append({
            "rst": 0, "enable": 1, "in_valid": 1, "mode": 1,
            "a": to_unsigned(32767, 16),
            "b": to_unsigned(32767, 16),
            "clear": 0
        })

    # 7. Additional Randomized Tests
    for _ in range(num_random):
        mode = random.choice([0, 1])
        in_val = random.choice([1, 1, 1, 0])
        clear = 1 if random.random() < 0.05 else 0
        if mode == 0:
            a_u = to_unsigned(random.randint(-128, 127), 8)
            b_u = to_unsigned(random.randint(-128, 127), 8)
        else:
            a_u = to_unsigned(random.randint(-32768, 32767), 16)
            b_u = to_unsigned(random.randint(-32768, 32767), 16)

        vectors.append({
            "rst": 0, "enable": 1, "in_valid": in_val, "mode": mode,
            "a": a_u, "b": b_u, "clear": clear
        })

    # Flush pipeline
    for _ in range(10):
        vectors.append({"rst": 0, "enable": 1, "in_valid": 0, "mode": 0, "a": 0, "b": 0, "clear": 0})

    return vectors


def export_vectors(vectors, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    stim_path = os.path.join(output_dir, "stimulus.txt")
    resp_l2_path = os.path.join(output_dir, "expected_l2.txt")
    resp_l1_path = os.path.join(output_dir, "expected_l1.txt")

    mac_l2 = GoldenMAC(latency=2, saturation=False)
    mac_l1 = GoldenMAC(latency=1, saturation=False)

    with open(stim_path, "w") as f_stim, \
         open(resp_l2_path, "w") as f_l2, \
         open(resp_l1_path, "w") as f_l1:

        for vec in vectors:
            rst = vec["rst"]
            en = vec["enable"]
            in_val = vec["in_valid"]
            mode = vec["mode"]
            a = vec["a"]
            b = vec["b"]
            clr = vec["clear"]

            # Write stimulus: rst, en, in_val, mode, a (16b hex), b (16b hex), clr
            f_stim.write(f"{rst} {en} {in_val} {mode} {a:04X} {b:04X} {clr}\n")

            if rst:
                mac_l2.reset()
                mac_l1.reset()
                out2 = {"result": 0, "out_valid": False, "overflow": False}
                out1 = {"result": 0, "out_valid": False, "overflow": False}
            else:
                out2 = mac_l2.step(en, in_val, mode, a, b, clr)
                out1 = mac_l1.step(en, in_val, mode, a, b, clr)

            # Write expected: result (40b hex), out_valid, overflow
            u_res2 = to_unsigned(out2["result"], 40)
            f_l2.write(f"{u_res2:010X} {1 if out2['out_valid'] else 0} {1 if out2['overflow'] else 0}\n")

            u_res1 = to_unsigned(out1["result"], 40)
            f_l1.write(f"{u_res1:010X} {1 if out1['out_valid'] else 0} {1 if out1['overflow'] else 0}\n")

    print(f"Generated {len(vectors)} test vectors saved to {stim_path}")


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    out_dir = os.path.join(repo_root, "results", "experimental_data")
    vecs = generate_vectors(num_random=2000, seed=2026)
    export_vectors(vecs, out_dir)
