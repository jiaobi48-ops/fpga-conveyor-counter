"""Check the exact integrated bit/XSA/ELF tuple and its source receipt."""
from pathlib import Path
import hashlib,json,zipfile,struct
R=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
receipt=json.loads((R/'release_receipt.json').read_text(encoding='utf-8'))
for name,want in receipt['files'].items():assert sha(R/name)==want,'Release file changed: '+name
for name,want in receipt['sources'].items():assert sha(R/'src'/name)==want,'Firmware source changed: '+name
bit=R/'hardware/camera_vision_integrated_v14.bit';elf=R/'build/camera_control_console.elf'
with zipfile.ZipFile(R/'hardware/camera_vision_integrated_v14.xsa') as z:
 payloads=[n for n in z.namelist() if n.endswith('.bit')];assert len(payloads)==1
 assert hashlib.sha256(z.read(payloads[0])).hexdigest()==sha(bit),'XSA/bit mismatch'
b=elf.read_bytes();assert b[:6]==b'\x7fELF\x01\x01' and struct.unpack_from('<HH',b,16)==(2,40)
print('ABC_V14_RELEASE_VERIFIED -- integrated bit/XSA/ELF and firmware sources')
