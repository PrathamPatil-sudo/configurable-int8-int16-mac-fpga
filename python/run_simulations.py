"""
Compiles and runs SystemVerilog testbenches using AMD/Xilinx Vivado Simulator (XSim).
Captures all simulation logs and generates verification reports.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
VIVADO_BIN = os.environ.get("XILINX_VIVADO_BIN", r"C:\Xilinx\2025.1\Vivado\bin")
RTL_DIR = os.path.join(BASE_DIR, "rtl")
TB_DIR = os.path.join(BASE_DIR, "testbench")
SIM_DIR = os.path.join(BASE_DIR, "reports", "simulation")
DATA_DIR = os.path.join(BASE_DIR, "results", "experimental_data")

os.makedirs(SIM_DIR, exist_ok=True)

XVLOG = os.path.join(VIVADO_BIN, "xvlog.bat")
XELAB = os.path.join(VIVADO_BIN, "xelab.bat")
XSIM  = os.path.join(VIVADO_BIN, "xsim.bat")

RTL_FILES = [
    os.path.join(RTL_DIR, "precision_controller.sv"),
    os.path.join(RTL_DIR, "operand_isolation.sv"),
    os.path.join(RTL_DIR, "overflow_detector.sv"),
    os.path.join(RTL_DIR, "mac_multiplier.sv"),
    os.path.join(RTL_DIR, "mac_accumulator.sv"),
    os.path.join(RTL_DIR, "mac_basic.sv"),
    os.path.join(RTL_DIR, "mac_configurable.sv"),
    os.path.join(RTL_DIR, "mac_pipelined.sv"),
    os.path.join(RTL_DIR, "mac_separate_datapaths.sv"),
    os.path.join(RTL_DIR, "mac_pipelined_isolated.sv"),
    os.path.join(RTL_DIR, "mac_top.sv"),
    os.path.join(RTL_DIR, "axi_lite_mac_ip.sv")
]

TESTBENCHES = [
    {"name": "tb_mac_basic", "top": "tb_mac_basic", "file": os.path.join(TB_DIR, "tb_mac_basic.sv")},
    {"name": "tb_mac_configurable", "top": "tb_mac_configurable", "file": os.path.join(TB_DIR, "tb_mac_configurable.sv")},
    {"name": "tb_mac_pipelined", "top": "tb_mac_pipelined", "file": os.path.join(TB_DIR, "tb_mac_pipelined.sv")},
    {"name": "tb_mac_top", "top": "tb_mac_top", "file": os.path.join(TB_DIR, "tb_mac_top.sv")}
]

def run_cmd(cmd, cwd=SIM_DIR):
    print(f"[EXEC] {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    res = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, shell=True)
    return res.returncode, res.stdout

def run_simulation_suite():
    # Copy stimulus and expected vectors to SIM_DIR for local testbench reading
    for fn in ["stimulus.txt", "expected_l1.txt", "expected_l2.txt"]:
        src = os.path.join(DATA_DIR, fn)
        dst = os.path.join(SIM_DIR, fn)
        if os.path.exists(src):
            with open(src, "r") as f_in, open(dst, "w") as f_out:
                f_out.write(f_in.read())

    overall_results = {}

    for tb in TESTBENCHES:
        tb_name = tb["name"]
        print(f"\n=======================================================")
        print(f" Running Simulation: {tb_name}")
        print(f"=======================================================")

        # Step 1: xvlog
        xvlog_cmd = [XVLOG, "-sv"] + RTL_FILES + [tb["file"]]
        code, out = run_cmd(xvlog_cmd)
        xvlog_log = os.path.join(SIM_DIR, f"{tb_name}_xvlog.log")
        with open(xvlog_log, "w") as f:
            f.write(out)
        if code != 0:
            print(f"[ERROR] xvlog failed for {tb_name} with code {code}!")
            print(out[-1000:])
            overall_results[tb_name] = "COMPILE_ERROR"
            continue

        # Step 2: xelab
        snapshot = f"{tb_name}_snap"
        xelab_cmd = [XELAB, "-debug", "typical", "-top", tb["top"], "-snapshot", snapshot]
        code, out = run_cmd(xelab_cmd)
        xelab_log = os.path.join(SIM_DIR, f"{tb_name}_xelab.log")
        with open(xelab_log, "w") as f:
            f.write(out)
        if code != 0:
            print(f"[ERROR] xelab failed for {tb_name} with code {code}!")
            print(out[-1000:])
            overall_results[tb_name] = "ELAB_ERROR"
            continue

        # Step 3: xsim
        xsim_cmd = [XSIM, snapshot, "-R"]
        code, out = run_cmd(xsim_cmd)
        xsim_log = os.path.join(SIM_DIR, f"{tb_name}_xsim.log")
        with open(xsim_log, "w") as f:
            f.write(out)

        print(out)
        has_error = (code != 0) or ("[FAIL]" in out) or ("FATAL" in out.upper()) or ("ERROR" in out.upper() and "0 FAILED" not in out)
        if not has_error:
            print(f"[SUCCESS] {tb_name} PASSED completely!")
            overall_results[tb_name] = "PASS"
        else:
            print(f"[FAIL] {tb_name} encountered errors!")
            overall_results[tb_name] = "FAIL"

    summary_file = os.path.join(SIM_DIR, "simulation_summary.txt")
    with open(summary_file, "w") as f:
        f.write("=== SIMULATION VERIFICATION SUMMARY ===\n")
        for k, v in overall_results.items():
            f.write(f"{k}: {v}\n")
    print("\n" + open(summary_file).read())

if __name__ == "__main__":
    run_simulation_suite()
