"""Compile the integrated Standalone firmware against the packaged BSP."""
from pathlib import Path
import os,subprocess,shutil,struct,json,hashlib
R=Path(__file__).resolve().parents[1];S=R/'console';BSP=R/'bsp'
local=R/'tools/.deps/arm-gnu-toolchain-13.3.rel1-mingw-w64-i686-arm-none-eabi/bin/arm-none-eabi-gcc.exe'
cc=os.environ.get('ARM_CC') or shutil.which('arm-none-eabi-gcc.exe') or (str(local) if local.exists() else None)
if not cc:raise SystemExit('Set ARM_CC, or run tools/setup_compiler.ps1')
CC=Path(cc);OUT=R/'rebuild/firmware';OUT.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
flags=['-std=c99','-DSDT','-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-Wall','-Wextra','-Werror','-O2','-g3','-isystem',str(BSP/'include'),'-specs='+str(BSP/'Xilinx.spec')]
objects=[];commands=[]
(OUT/'compile.log').write_text('ARM Standalone compile and BSP link\n',encoding='utf-8')
def run(command):
 command=list(map(str,command));commands.append(command)
 p=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace')
 with (OUT/'compile.log').open('a',encoding='utf-8') as f:f.write(p.stdout+p.stderr)
 if p.returncode:raise SystemExit(p.stdout+p.stderr)
for n in ['vision_control','studio_protocol','studio_snapshot','preview_service','cup_commands','control_dispatch','main','probe_sccb','platform','gpio_bus','sensor','frame_audit','sccb_verify']:
 o=OUT/(n+'.o');objects.append(o);run([CC,*flags,'-c',S/'src'/(n+'.c'),'-o',o])
elf=OUT/'camera_control_console.elf'
run([CC,*flags,*objects,'-o',elf,'-Wl,-T,'+str(S/'src/lscript.ld'),'-L'+str(BSP/'lib'),'-Wl,--start-group','-lxilstandalone','-lxiltimer','-lxil','-lgcc','-lc','-Wl,--end-group'])
data=elf.read_bytes();assert data[:6]==b'\x7fELF\x01\x01' and struct.unpack_from('<HH',data,16)==(2,40)
entry,offset=struct.unpack_from('<II',data,24);size,count=struct.unpack_from('<HH',data,42)
assert size==32 and 0x100000<=entry<0xf00000
segments=[]
for i in range(count):
 kind,fo,va,pa,fs,ms,perm,al=struct.unpack_from('<8I',data,offset+i*size)
 if kind==1:
  assert 0x100000<=pa and pa+ms<=0xf00000 and fs<=ms and fo+fs<=len(data)
  segments.append(dict(address=pa,file_bytes=fs,memory_bytes=ms,permissions=perm))
receipt=dict(status='PASS',verification='ARM compile, BSP link and ELF memory layout',elf_sha256=sha(elf),segments=segments,
 sources={p.name:sha(p) for p in (S/'src').iterdir() if p.is_file()},commands=commands)
(OUT/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
print('PASS ARM Standalone compile/link/ELF:',elf)
