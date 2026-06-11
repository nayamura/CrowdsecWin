# Test-NSSM.ps1 - Script de prueba para verificar NSSM en Windows
# Ejecuta esto en Windows con PowerShell como Administrador para diagnosticar

$NssmPath = "C:\PROGRA~1\CrowdSec\nssm.exe"
$CrowdsecPath = "C:\PROGRA~1\CrowdSec\crowdsec.exe"
$DataDir = "C:\ProgramData\CrowdSec"
$InstallDir = "C:\Program Files\CrowdSec"

Write-Host "=== DIAGNOSTICO NSSM/CrowdSec ===" -ForegroundColor Cyan

# Test 1: Verificar NSSM existe
Write-Host "`n[Test 1] NSSM existe:" -ForegroundColor Yellow
if (Test-Path $NssmPath) {
    Write-Host "  OK: $NssmPath" -ForegroundColor Green
} else {
    Write-Host "  FAIL: No existe" -ForegroundColor Red
}

# Test 2: Verificar crowdsec.exe existe
Write-Host "`n[Test 2] crowdsec.exe existe:" -ForegroundColor Yellow
if (Test-Path $CrowdsecPath) {
    Write-Host "  OK: $CrowdsecPath" -ForegroundColor Green
    $ver = & $CrowdsecPath --version 2>&1
    Write-Host "  Version: $ver" -ForegroundColor Green
} else {
    Write-Host "  FAIL: No existe" -ForegroundColor Red
}

# Test 3: Probar que crowdsec.exe acepta -winsvc
Write-Host "`n[Test 3] Probar crowdsec.exe --help | Select winsvc:" -ForegroundColor Yellow
$help = & $CrowdsecPath --help 2>&1 | Select-String "winsvc"
if ($help) {
    Write-Host "  OK: $help" -ForegroundColor Green
} else {
    Write-Host "  FAIL: No se encontro -winsvc en la ayuda" -ForegroundColor Red
    $allHelp = & $CrowdsecPath --help 2>&1 | Select-Object -First 5
    Write-Host "  Ayuda disponible:" -ForegroundColor Yellow
    $allHelp | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

# Test 4: Intentar instalar el servicio paso a paso
Write-Host "`n[Test 4] Instalar servicio paso a paso:" -ForegroundColor Yellow

# Primero eliminar si existe
$exists = Get-Service CrowdSec -ErrorAction SilentlyContinue
if ($exists) {
    Write-Host "  Eliminando servicio existente..." -ForegroundColor Yellow
    sc.exe stop CrowdSec 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    sc.exe delete CrowdSec 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $exists2 = Get-Service CrowdSec -ErrorAction SilentlyContinue
    if ($exists2) {
        Write-Host "  WARN: No se pudo eliminar" -ForegroundColor Red
    } else {
        Write-Host "  OK: Servicio eliminado" -ForegroundColor Green
    }
}

# Instalar con NSSM
Write-Host "  Instalando servicio con NSSM..." -ForegroundColor Yellow
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $NssmPath
$psi.Arguments = "install CrowdSec `"$CrowdsecPath`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
$p.WaitForExit()
Write-Host "  Exit: $($p.ExitCode)"
if ($out.Trim()) { Write-Host "  stdout: $out" -ForegroundColor DarkGray }
if ($err.Trim()) { Write-Host "  stderr: $err" -ForegroundColor DarkYellow }

# Test 5: Verificar servicio existe
Write-Host "`n[Test 5] Verificar servicio CrowdSec:" -ForegroundColor Yellow
$svc = Get-Service CrowdSec -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "  OK: $($svc.Status) - $($svc.DisplayName)" -ForegroundColor Green
} else {
    Write-Host "  FAIL: No existe" -ForegroundColor Red
}

# Test 6: Intentar iniciar
Write-Host "`n[Test 6] Intentar iniciar servicio:" -ForegroundColor Yellow
try {
    Start-Service CrowdSec -ErrorAction Stop
    Start-Sleep -Seconds 3
    $svc = Get-Service CrowdSec
    Write-Host "  Status: $($svc.Status)" -ForegroundColor $(if($svc.Status -eq "Running"){"Green"}else{"Yellow"})
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
}

# Test 7: Ver logs
Write-Host "`n[Test 7] Logs del servicio:" -ForegroundColor Yellow
$logPath = "$DataDir\log"
if (Test-Path "$logPath\service_stderr.log") {
    $lines = Get-Content "$logPath\service_stderr.log" -Tail 10
    Write-Host "  service_stderr.log (ultimas 10 lineas):" -ForegroundColor Yellow
    $lines | ForEach-Object { Write-Host "    $($_.Substring(0, [Math]::Min($_.Length, 120)))" -ForegroundColor DarkYellow }
} else {
    Write-Host "  No existe service_stderr.log" -ForegroundColor Gray
}

Write-Host "`n=== FIN DEL DIAGNOSTICO ===" -ForegroundColor Cyan
