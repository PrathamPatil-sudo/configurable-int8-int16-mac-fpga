"""
Transfer bitstream, hardware handoff, drivers, and test vectors to PYNQ-Z2
via SFTP over SSH (192.168.2.99:22).
"""

import paramiko
import os
import sys

PYNQ_IP = os.environ.get("PYNQ_IP", "192.168.2.99")
PYNQ_PORT = int(os.environ.get("PYNQ_PORT", "22"))
PYNQ_USER = os.environ.get("PYNQ_USER", "xilinx")
PYNQ_PASS = os.environ.get("PYNQ_PASS", "xilinx")

REMOTE_DIR = os.environ.get("PYNQ_REMOTE_DIR", "/home/xilinx/configurable-int8-int16-mac-fpga")
REMOTE_JUPYTER_DIR = os.environ.get("PYNQ_JUPYTER_DIR", "/home/xilinx/jupyter_notebooks/configurable-int8-int16-mac-fpga")

FILES_TO_TRANSFER = [
    ("hardware/pynq_mac.bit", "pynq_mac.bit"),
    ("hardware/pynq_mac.hwh", "pynq_mac.hwh"),
    ("python/pynq_mac_test.py", "pynq_mac_test.py"),
    ("python/golden_model.py", "golden_model.py"),
    ("results/experimental_data/stimulus.txt", "stimulus.txt"),
    ("results/experimental_data/expected_l2.txt", "expected_l2.txt"),
]

def transfer():
    print(f"[SFTP] Connecting to PYNQ-Z2 at {PYNQ_IP}:{PYNQ_PORT} as {PYNQ_USER}...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PYNQ_IP, port=PYNQ_PORT, username=PYNQ_USER, password=PYNQ_PASS, timeout=10)
    print("[SFTP] SSH connection established successfully!")

    sftp = ssh.open_sftp()
    
    # Ensure directories exist
    for d in [REMOTE_DIR, REMOTE_JUPYTER_DIR]:
        try:
            sftp.stat(d)
        except IOError:
            sftp.mkdir(d)

    for local_path, filename in FILES_TO_TRANSFER:
        if not os.path.exists(local_path):
            print(f"[ERROR] Local file not found: {local_path}")
            continue
        
        file_size = os.path.getsize(local_path)
        print(f"[TRANSFERRING] {local_path} ({file_size:,} bytes) -> {REMOTE_DIR}/{filename}...")
        
        # Upload to main project dir
        remote_dest = f"{REMOTE_DIR}/{filename}"
        sftp.put(local_path, remote_dest)
        
        # Also mirror bit/hwh/scripts to Jupyter dir for easy browser access
        remote_jup = f"{REMOTE_JUPYTER_DIR}/{filename}"
        sftp.put(local_path, remote_jup)
        
        print(f"[OK] {filename} successfully transferred and mirrored!")

    sftp.close()
    ssh.close()
    print("[SUCCESS] All files transferred to PYNQ-Z2 successfully!")

if __name__ == "__main__":
    transfer()
