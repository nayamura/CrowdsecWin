# CrowdSec Windows MSI Builder
# Ejecutar en Windows con WiX Toolset v3 instalado
# choco install -y wixtoolset

param(
    [string]$version = "1.0.0"
)

$ErrorActionPreference = "Stop"

# Agregar WiX al PATH
$env:Path += ";C:\Program Files (x86)\WiX Toolset v3.14\bin"

# Preparar directorio de salida
$msiDir = ".\msi"
if (Test-Path $msiDir) { Remove-Item -Force -Recurse -Path $msiDir }
New-Item -ItemType Directory -Path $msiDir -Force | Out-Null

Write-Host "=== Building CrowdSec MSI v$version ===" -ForegroundColor Cyan

# 1) Harvest de patrones
Write-Host "Harvesting patterns..." -ForegroundColor Yellow
heat.exe dir ".\config\patterns" -nologo -cg CrowdsecPatterns -dr PatternsDir -g1 -ag -sf -srd -scom -sreg -out "$msiDir\fragment.wxs"

# 2) Compilar
Write-Host "Compiling..." -ForegroundColor Yellow
candle.exe -arch x64 -dSourceDir=".\config\patterns" -dVersion="$version" -out "$msiDir\" ".\build\windows\installer\WixUI_HK.wxs" ".\build\windows\installer\product.wxs"

# 3) Link
Write-Host "Linking..." -ForegroundColor Yellow
light.exe -b ".\config\patterns" -ext WixUIExtension -ext WixUtilExtension -sacl -spdb -out "crowdsec_$version.msi" "$msiDir\fragment.wixobj" "$msiDir\WixUI_HK.wixobj" "$msiDir\product.wixobj"

Write-Host "=== Done! ===" -ForegroundColor Green
Write-Host "Output: crowdsec_$version.msi"
