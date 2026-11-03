$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot '.deps'
$null=New-Item -ItemType Directory -Force -Path $out
$archive=Join-Path $out 'arm-gnu-13.3.zip'
$url='https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-mingw-w64-i686-arm-none-eabi.zip'
if(-not(Test-Path -LiteralPath $archive)){
 & curl.exe -L --fail --output $archive $url
 if($LASTEXITCODE){throw 'Compiler download failed'}
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower() -ne 'e46fda043c0ce83582bc8db4b3ef85f77f4beb7333344c2f4193c17e1167a095'){throw 'Compiler SHA256 mismatch'}
Expand-Archive -LiteralPath $archive -DestinationPath $out -Force
Write-Output 'ARM compiler ready; run python tools/build_firmware.py'
