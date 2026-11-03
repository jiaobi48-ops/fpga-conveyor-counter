param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/epoch_hint'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/guarded_adaptive_threshold.v') (Join-Path $root 'fpga/rtl/unsigned_divider32.v') (Join-Path $root 'fpga/sim/threshold_epoch_reference.v') (Join-Path $root 'fpga/sim/tb_epoch_hint.sv') *> compile.log
 if($LASTEXITCODE){throw 'Epoch compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_epoch_hint -s epoch_hint *> elaborate.log
 if($LASTEXITCODE){throw 'Epoch elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') epoch_hint -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS EPOCH_HINT ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Epoch equivalence failed'}
 $terminal=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
 @{test='epoch_hint';status='PASS';cycles=30000;terminal=$terminal}|ConvertTo-Json|Set-Content summary.json -Encoding utf8
 $terminal
}finally{Pop-Location}
