# CrowdSec Guardian - Automated Windows Installer
# Run this script in PowerShell as Administrator
# Usage: .\install.ps1

param(
    [string]$InstallDir = "C:\Program Files\CrowdSec",
    [string]$DataDir = "C:\ProgramData\CrowdSec",
    [string]$CAPIUrl = "https://186.72.108.182"
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: Run this script as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host @"
   _____ _____            __
  / ____/ ____/___  ____ _/ /_
 / /   / / __/ __ \/ __ \`/ __/
/ /___/ /_/ / /_/ / /_/ / /_
\____/\____/ .___/\__,_/\__/
         /_/   Guardian Installer
"@ -ForegroundColor Cyan

Write-Host "  CAPI URL: $CAPIUrl" -ForegroundColor Yellow
Write-Host "  Install Dir: $InstallDir" -ForegroundColor Yellow
Write-Host "  Data Dir: $DataDir" -ForegroundColor Yellow

# Step 1: Create directories
Write-Step "Creating directories"
@($InstallDir,
  "$DataDir\config",
  "$DataDir\config\notifications",
  "$DataDir\config\console",
  "$DataDir\patterns",
  "$DataDir\hub",
  "$DataDir\data",
  "$InstallDir\plugins"
) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Ok "Created: $_"
    } else {
        Write-Ok "Exists:  $_"
    }
}

# Step 2: Download binaries from GitHub
Write-Step "Downloading binaries from GitHub"
$repo = "https://github.com/nayamura/CrowdsecWin/raw/main"
$binaries = @(
    @{name="crowdsec.exe";   dest="$InstallDir\crowdsec.exe"},
    @{name="cscli.exe";      dest="$InstallDir\cscli.exe"},
    @{name="notification-slack.exe";    dest="$InstallDir\plugins\notification-slack.exe"},
    @{name="notification-email.exe";    dest="$InstallDir\plugins\notification-email.exe"},
    @{name="notification-http.exe";     dest="$InstallDir\plugins\notification-http.exe"},
    @{name="notification-sentinel.exe"; dest="$InstallDir\plugins\notification-sentinel.exe"},
    @{name="notification-file.exe";     dest="$InstallDir\plugins\notification-file.exe"},
    @{name="notification-splunk.exe";   dest="$InstallDir\plugins\notification-splunk.exe"}
)

foreach ($bin in $binaries) {
    $url = "$repo/$($bin.name)"
    $dest = $bin.dest
    Write-Host "  Downloading $($bin.name)..." -ForegroundColor Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Write-Ok "$($bin.name) -> $dest"
    } catch {
        Write-Host "  [FAIL] $($bin.name): $_" -ForegroundColor Red
    }
}

# Step 3: Add to PATH
Write-Step "Adding to system PATH"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$InstallDir", "Machine")
    Write-Ok "$InstallDir added to PATH"
} else {
    Write-Ok "Already in PATH"
}

# Step 4: Install NSSM (service manager)
Write-Step "Installing NSSM (service manager)"
$nssmPath = "$InstallDir\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    try {
        $nssmZip = "$env:TEMP\nssm.zip"
        Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $nssmZip -UseBasicParsing
        Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm" -Force
        $nssmExe = Get-ChildItem "$env:TEMP\nssm" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
        if ($nssmExe) {
            Copy-Item $nssmExe.FullName $nssmPath
            Write-Ok "NSSM installed to $nssmPath"
        } else {
            Write-Warn "Could not find nssm.exe in zip, trying choco..."
            choco install -y nssm 2>$null
            Write-Ok "NSSM installed via Chocolatey"
        }
        Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\nssm" -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warn "NSSM download failed: $_"
        Write-Warn "Install manually: choco install -y nssm"
    }
}

# Step 5: Create Windows Service
Write-Step "Creating CrowdSec Windows Service"
if (Test-Path $nssmPath) {
    & $nssmPath install CrowdSec "$InstallDir\crowdsec.exe" 2>$null
    & $nssmPath set CrowdSec AppDirectory $InstallDir 2>$null
    & $nssmPath set CrowdSec DisplayName "CrowdSec Guardian" 2>$null
    & $nssmPath set CrowdSec Description "CrowdSec Security Engine - CAPI: $CAPIUrl" 2>$null
    & $nssmPath set CrowdSec Start SERVICE_AUTO_START 2>$null
    & $nssmPath set CrowdSec ObjectName LocalSystem 2>$null
    Write-Ok "Service 'CrowdSec Guardian' created"
} else {
    Write-Warn "NSSM not available, skipping service creation"
}

# Step 6: Create basic config
Write-Step "Creating basic config"
$configContent = @"
# CrowdSec Guardian Configuration
# CAPI: $CAPIUrl

api:
  server:
    listen_uri: 127.0.0.1:8080
  client:
    credentials_path: $DataDir/config/local_api_credentials.yaml

common:
  log_dir: $DataDir/log
  log_mode: file
  log_level: info

db:
  type: sqlite
  path: $DataDir/data/crowdsec.db

plugin_config:
  notification_dir: $DataDir/config/notifications
  console_dir: $DataDir/config/console

crowdsec_service:
  enable: true
  acquisition_dir: $DataDir/config
"@

$configContent | Out-File -FilePath "$DataDir\config\config.yaml" -Encoding UTF8
Write-Ok "Config created at $DataDir\config\config.yaml"

# Step 7: Start service
Write-Step "Starting CrowdSec Guardian"
try {
    Start-Service CrowdSec -ErrorAction Stop
    Write-Ok "Service started successfully"
} catch {
    Write-Warn "Could not start service: $_"
    Write-Warn "Try: Start-Service CrowdSec"
}

# Step 8: Verify
Write-Step "Verification"
Start-Sleep -Seconds 3
$service = Get-Service CrowdSec -ErrorAction SilentlyContinue
if ($service) {
    Write-Ok "Service status: $($service.Status)"
} else {
    Write-Warn "Service not found"
}

Write-Host @"

========================================
  CrowdSec Guardian Installation Complete!
========================================

  Install Dir:  $InstallDir
  Data Dir:     $DataDir
  CAPI URL:     $CAPIUrl

  Next steps:
  1. Register agent:     cscli machines add
  2. Register CAPI:      cscli capi register
  3. Check status:       cscli machines list
  4. View alerts:        cscli alerts list

  Service commands:
    Start:   Start-Service CrowdSec
    Stop:    Stop-Service CrowdSec
    Status:  Get-Service CrowdSec

========================================
"@ -ForegroundColor Green
