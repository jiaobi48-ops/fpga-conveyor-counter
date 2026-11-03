param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/sim/sources800'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/selftest_video_source.v') (Join-Path $root 'fpga/rtl/conveyor_bist_source.v') (Join-Path $root 'fpga/sim/tb_800_sources.sv') *> compile.log
 if($LASTEXITCODE){throw 'Source compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_800_sources -s sources800 *> elaborate.log
 if($LASTEXITCODE){throw 'Source elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') sources800 -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS 800 SOURCES ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Source scoreboard failed'}
 $log -split "`r?`n"|Where-Object{$_ -match '^PASS 800 SOURCES '}
}finally{Pop-Location}
