param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/configuration'
$null=New-Item -ItemType Directory -Force -Path $out
$sources=@((Get-ChildItem -LiteralPath (Join-Path $root 'fpga/rtl') -Filter '*.v').FullName)
$sources+=Join-Path $root 'fpga/sim/tb_configuration_contract.sv'
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv -i (Join-Path $root 'fpga/rtl') @sources *> compile.log
 if($LASTEXITCODE){throw 'Config compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_configuration_contract -s config *> elaborate.log
 if($LASTEXITCODE){throw 'Config elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') config -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS CONFIG ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Config scoreboard failed'}
 $log -split "`r?`n"|Where-Object{$_ -match '^PASS '}
}finally{Pop-Location}
