param([string]$VivadoBin='E:/JLU/AMD_Vivado/2025.2/Vivado/bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/speed_indices'
$null=New-Item -ItemType Directory -Path $out -Force
$paths=@('fpga/rtl/projection_correlation_speed.v','fpga/sim/tb_speed_indices800.sv')
$inputs=@{}
foreach($p in $paths){$inputs[$p]=(Get-FileHash -LiteralPath (Join-Path $root $p)).Hash.ToLower()}
Push-Location $out
try {
 & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $root $paths[0]) (Join-Path $root $paths[1]) *> compile.log
 if($LASTEXITCODE){throw 'Speed indices compilation failed'}
 & (Join-Path $VivadoBin xelab.bat) tb_speed_indices800 -s indices800 *> elaborate.log
 if($LASTEXITCODE){throw 'Speed indices elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin xsim.bat) indices800 -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS SPEED INDICES800 ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Speed indices scoreboard failed'}
 $terminal=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
 @{status='PASS';width=800;max_shift=32;cases=24;terminal=$terminal;inputs=$inputs}|ConvertTo-Json|Set-Content summary.json -Encoding utf8
 Write-Output $terminal
}finally{Pop-Location}
