"""
Automates Vivado synthesis, implementation, timing, resource utilization,
and power analysis across all MAC architectural versions on XC7Z020CLG400-1.
"""

import os
import re
import subprocess
import json
import csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
VIVADO_BIN = os.environ.get("XILINX_VIVADO_BAT", r"C:\Xilinx\2025.1\Vivado\bin\vivado.bat")
RTL_DIR = os.path.join(BASE_DIR, "rtl")
XDC_FILE = os.path.join(BASE_DIR, "constraints", "mac_timing.xdc").replace("\\", "/")
REPORTS_DIR = os.path.join(BASE_DIR, "reports")
RESULTS_DIR = os.path.join(BASE_DIR, "results", "comparison_tables")
VCD_FILE = os.path.join(REPORTS_DIR, "simulation", "mac_top_activity.vcd").replace("\\", "/")

os.makedirs(os.path.join(REPORTS_DIR, "synthesis"), exist_ok=True)
os.makedirs(os.path.join(REPORTS_DIR, "timing"), exist_ok=True)
os.makedirs(os.path.join(REPORTS_DIR, "power"), exist_ok=True)
os.makedirs(RESULTS_DIR, exist_ok=True)

ARCHITECTURES = [
    {
        "id": "V1",
        "name": "Basic Non-Pipelined INT16 MAC",
        "top": "mac_basic",
        "generics": [],
        "latency": 1,
        "ii": 1,
        "note": "Baseline non-pipelined INT16"
    },
    {
        "id": "V2",
        "name": "Shared Configurable INT8/INT16 MAC",
        "top": "mac_configurable",
        "generics": [],
        "latency": 1,
        "ii": 1,
        "note": "Resource-shared single-cycle"
    },
    {
        "id": "V3",
        "name": "Pipelined Configurable MAC",
        "top": "mac_pipelined",
        "generics": [],
        "latency": 2,
        "ii": 1,
        "note": "Shared pipelined (no isolation)"
    },
    {
        "id": "V4",
        "name": "Separate INT8/INT16 Datapaths",
        "top": "mac_separate_datapaths",
        "generics": [],
        "latency": 2,
        "ii": 1,
        "note": "Dedicated 8x8 and 16x16 multipliers"
    },
    {
        "id": "V5",
        "name": "Pipelined MAC with Operand Isolation",
        "top": "mac_pipelined_isolated",
        "generics": [],
        "latency": 2,
        "ii": 1,
        "note": "Input operand isolation enabled"
    },
    {
        "id": "V6_DSP",
        "name": "Final Optimized Architecture (DSP)",
        "top": "mac_top",
        "generics": ["ENABLE_ISOLATION=1'b1", "USE_DSP=\"yes\""],
        "latency": 2,
        "ii": 1,
        "note": "Full feature top with DSP inference"
    },
    {
        "id": "V6_LUT",
        "name": "Optimized Architecture (Forced LUTs)",
        "top": "mac_top",
        "generics": ["ENABLE_ISOLATION=1'b1", "USE_DSP=\"no\""],
        "latency": 2,
        "ii": 1,
        "note": "Forced LUT-based multiplier mapping"
    }
]

