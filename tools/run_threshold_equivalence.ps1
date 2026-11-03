param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/threshold_equivalence'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/unsigned_divider32.v') (Join-Path $root 'fpga/rtl/guarded_adaptive_threshold.v') (Join-Path $root 'fpga/sim/reference_guarded_adaptive_threshold.v') (Join-Path $root 'fpga/sim/tb_threshold_equivalence.sv') *> compile.log
 if($LASTEXITCODE){throw 'Equivalence compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_threshold_equivalence -s equiv *> elaborate.log
 if($LASTEXITCODE){throw 'Equivalence elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') equiv -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS THRESHOLD EQUIVALENCE ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Equivalence failed'}
 $log -split "`r?`n"|Where-Object{$_ -match '^PASS '}
}finally{Pop-Location}
