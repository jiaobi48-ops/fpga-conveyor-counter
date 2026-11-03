param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/consensus_math';$null=New-Item -ItemType Directory -Path $out -Force
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/interval_consensus3.v') (Join-Path $root 'fpga/sim/tb_consensus_bounds_math.sv') *> compile.log
 if($LASTEXITCODE){throw 'Consensus math compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_consensus_bounds_math -s math *> elaborate.log
 if($LASTEXITCODE){throw 'Consensus math elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') math -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS CONSENSUS BOUNDS ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Consensus math failed'}
 $line=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n";Write-Output $line
 @(@{status='PASS';test='tb_consensus_bounds_math';terminal=$line})|ConvertTo-Json|Set-Content summary.json -Encoding utf8
}finally{Pop-Location}
