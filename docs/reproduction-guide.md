# Reproduction Guide

This guide provides step-by-step instructions to reproduce all simulation results, Vivado synthesis/implementation experiments, IP packaging, bitstream generation, and physical PYNQ-Z2 hardware tests.

---

## 1. Prerequisites & Toolchain Requirements

### Software
- **AMD Vivado Design Suite:** Vivado 2025.1 (or 2020.2+). Ensure the **Zynq-7000 device family** (`xc7z020`) is installed.
- **Python:** Python 3.8 or higher.
  ```bash
  pip install -r requirements.txt
  ```
- **Operating System:** Windows 10/11 or Ubuntu 20.04/22.04 LTS.

### Hardware (Optional, for physical FPGA testing)
- **Development Board:** Digilent PYNQ-Z2.
- **MicroSD Card:** Flashed with PYNQ v3.0.1 or v3.1.1 image.
- **Connectivity:** Micro-USB cable (UART/power) and Ethernet cable.

---

## 2. Directory Layout & Setup

Clone the repository and navigate into the project directory:

```bash
git clone https://github.com/PrathamPatil-sudo/configurable-int8-int16-mac-fpga.git
cd configurable-int8-int16-mac-fpga
```

---

## 3. Step-by-Step Reproduction

### Step 1: Generate Verification Vectors & Run Golden Model
Run the vector generator to recreate the 2,362 stimulus vectors and verify the Python bit-true reference model:

```bash
cd python
python generate_vectors.py
python golden_model.py
```

Expected Output:
```text
Generated 2362 vectors in results/experimental_data/
All golden model checks PASSED.
```

---

### Step 2: Run SystemVerilog Simulations via Vivado XSim
Execute the automated simulation runner, which compiles all testbenches using AMD Vivado Simulator (XSim):

```bash
python run_simulations.py
```

Or run individual testbenches manually via Vivado command line:

```bash
# Compile and simulate the top-level co-simulation testbench
xvlog -sv rtl/*.sv testbench/tb_mac_top.sv
xelab tb_mac_top -s tb_mac_top_sim
xsim tb_mac_top_sim -R
```

Expected Output:
```text
======================================================================
 SIMULATION SUMMARY: ALL TESTBENCHES PASSED (100% BIT-TRUE MATCH)
======================================================================
  tb_mac_basic.sv:        20 / 20 vectors PASSED
  tb_mac_configurable.sv: 40 / 40 vectors PASSED
  tb_mac_pipelined.sv:    60 / 60 vectors PASSED
  tb_mac_top.sv:          2362 / 2362 vectors PASSED
```

---

### Step 3: Run Synthesis and Implementation for All 7 Architectures
To synthesize and implement all seven architectural variants (V1 through V6_LUT) and generate post-route utilization, timing, and power reports:

```bash
python run_vivado_experiments.py
```

Or execute individual Tcl scripts directly in Vivado batch mode:

```bash
# Example: Run implementation for Architecture V5 (Pipelined with Operand Isolation)
vivado -mode batch -nojournal -nolog -source tcl/run_V5.tcl
```

All generated reports and checkpoints will be saved in `reports/` and `vivado/`.

---

### Step 4: Package the Custom AXI4-Lite MAC IP
To package the synthesizable RTL into an IP-XACT component for the Vivado IP Catalog:

```bash
vivado -mode batch -nojournal -nolog -source tcl/package_mac_ip.tcl
```

The packaged IP will be created in `vivado/ip_repo/axi_lite_mac_ip`.

---

### Step 5: Build the Complete Zynq SoC Overlay & Bitstream
To build the Zynq Processing System block design, connect the AXI Interconnect, synthesize, implement, and write the FPGA bitstream:

```bash
vivado -mode batch -nojournal -nolog -source tcl/build_pynq_overlay.tcl
```

Outputs generated:
- Bitstream: `hardware/pynq_mac.bit`
- Hardware Handoff: `hardware/pynq_mac.hwh`
- SoC Post-Route Reports: `hardware/reports/pynq_soc_*.rpt`

---

### Step 6: Physical Hardware Testing on PYNQ-Z2
1. Boot the PYNQ-Z2 board with PYNQ Linux and connect it to your local network.
2. Transfer the hardware overlay and Python driver to the board:
   ```bash
   scp hardware/pynq_mac.bit hardware/pynq_mac.hwh python/pynq_mac_test.py python/golden_model.py results/experimental_data/stimulus.txt xilinx@<BOARD_IP>:/home/xilinx/
   ```
3. SSH into the board and execute the physical hardware test driver:
   ```bash
   ssh xilinx@<BOARD_IP>
   sudo BOARD=Pynq-Z2 /usr/local/share/pynq-venv/bin/python3 -u pynq_mac_test.py
   ```

Expected Output on Hardware:
```text
======================================================================
  PHYSICAL FPGA VALIDATION ON AMD/XILINX ZYNQ-7000 (PYNQ-Z2)
======================================================================
[PYNQ] Programming FPGA PL Fabric with Overlay: pynq_mac.bit...
[PYNQ] Bitstream programmed successfully in 1916.97 ms!
[PYNQ] Connected via overlay.axi_lite_mac_ip_0.mmio at 0x43c00000
...
[REGRESSION RESULT] 2361/2361 vectors PASSED in 0.65s!
======================================================================
 PHYSICAL FPGA TEST SUMMARY: 2379 PASSED, 0 FAILED
======================================================================
```
