with open('vivado/pynq_overlay/pynq_mac.hwh', 'r', encoding='utf-8') as f:
    text = f.read()

import re
matches = re.findall(r'<MODULE\s+[^>]*INSTANCE="([^"]+)"[^>]*VLNV="([^"]+)"', text)
for inst, vlnv in matches:
    print(f"Module Instance: {inst} | VLNV: {vlnv}")

mem_map = re.findall(r'<MEMRANGE\s+[^>]*>', text)
print("\n=== MEMORY MAP RANGES ===")
for mm in mem_map:
    print(mm)
