param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/noise_pipeline'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/dynamic_noise_policy.v') (Join-Path $root 'fpga/sim/noise_policy_reference.v') (Join-Path $root 'fpga/sim/tb_noise_pipeline.sv') *> compile.log
 if($LASTEXITCODE){throw 'Noise compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_noise_pipeline -s noise_pipeline *> elaborate.log
 if($LASTEXITCODE){throw 'Noise elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') noise_pipeline -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS NOISE_PIPELINE ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Noise equivalence failed'}
 $terminal=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
 @{test='noise_pipeline';status='PASS';cycles=30000;terminal=$terminal}|ConvertTo-Json|Set-Content summary.json -Encoding utf8
 $terminal
}finally{Pop-Location}
