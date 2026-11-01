from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
b=json.loads((R/'validation/build_receipt.json').read_text());h=json.loads((R/'hardware/handoff_receipt.json').read_text())
assert sha(R/'build/camera_control_console.elf')==b['elf_sha256'],'ELF changed'
for n,v in b['sources'].items():assert sha(R/'src'/n)==v,'Source changed: '+n
for n,k in [('camera_cup_follow_v1.bit','bit_sha256'),('camera_cup_follow_v1.xsa','xsa_sha256'),('ps7_init.tcl','psinit_sha256')]:assert sha(R/'hardware'/n)==h[k],'Hardware changed'
assert 'follow_match' not in (R/'build_app.py').read_text() and 'follow_service' not in (R/'build_app.py').read_text()
f=json.loads((R/'validation/firmware_host_receipt.json').read_text());assert sha(R/'src/cup_commands.c')==f['source_sha256']
print('FIXED_CONSOLE_INPUTS_VERIFIED -- no auto-follow service; starts paused')
