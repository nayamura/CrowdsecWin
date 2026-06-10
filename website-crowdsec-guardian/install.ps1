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

# ============================================================
# Helper: Get file from local folder or download from GitHub
# ============================================================
# Looks for $fileName in the script's directory and subfolders.
# If not found, downloads from the GitHub repo.
# Returns the full path to the file, or $null if both fail.
function Get-FileLocalOrRepo {
    param(
        [string]$FileName,
        [string]$Destination,
        [string]$RepoBase = "https://github.com/nayamura/CrowdsecWin/raw/main"
    )

    # 1) Search locally (script directory + subfolders)
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) { $scriptDir = "." }
    $localFile = Get-ChildItem -Path $scriptDir -Recurse -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($localFile -and (Test-Path $localFile.FullName)) {
        Copy-Item $localFile.FullName $Destination -Force
        Write-Ok "$FileName (local: $($localFile.FullName)) -> $Destination"
        return $true
    }

    # 2) Search in current working directory + subfolders
    $cwdFile = Get-ChildItem -Path "." -Recurse -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cwdFile -and (Test-Path $cwdFile.FullName)) {
        Copy-Item $cwdFile.FullName $Destination -Force
        Write-Ok "$FileName (cwd: $($cwdFile.FullName)) -> $Destination"
        return $true
    }

    # 3) Download from GitHub repo
    $url = "$RepoBase/$FileName"
    try {
        Write-Host "  $FileName not found locally, downloading from GitHub..." -ForegroundColor Gray
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 120
        Write-Ok "$FileName (downloaded) -> $Destination"
        return $true
    } catch {
        Write-Host "  [FAIL] $FileName: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================
# Step 1: Create directories
# ============================================================
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

# ============================================================
# Step 2: Get binaries (local first, then GitHub)
# ============================================================
Write-Step "Getting binaries (local search, then GitHub download)"
$binaries = @(
    @{name="crowdsec.exe";              dest="$InstallDir\crowdsec.exe"},
    @{name="cscli.exe";                 dest="$InstallDir\cscli.exe"},
    @{name="notification-slack.exe";    dest="$InstallDir\plugins\notification-slack.exe"},
    @{name="notification-email.exe";    dest="$InstallDir\plugins\notification-email.exe"},
    @{name="notification-http.exe";     dest="$InstallDir\plugins\notification-http.exe"},
    @{name="notification-sentinel.exe"; dest="$InstallDir\plugins\notification-sentinel.exe"},
    @{name="notification-file.exe";     dest="$InstallDir\plugins\notification-file.exe"},
    @{name="notification-splunk.exe";   dest="$InstallDir\plugins\notification-splunk.exe"}
)

$failedBinaries = @()
foreach ($bin in $binaries) {
    $ok = Get-FileLocalOrRepo -FileName $bin.name -Destination $bin.dest
    if (-not $ok) {
        $failedBinaries += $bin.name
    }
}
if ($failedBinaries.Count -gt 0) {
    Write-Warn "Failed to get: $($failedBinaries -join ', ')"
}

# ============================================================
# Step 3: Add to PATH
# ============================================================
Write-Step "Adding to system PATH"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$InstallDir", "Machine")
    Write-Ok "$InstallDir added to PATH"
} else {
    Write-Ok "Already in PATH"
}

# ============================================================
# Step 4: Install NSSM (local zip first, then GitHub, then choco)
# ============================================================
Write-Step "Installing NSSM (service manager)"
$nssmPath = "$InstallDir\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    $nssmInstalled = $false

    # 4a) Look for nssm.exe directly in local folders
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) { $scriptDir = "." }
    $localNssm = Get-ChildItem -Path $scriptDir -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
    if (-not $localNssm) {
        $localNssm = Get-ChildItem -Path "." -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
    }
    if ($localNssm -and (Test-Path $localNssm.FullName)) {
        Copy-Item $localNssm.FullName $nssmPath -Force
        Write-Ok "NSSM (local: $($localNssm.FullName)) -> $nssmPath"
        $nssmInstalled = $true
    }

    # 4b) Look for nssm-2.24.zip locally, extract it
    if (-not $nssmInstalled) {
        $localZip = Get-ChildItem -Path $scriptDir -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $localZip) {
            $localZip = Get-ChildItem -Path "." -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($localZip -and (Test-Path $localZip.FullName)) {
            try {
                Expand-Archive -Path $localZip.FullName -DestinationPath "$env:TEMP\nssm" -Force
                $nssmExe = Get-ChildItem "$env:TEMP\nssm" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
                if ($nssmExe) {
                    Copy-Item $nssmExe.FullName $nssmPath
                    Write-Ok "NSSM (extracted from local zip) -> $nssmPath"
                    $nssmInstalled = $true
                }
                Remove-Item "$env:TEMP\nssm" -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn "Failed to extract local NSSM zip: $_"
            }
        }
    }

    # 4c) Download zip from GitHub
    if (-not $nssmInstalled) {
        $nssmZip = "$env:TEMP\nssm.zip"
        try {
            Write-Host "  Downloading NSSM from GitHub..." -ForegroundColor Gray
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://github.com/nayamura/CrowdsecWin/raw/main/nssm-2.24.zip" -OutFile $nssmZip -UseBasicParsing -TimeoutSec 60
            Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm" -Force
            $nssmExe = Get-ChildItem "$env:TEMP\nssm" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
            if ($nssmExe) {
                Copy-Item $nssmExe.FullName $nssmPath
                Write-Ok "NSSM (downloaded + extracted) -> $nssmPath"
                $nssmInstalled = $true
            }
            Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\nssm" -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "NSSM download failed: $_"
        }
    }

    # 4d) Fallback: Chocolatey
    if (-not $nssmInstalled) {
        Write-Warn "Trying Chocolatey as fallback..."
        try {
            choco install -y nssm 2>$null
            Write-Ok "NSSM installed via Chocolatey"
        } catch {
            Write-Warn "All NSSM install methods failed. Install manually: choco install -y nssm"
        }
    }
} else {
    Write-Ok "NSSM already exists at $nssmPath"
}

# ============================================================
# Step 5: Create Windows Service
# ============================================================
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

# ============================================================
# Step 6: Create basic config
# ============================================================
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

# ============================================================
# Step 7: Start service
# ============================================================
Write-Step "Starting CrowdSec Guardian"
try {
    Start-Service CrowdSec -ErrorAction Stop
    Write-Ok "Service started successfully"
} catch {
    Write-Warn "Could not start service: $_"
    Write-Warn "Try: Start-Service CrowdSec"
}

# ============================================================
# Step 8: Verify
# ============================================================
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
