import sys
sys.stdout.reconfigure(encoding='utf-8')
from pynq_uart_comm import PynqUart

p = PynqUart()
try:
    print("=== PYNQ OVERLAY & PL INSPECTION ===")
    cmd = (
        "python3 -c \""
        "import pynq; "
        "print('PYNQ Version:', pynq.__version__); "
        "print('Bitfile loaded:', pynq.PL.bitfile_name); "
        "print('Active Device:', pynq.Device.active_device.name)"
        "\""
    )
    print(p.run_cmd(cmd))

    print("=== EXISTING OVERLAYS ===")
    print(p.run_cmd("ls -la /home/xilinx/pynq/overlays/ 2>/dev/null || ls -la /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq/overlays/"))

    print("=== CREATE PROJECT DIRECTORY ===")
    proj_name = os.environ.get("PYNQ_PROJ_NAME", "configurable-int8-int16-mac-fpga")
    print(p.run_cmd(f"mkdir -p /home/xilinx/{proj_name}"))
    print(p.run_cmd(f"mkdir -p /home/xilinx/jupyter_notebooks/{proj_name}"))
    print(p.run_cmd(f"ls -ld /home/xilinx/{proj_name} /home/xilinx/jupyter_notebooks/{proj_name}"))
finally:
    p.close()
