param([string]$VivadoBin='E:\JLU\AMD_Vivado\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'rebuild/valley_pipeline'
$null=New-Item -ItemType Directory -Force -Path $out
Push-Location $out
try{
 & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $root 'fpga/rtl/projection_valley_counter.v') (Join-Path $root 'fpga/rtl/projection_valley_scanner.v') (Join-Path $root 'fpga/sim/tb_valley_vectors.sv') *> compile.log
 if($LASTEXITCODE){throw 'Valley compile failed'}
 'run all','quit'|Set-Content run.tcl -Encoding ascii
 $results=@()
 foreach($test in @('tb_valley_unit','tb_valley_min','tb_valley_pipe32','tb_valley_pipe5')){
  & (Join-Path $VivadoBin 'xelab.bat') $test -s $test *> "$test.elaborate.log"
  if($LASTEXITCODE){throw 'Valley elaboration failed'}
  $w=if($test -in @('tb_valley_min','tb_valley_pipe5')){5}else{32}
  $vector=(Join-Path $root "fixtures/valley_vectors_w$w.hex").Replace('\','/')
  ('-testplusarg "VECTORS='+$vector+'"')|Set-Content args.txt -Encoding ascii
  & (Join-Path $VivadoBin 'xsim.bat') $test -f args.txt -tclbatch run.tcl -log "$test.log" *> "$test.console.log"
  $log=Get-Content "$test.log" -Raw
  if($LASTEXITCODE -or $log -notmatch '(?m)^PASS ' -or $log -match '\b(Fatal|FAIL|ERROR:)\b'){throw "Valley scoreboard failed: $test"}
  $pass=($log -split "`r?`n"|Where-Object{$_ -match '^PASS '}) -join "`n"
  Write-Output "$test $pass";$results+=@{test=$test;status='PASS';terminal=$pass}
 }
 $results|ConvertTo-Json|Set-Content summary.json -Encoding utf8
}finally{Pop-Location}
