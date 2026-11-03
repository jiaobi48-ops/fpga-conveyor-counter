param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/full800'
$null=New-Item -ItemType Directory -Force -Path $out
$sources=@((Get-ChildItem -LiteralPath (Join-Path $root 'fpga/rtl') -Filter '*.v').FullName)
$sources+=Join-Path $root 'fpga/sim/tb_full800_bist.sv'
$receipt=@{}
foreach($source in @($sources)+@((Join-Path $root 'fpga/rtl/vision_bindings.vh'))){$receipt[$source.Substring($root.Length).TrimStart('\','/').Replace('\','/')]=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower()}
$receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $out 'sources.json') -Encoding utf8
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv -i (Join-Path $root 'fpga/rtl') @sources *> compile.log
 if($LASTEXITCODE){throw 'Full800 compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_full800_bist -s full800 *> elaborate.log
 if($LASTEXITCODE){throw 'Full800 elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') full800 -tclbatch run.tcl -log simulate.log *> console.log
 $log=Get-Content simulate.log -Raw
 if($LASTEXITCODE -or $log -notmatch '(?m)^PASS FULL800 ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Full800 scoreboard failed'}
 foreach($relative in $receipt.Keys){if((Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLower() -ne $receipt[$relative]){throw "Simulation input changed: $relative"}}
 $log -split "`r?`n"|Where-Object{$_ -match '^PASS FULL800 '}
}finally{Pop-Location}