def generate_tcl_script(arch):
    arch_id = arch["id"]
    top = arch["top"]
    gen_args = ""
    for g in arch.get("generics", []):
        gen_args += f" -generic {{{g}}}"

    tcl_content = f"""# Vivado Tcl Script for {arch_id} ({arch['name']})
set_param general.maxThreads 4

# Read RTL Sources
read_verilog -sv [glob {RTL_DIR.replace("\\", "/")}/*.sv]

# Read Timing Constraints
read_xdc {XDC_FILE}

# Synthesis (Out-of-Context for pure core characterization)
puts "=== RUNNING SYNTHESIS FOR {arch_id} ==="
synth_design -top {top} -part xc7z020clg400-1 -mode out_of_context{gen_args}

# Synthesis Reports
report_utilization -file {REPORTS_DIR.replace("\\", "/")}/synthesis/{arch_id}_utilization_synth.rpt
report_timing_summary -file {REPORTS_DIR.replace("\\", "/")}/timing/{arch_id}_timing_synth.rpt

# Implementation Flow
puts "=== RUNNING IMPLEMENTATION FOR {arch_id} ==="
opt_design
place_design
route_design

# Implementation Reports
report_utilization -file {REPORTS_DIR.replace("\\", "/")}/synthesis/{arch_id}_utilization_route.rpt
report_timing_summary -max_paths 10 -file {REPORTS_DIR.replace("\\", "/")}/timing/{arch_id}_timing_route.rpt
report_power -file {REPORTS_DIR.replace("\\", "/")}/power/{arch_id}_power.rpt

# Write checkpoint
write_checkpoint -force {BASE_DIR.replace("\\", "/")}/vivado/{arch_id}_routed.dcp

puts "=== COMPLETED {arch_id} ==="
exit 0
"""
    tcl_path = os.path.join(BASE_DIR, "vivado", f"run_{arch_id}.tcl")
    with open(tcl_path, "w") as f:
        f.write(tcl_content)
    return tcl_path

def parse_reports(arch_id, arch):
    util_file = os.path.join(REPORTS_DIR, "synthesis", f"{arch_id}_utilization_route.rpt")
    timing_file = os.path.join(REPORTS_DIR, "timing", f"{arch_id}_timing_route.rpt")
    power_file = os.path.join(REPORTS_DIR, "power", f"{arch_id}_power.rpt")

    # Default metrics
    luts = 0
    ffs = 0
    dsps = 0
    bram = 0
    wns = 0.0
    tns = 0.0
    fmax_mhz = 100.0
    dyn_pwr_w = 0.0
    stat_pwr_w = 0.0

    # Parse Utilization
    if os.path.exists(util_file):
        with open(util_file, "r") as f:
            content = f.read()
            # Match Slice LUTs
            m_lut = re.search(r"Slice LUTs\s*\|\s*(\d+)", content)
            if not m_lut:
                m_lut = re.search(r"CLB LUTs\s*\|\s*(\d+)", content)
            if m_lut:
                luts = int(m_lut.group(1))

            # Match Slice Registers (FFs)
            m_ff = re.search(r"Slice Registers\s*\|\s*(\d+)", content)
            if not m_ff:
                m_ff = re.search(r"CLB Registers\s*\|\s*(\d+)", content)
            if m_ff:
                ffs = int(m_ff.group(1))

            # Match DSPs
            m_dsp = re.search(r"DSPs\s*\|\s*(\d+)", content)
            if m_dsp:
                dsps = int(m_dsp.group(1))

            # Match Block RAM
            m_bram = re.search(r"Block RAM Tile\s*\|\s*(\d+)", content)
            if m_bram:
                bram = int(m_bram.group(1))

    # Parse Timing
    if os.path.exists(timing_file):
        with open(timing_file, "r") as f:
            content = f.read()
            m_table = re.search(r"WNS\(ns\)\s+TNS\(ns\)[^\n]*\n\s*[-]+\s+[-]+[^\n]*\n\s*(-?[\d\.]+)\s+(-?[\d\.]+)", content)
            if m_table:
                wns = float(m_table.group(1))
                tns = float(m_table.group(2))
            else:
                m_wns = re.search(r"Worst Negative Slack \(WNS\):\s*(-?[\d\.]+)\s*ns", content)
                if m_wns:
                    wns = float(m_wns.group(1))
                m_tns = re.search(r"Total Negative Slack \(TNS\):\s*(-?[\d\.]+)\s*ns", content)
                if m_tns:
                    tns = float(m_tns.group(1))

            # Calculate Fmax from target clock period (10.0 ns) and WNS
            target_period = 10.0
            if wns >= 0:
                min_period = target_period - wns
                fmax_mhz = 1000.0 / min_period if min_period > 0 else 100.0
            else:
                min_period = target_period - wns
                fmax_mhz = 1000.0 / min_period

    # Parse Power
    if os.path.exists(power_file):
        with open(power_file, "r") as f:
            content = f.read()
            m_dyn = re.search(r"Total On-Chip Power\s*\|\s*[\d\.]+\s*W\s*\|\s*Dynamic\s*\(W\)\s*\|\s*([\d\.]+)", content)
            if not m_dyn:
                m_dyn = re.search(r"Dynamic \(W\)\s*\|\s*([\d\.]+)", content)
            if m_dyn:
                dyn_pwr_w = float(m_dyn.group(1))

            m_stat = re.search(r"Device Static \(W\)\s*\|\s*([\d\.]+)", content)
            if m_stat:
                stat_pwr_w = float(m_stat.group(1))

    latency = arch["latency"]
    ii = arch["ii"]
    throughput_mops = fmax_mhz / ii  # Mega MAC Operations / sec

    return {
        "Architecture_ID": arch_id,
        "Architecture_Name": arch["name"],
        "LUTs": luts,
        "FFs": ffs,
        "DSPs": dsps,
        "BRAM": bram,
        "Target_Clock_MHz": 100.0,
        "WNS_ns": round(wns, 3),
        "TNS_ns": round(tns, 3),
        "Fmax_MHz": round(fmax_mhz, 2),
        "Latency_Cycles": latency,
        "II_Cycles": ii,
        "Throughput_MMAC_s": round(throughput_mops, 2),
        "Dynamic_Power_W": round(dyn_pwr_w, 4),
        "Static_Power_W": round(stat_pwr_w, 4),
        "Total_Power_W": round(dyn_pwr_w + stat_pwr_w, 4),
        "Note": arch["note"]
    }

