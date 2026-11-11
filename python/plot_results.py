"""
Generates publication-quality comparison charts and plots for the MAC architecture report:
1. Resource Utilization Breakdown (LUTs, FFs, DSPs across all architectures)
2. Operating Frequency (Fmax) and Initiation Interval Comparison
3. MAC Throughput Comparison (MMAC/s)
4. Dynamic and Static Power Estimation Breakdown
5. DSP vs LUT Resource and Timing Trade-off
"""

import os
import json
import matplotlib.pyplot as plt
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
DATA_FILE = os.path.join(BASE_DIR, "results", "comparison_tables", "mac_architectures_comparison.json")
GRAPHS_DIR = os.path.join(BASE_DIR, "results", "graphs")
os.makedirs(GRAPHS_DIR, exist_ok=True)

# Set matplotlib style
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')
plt.rcParams['font.sans-serif'] = 'Arial'
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['figure.dpi'] = 300

def generate_plots():
    if not os.path.exists(DATA_FILE):
        print(f"Data file not found at {DATA_FILE}. Run experiments first.")
        return

    with open(DATA_FILE, "r") as f:
        data = json.load(f)

    arch_ids = [d["Architecture_ID"] for d in data]
    arch_names = [d["Architecture_Name"] for d in data]
    luts = [d["LUTs"] for d in data]
    ffs = [d["FFs"] for d in data]
    dsps = [d["DSPs"] for d in data]
    fmax = [d["Fmax_MHz"] for d in data]
    throughput = [d["Throughput_MMAC_s"] for d in data]
    dyn_pwr = [d["Dynamic_Power_W"] * 1000 for d in data]  # mW
    stat_pwr = [d["Static_Power_W"] * 1000 for d in data]  # mW

    x = np.arange(len(arch_ids))
    width = 0.35

    # -------------------------------------------------------------
    # Plot 1: Resource Utilization Breakdown (LUTs & FFs)
    # -------------------------------------------------------------
    fig, ax1 = plt.subplots(figsize=(10, 5))
    bar1 = ax1.bar(x - width/2, luts, width, label='CLB LUTs', color='#1f77b4', edgecolor='black')
    bar2 = ax1.bar(x + width/2, ffs, width, label='CLB Flip-Flops', color='#ff7f0e', edgecolor='black')

    ax1.set_xlabel('Architectural Version', fontweight='bold', fontsize=11)
    ax1.set_ylabel('Resource Count', fontweight='bold', fontsize=11)
    ax1.set_title('FPGA Logic Resource Utilization Comparison (XC7Z020)', fontweight='bold', fontsize=13)
    ax1.set_xticks(x)
    ax1.set_xticklabels(arch_ids, fontweight='bold', fontsize=10)
    ax1.legend(loc='upper left', frameon=True)

    for b in bar1:
        h = b.get_height()
        ax1.annotate(f'{int(h)}', xy=(b.get_x() + b.get_width()/2, h),
                     xytext=(0, 3), textcoords="offset points", ha='center', va='bottom', fontsize=8)
    for b in bar2:
        h = b.get_height()
        ax1.annotate(f'{int(h)}', xy=(b.get_x() + b.get_width()/2, h),
                     xytext=(0, 3), textcoords="offset points", ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    p1 = os.path.join(GRAPHS_DIR, "resource_utilization_comparison.png")
    plt.savefig(p1)
    plt.close()
    print(f"[GRAPH] Saved {p1}")

    # -------------------------------------------------------------
    # Plot 2: Maximum Frequency (Fmax) & Throughput Comparison
    # -------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(10, 5))
    bars = ax.bar(x, fmax, 0.5, color='#2ca02c', edgecolor='black')
    ax.set_xlabel('Architectural Version', fontweight='bold', fontsize=11)
    ax.set_ylabel('Maximum Achievable Frequency (MHz)', fontweight='bold', fontsize=11)
    ax.set_title('Post-Route Timing Closure & Maximum Frequency (Fmax)', fontweight='bold', fontsize=13)
    ax.set_xticks(x)
    ax.set_xticklabels(arch_ids, fontweight='bold', fontsize=10)

    for b in bars:
        h = b.get_height()
        ax.annotate(f'{h:.1f} MHz', xy=(b.get_x() + b.get_width()/2, h),
                    xytext=(0, 3), textcoords="offset points", ha='center', va='bottom', fontsize=9, fontweight='bold')

    plt.tight_layout()
    p2 = os.path.join(GRAPHS_DIR, "fmax_throughput_comparison.png")
    plt.savefig(p2)
    plt.close()
    print(f"[GRAPH] Saved {p2}")

    # -------------------------------------------------------------
    # Plot 3: Power Dissipation Breakdown (Dynamic vs Static)
    # -------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(x, dyn_pwr, 0.45, label='Dynamic Power (mW)', color='#d62728', edgecolor='black')
    ax.bar(x, stat_pwr, 0.45, bottom=dyn_pwr, label='Static Power (mW)', color='#9467bd', edgecolor='black')

    ax.set_xlabel('Architectural Version', fontweight='bold', fontsize=11)
    ax.set_ylabel('Estimated On-Chip Power (mW)', fontweight='bold', fontsize=11)
    ax.set_title('Vivado Post-Route Power Estimation Comparison', fontweight='bold', fontsize=13)
    ax.set_xticks(x)
    ax.set_xticklabels(arch_ids, fontweight='bold', fontsize=10)
    ax.legend(loc='lower right', frameon=True)

    plt.tight_layout()
    p3 = os.path.join(GRAPHS_DIR, "power_breakdown_comparison.png")
    plt.savefig(p3)
    plt.close()
    print(f"[GRAPH] Saved {p3}")

    # -------------------------------------------------------------
    # Plot 4: DSP vs LUT Implementation Trade-Off
    # -------------------------------------------------------------
    fig, (ax_l, ax_r) = plt.subplots(1, 2, figsize=(10, 4.5))
    dsp_idx = [i for i, a in enumerate(arch_ids) if a in ["V6_DSP", "V6_LUT"]]
    if len(dsp_idx) == 2:
        labels = ["DSP48E1 Mapped", "LUT-Based Multiplier"]
        comp_luts = [luts[i] for i in dsp_idx]
        comp_fmax = [fmax[i] for i in dsp_idx]

        ax_l.bar(labels, comp_luts, color=['#1f77b4', '#e377c2'], edgecolor='black', width=0.4)
        ax_l.set_ylabel('LUT Count', fontweight='bold')
        ax_l.set_title('LUT Utilization Overhead', fontweight='bold')
        for i, v in enumerate(comp_luts):
            ax_l.text(i, v + 5, f'{v} LUTs', ha='center', fontweight='bold')

        ax_r.bar(labels, comp_fmax, color=['#2ca02c', '#bcbd22'], edgecolor='black', width=0.4)
        ax_r.set_ylabel('Fmax (MHz)', fontweight='bold')
        ax_r.set_title('Timing Performance Comparison', fontweight='bold')
        for i, v in enumerate(comp_fmax):
            ax_r.text(i, v + 5, f'{v:.1f} MHz', ha='center', fontweight='bold')

        plt.tight_layout()
        p4 = os.path.join(GRAPHS_DIR, "dsp_vs_lut_tradeoff.png")
        plt.savefig(p4)
        plt.close()
        print(f"[GRAPH] Saved {p4}")

    print("All comparison graphs generated successfully!")

if __name__ == "__main__":
    generate_plots()
