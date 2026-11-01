"""Recompile board C against the included BSP; no board programming."""
from pathlib import Path
import os, subprocess, sys, json, hashlib
R=Path(__file__).resolve().parents[1]; S=R/'console'; BSP=R/'bsp'
CC=Path(os.environ.get('ARM_CC','D:/vivado/2025.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe'))
OUT=R/'rebuild/firmware';OUT.mkdir(parents=True,exist_ok=True)
flags=['-std=c99','-DSDT','-mcpu=cortex-a9','-mfpu=vfpv3','-mfloat-abi=hard','-Wall','-Wextra','-Werror','-O2','-g3','-isystem',str(BSP/'include'),'-specs='+str(BSP/'Xilinx.spec')]
objects=[]
for n in ['studio_protocol','studio_snapshot','preview_service','cup_commands','control_dispatch','main','probe_sccb','platform','gpio_bus','sensor','frame_audit','sccb_verify']:
 o=OUT/(n+'.o');objects.append(o)
 subprocess.run([str(CC),*flags,'-c',str(S/'src'/(n+'.c')),'-o',str(o)],check=True)
elf=OUT/'camera_control_console.elf'
subprocess.run([str(CC),*flags,*map(str,objects),'-o',str(elf),'-Wl,-T,'+str(S/'src/lscript.ld'),'-L'+str(BSP/'lib'),'-Wl,--start-group','-lxilstandalone','-lxiltimer','-lxil','-lgcc','-lc','-Wl,--end-group'],check=True)
print('ARM rebuild passed; output is separate from the sealed release:',elf)
