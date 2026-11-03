"""Portable AMD tool discovery from explicit environment, PATH and install roots."""
from pathlib import Path
import os,shutil

def xsdb_path():
    if os.environ.get('XSDB_EXE'):
        p=Path(os.environ['XSDB_EXE'])
        if p.is_file():return p
        raise FileNotFoundError('XSDB_EXE 路径不存在')
    found=shutil.which('xsdb.bat')
    if found:return Path(found)
    for name in ('XILINX_VITIS','XILINX_VIVADO','AMD_ROOT'):
        if os.environ.get(name):
            for tail in ('bin/xsdb.bat','Vivado/bin/xsdb.bat','Vitis/bin/xsdb.bat'):
                p=Path(os.environ[name])/tail
                if p.is_file():return p
    for product in ('Vivado','Vitis'):
        p=Path('E:/JLU/AMD_Vivado/2025.2')/product/'bin/xsdb.bat'
        if p.is_file():return p
    raise FileNotFoundError('设置 XSDB_EXE 为本机 xsdb.bat 的完整路径')
