"""Run the packaged integration and 800x480 source scoreboards."""
from pathlib import Path
import os,shutil,subprocess
root=Path(__file__).resolve().parents[1]
shell=shutil.which('pwsh.exe') or shutil.which('powershell.exe')
if not shell:raise SystemExit('PowerShell is required')
for script in ('run_integration.ps1','run_source_tests.ps1','run_policy_tests.ps1','run_tracking_tests.ps1','run_valley_tests.ps1','run_consensus_math_tests.ps1','run_lcd_tests.ps1','run_full800_tests.ps1','run_threshold_equivalence.ps1','run_config_tests.ps1','run_noise_tests.ps1','run_epoch_tests.ps1'):
 args=[shell,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(root/'tools'/script)]
 if os.environ.get('VIVADO_BIN'):args+=['-VivadoBin',os.environ['VIVADO_BIN']]
 subprocess.run(args,check=True,cwd=root)
print('PASS ABC integrated RTL scoreboards')
speed_test=root/'tools/run_speed_indices_tests.ps1'
if speed_test.exists():
 args=[shell,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(speed_test)]
 if os.environ.get('VIVADO_BIN'):args+=['-VivadoBin',os.environ['VIVADO_BIN']]
 subprocess.run(args,check=True,cwd=root)
