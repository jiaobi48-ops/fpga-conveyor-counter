from pathlib import Path
import hashlib,json,struct,subprocess
R=Path(__file__).resolve().parent
BSP=R.parent/'bsp'
if not (BSP/'include/xparameters.h').is_file():BSP=Path(r'D:/fpga/vitis_workspace/z15_platform/export/z15_platform/sw/standalone_ps7_cortexa9_0')
CC=Path(r'D:/vivado/2025.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
flags=['-std=c99','-DSDT','-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-Wall','-Wextra','-Werror','-O2','-g3','-isystem',str(BSP/'include'),'-specs='+str(BSP/'Xilinx.spec')]
def run(args,name):
    c=list(map(str,args));p=subprocess.run(c,capture_output=True,text=True)
    (R/'validation'/name).write_text(p.stdout+p.stderr,encoding='utf-8')
    if p.returncode:raise RuntimeError(name+': '+p.stdout+p.stderr)
    return c
commands=[];objects=[]
for name in ['studio_protocol','studio_snapshot','preview_service','cup_commands','control_dispatch','main','probe_sccb','platform','gpio_bus','sensor','frame_audit','sccb_verify']:
    o=R/'build'/f'{name}.o';objects.append(o)
    commands.append(run([CC,*flags,'-c',R/'src'/f'{name}.c','-o',o],f'compile_{name}.txt'))
elf=R/'build/camera_control_console.elf'
commands.append(run([CC,*flags,*objects,'-o',elf,'-Wl,-T,'+str(R/'src/lscript.ld'),'-L'+str(BSP/'lib'),'-Wl,--start-group','-lxilstandalone','-lxiltimer','-lxil','-lgcc','-lc','-Wl,--end-group'],'link.txt'))
b=elf.read_bytes();assert b[:6]==b'\x7fELF\x01\x01'
assert struct.unpack_from('<HH',b,16)==(2,40)
entry,off=struct.unpack_from('<II',b,24);size,count=struct.unpack_from('<HH',b,42)
assert size==32 and 0x100000<=entry<0xF00000
segments=[]
for i in range(count):
    kind,fo,va,pa,fs,ms,perm,al=struct.unpack_from('<8I',b,off+i*size)
    if kind!=1:continue
    assert 0x100000<=pa and pa+ms<=0xF00000 and fs<=ms and fo+fs<=len(b)
    segments.append(dict(address=hex(pa),file_bytes=fs,memory_bytes=ms,permissions=perm))
(R/'validation/build_receipt.json').write_text(json.dumps({'status':'PASS ARM compile and BSP link; not executed on board','elf_sha256':sha(elf),'segments':segments,'sources':{p.name:sha(p) for p in (R/'src').iterdir() if p.is_file()},'bsp_xparameters_sha256':sha(BSP/'include/xparameters.h'),'commands':commands},indent=2))
print('CAPTURE_STUDIO_APP_COMPILED -- hardware execution pending')
