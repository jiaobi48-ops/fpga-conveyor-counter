param([string]$VivadoBin=$env:VIVADO_BIN)
$ErrorActionPreference='Stop'
if(!$VivadoBin){$VivadoBin='E:/JLU/AMD_Vivado/2025.2/Vivado/bin'}
$VivadoBin=(Resolve-Path -LiteralPath $VivadoBin).Path.TrimEnd('\','/')
$vivadoExe=Join-Path $VivadoBin 'vivado.bat'
if(!(Test-Path -LiteralPath $vivadoExe)){throw 'Set VIVADO_BIN to the installed Vivado bin directory'}
# Each child uses the installed Tcl catalog, avoiding concurrent user-cache writes.
$env:XILINX_LOCAL_USER_DATA='no'
$env:XILINX_TCLAPP_REPO=Join-Path (Split-Path -Parent $VivadoBin) 'data/XilinxTclStore'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
 & $vivadoExe -mode batch -source (Join-Path $PSScriptRoot 'build_fpga.tcl') -log (Join-Path $root 'build_fpga.log')
 if($LASTEXITCODE){throw 'FPGA build failed; inspect build_fpga.log'}
}finally{Pop-Location}
