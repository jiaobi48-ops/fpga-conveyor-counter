param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/narrow_indices'
$null=New-Item -ItemType Directory -Force -Path $out
$sources=@((Get-ChildItem -LiteralPath (Join-Path $root 'fpga/rtl') -Filter '*.v').FullName)
$sources+=Join-Path $root 'fpga/sim/tb_parallel_units.sv'
$sources+=Join-Path $root 'fpga/sim/tb_parallel_consensus_local.sv'
$sources+=Join-Path $root 'fpga/sim/tb_merge_tracks.sv'
$sources+=Join-Path $root 'fpga/sim/tb_merge_tracks_registered.sv'
$sources+=Join-Path $root 'fpga/sim/tb_conveyor_extract.sv'
$sources+=Join-Path $root 'fpga/sim/tb_conveyor_extract_pipelined.sv'
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv -i (Join-Path $root 'fpga/rtl') @sources *> compile.log
 if($LASTEXITCODE){throw 'Compile failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 '-testplusarg "OUTPUT=merge.csv"'|Set-Content args.txt -Encoding ascii
 $results=@()
 foreach($test in @('tb_parallel_consensus','tb_parallel_consensus_local','tb_parallel_speed','tb_merge_tracks','tb_merge_tracks_registered','tb_conveyor_extract','tb_conveyor_extract_pipelined')){
  & (Join-Path $VivadoBin 'xelab.bat') $test -s $test *> "$test.elaborate.log"
  if($LASTEXITCODE){throw "Elaboration failed: $test"}
  & (Join-Path $VivadoBin 'xsim.bat') $test -f args.txt -tclbatch run.tcl -log "$test.log" *> "$test.console.log"
  $log=Get-Content "$test.log" -Raw
  if($LASTEXITCODE -or $log -notmatch '(?m)^PASS ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw "Scoreboard failed: $test"}
  $pass=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
  Write-Output $pass;$results+=@{test=$test;status='PASS';terminal=$pass}
 }
 $results|ConvertTo-Json|Set-Content summary.json -Encoding utf8
}finally{Pop-Location}
