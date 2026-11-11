"""
PYNQ UART Shell Communication and Execution Utility
Provides reliable command execution, file transfer, and hardware interaction
over the PYNQ-Z2 FTDI UART console on COM11.
"""

import serial
import time
import re
import sys

class PynqUart:
    def __init__(self, port="COM11", baud=115200, timeout=2):
        self.port = port
        self.baud = baud
        self.timeout = timeout
        self.ser = serial.Serial(port, baud, timeout=timeout)
        self._flush()
        # Ensure we have a clean prompt
        self.run_cmd("")

    def _flush(self):
        time.sleep(0.2)
        if self.ser.in_waiting:
            self.ser.read(self.ser.in_waiting)

    def run_cmd(self, cmd, wait_time=0.8, timeout=30):
        self._flush()
        self.ser.write((cmd + "\n").encode("utf-8"))
        
        start = time.time()
        buf = b""
        # Wait until prompt or timeout
        while time.time() - start < timeout:
            if self.ser.in_waiting:
                chunk = self.ser.read(self.ser.in_waiting)
                buf += chunk
                # Check for standard prompt: xilinx@pynq:~$ or # or %
                decoded = buf.decode("utf-8", errors="replace")
                if "xilinx@pynq:" in decoded and decoded.rstrip().endswith("$"):
                    break
            else:
                time.sleep(0.1)
                
        decoded = buf.decode("utf-8", errors="replace")
        # Clean terminal ANSI escape sequences
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        cleaned = ansi_escape.sub('', decoded)
        return cleaned

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()

if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    p = PynqUart()
    try:
        print("=== HOSTNAME ===")
        print(p.run_cmd("hostname"))

        print("=== IP ADDR ===")
        print(p.run_cmd("ip addr"))

        print("=== JUPYTER STATUS ===")
        print(p.run_cmd("systemctl status jupyter.service --no-pager"))

        print("=== PYNQ & PYTHON ===")
        print(p.run_cmd("python3 --version"))
        print(p.run_cmd("python3 -c 'import pynq; print(pynq.__version__)'"))
        print(p.run_cmd("uname -a"))
    finally:
        p.close()
