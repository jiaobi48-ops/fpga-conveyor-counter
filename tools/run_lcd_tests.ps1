param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/lcd'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try {
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/vision_lcd_bridge.v') (Join-Path $root 'fpga/sim/tb_lcd_overlay.sv') (Join-Path $VivadoBin '../data/verilog/src/glbl.v') *> compile.log
 if($LASTEXITCODE){throw 'LCD compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_lcd_overlay glbl -L unisims_ver -s lcd *> elaborate.log
 if($LASTEXITCODE){throw 'LCD elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') lcd -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS LCD ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'LCD scoreboard failed'}
 $log -split "`r?`n"|Where-Object{$_ -match '^PASS LCD '}
}finally{Pop-Location}
