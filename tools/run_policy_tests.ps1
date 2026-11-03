param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/policy'
$null=New-Item -ItemType Directory -Force -Path $out
$sources=@((Get-ChildItem -LiteralPath (Join-Path $root 'fpga/rtl') -Filter '*.v').FullName)
foreach($name in @('tb_adaptive_units','tb_guard_identity','tb_guard_supervisor','tb_guard_supervisor_pipeline','tb_guard_pixels','tb_guard_pixels_pipeline')){$sources+=Join-Path $root "fpga/sim/$name.sv"}
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv -i (Join-Path $root 'fpga/rtl') @sources *> compile.log
 if($LASTEXITCODE){throw 'Policy compile failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 $results=@()
 foreach($test in @('tb_adaptive_policy','tb_stability','tb_guard_identity','tb_guard_supervisor','tb_guard_supervisor_pipeline','tb_guard_pixels','tb_guard_pixels_pipeline')){
  & (Join-Path $VivadoBin 'xelab.bat') $test -s $test *> "$test.elaborate.log"
  if($LASTEXITCODE){throw "Elaboration failed: $test"}
  & (Join-Path $VivadoBin 'xsim.bat') $test -tclbatch run.tcl -log "$test.log" *> "$test.console.log"
  $log=Get-Content "$test.log" -Raw
  if($LASTEXITCODE -or $log -notmatch '(?m)^PASS ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw "Policy scoreboard failed: $test"}
  $pass=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
  Write-Output $pass;$results+=@{test=$test;status='PASS';terminal=$pass}
 }
 $results|ConvertTo-Json|Set-Content summary.json -Encoding utf8
}finally{Pop-Location}
