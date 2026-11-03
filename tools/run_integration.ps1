param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin',[string]$InputHex)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(-not $InputHex){$InputHex=Join-Path $root 'fpga/data/integration_input_rgb.hex'}
$runName='system_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$out=Join-Path $root "rebuild/sim/$runName"
$null=New-Item -ItemType Directory -Force -Path $out
$sources=@((Get-ChildItem -LiteralPath (Join-Path $root 'fpga/rtl') -Filter '*.v').FullName)
$sources+=Join-Path $root 'fpga/sim/tb_vision_system.sv'
$receipt=@{}
foreach($source in @($sources)+@((Join-Path $root 'fpga/rtl/vision_bindings.vh'))){$receipt[$source.Substring($root.Length).TrimStart('\','/').Replace('\','/')]=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower()}
$receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $out 'sources.json') -Encoding utf8
Push-Location $out
try {
 & (Join-Path $VivadoBin 'xvlog.bat') --sv -i (Join-Path $root 'fpga/rtl') @sources *> compile.log
 if($LASTEXITCODE){throw 'Compile failed'}
 & (Join-Path $VivadoBin 'xelab.bat') tb_vision_system --snapshot integrated --debug typical *> elaborate.log
 if($LASTEXITCODE){throw 'Elaboration failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 ('-testplusarg "INPUT='+$InputHex.Replace('\','/')+'"')|Set-Content args.txt -Encoding ascii
 & (Join-Path $VivadoBin 'xsim.bat') integrated -f args.txt -tclbatch run.tcl -log simulate.log *> console.log
 if($LASTEXITCODE){throw 'Simulation failed'}
 $log=Get-Content simulate.log -Raw
 if($log -notmatch '(?m)^PASS INTEGRATION ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw 'Integration scoreboard failed'}
 $log -split "`r?`n"|Where-Object {$_ -match '^PASS INTEGRATION '}
 foreach($relative in $receipt.Keys){if((Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLower() -ne $receipt[$relative]){throw "Simulation input changed: $relative"}}
 @{run=$out;backend='XSim';test='tb_vision_system';status='PASS';input=(Get-FileHash -LiteralPath $InputHex -Algorithm SHA256).Hash.ToLower()}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'rebuild/sim/latest.json') -Encoding utf8
} finally {Pop-Location}