def run_experiments():
    os.makedirs(os.path.join(BASE_DIR, "vivado"), exist_ok=True)
    results = []

    for arch in ARCHITECTURES:
        arch_id = arch["id"]
        dcp_file = os.path.join(BASE_DIR, "vivado", f"{arch_id}_routed.dcp")
        rpt_file = os.path.join(REPORTS_DIR, "timing", f"{arch_id}_timing_route.rpt")

        if os.path.exists(dcp_file) and os.path.exists(rpt_file):
            print(f"\n[INFO] {arch_id} already implemented and routed. Parsing existing reports...")
            data = parse_reports(arch_id, arch)
            results.append(data)
            print(f"[METRICS for {arch_id}]: {json.dumps(data, indent=2)}")
            continue

        print(f"\n=======================================================")
        print(f" Executing Vivado Flow for {arch_id}: {arch['name']}")
        print(f"=======================================================")
        tcl_script = generate_tcl_script(arch)
        cmd = f'"{VIVADO_BIN}" -mode batch -nojournal -nolog -source "{tcl_script}"'
        print(f"[CMD] {cmd}")
        res = subprocess.run(cmd, cwd=os.path.join(BASE_DIR, "vivado"), shell=True)
        if res.returncode != 0:
            print(f"[WARNING] Vivado run for {arch_id} exited with code {res.returncode}")

        data = parse_reports(arch_id, arch)
        results.append(data)
        print(f"[METRICS for {arch_id}]: {json.dumps(data, indent=2)}")

    # Export Results to JSON and CSV
    json_path = os.path.join(RESULTS_DIR, "mac_architectures_comparison.json")
    csv_path = os.path.join(RESULTS_DIR, "mac_architectures_comparison.csv")

    with open(json_path, "w") as f:
        json.dump(results, f, indent=2)

    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        writer.writeheader()
        writer.writerows(results)

    print(f"\nSuccessfully generated comparison tables at:\n- {csv_path}\n- {json_path}")

if __name__ == "__main__":
    run_experiments()
