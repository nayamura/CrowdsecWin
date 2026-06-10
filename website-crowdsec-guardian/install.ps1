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
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: Run this script as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "   _____ _____            __"
Write-Host "  / ____/ ____/___  ____ _/ /_"
Write-Host " / /   / / __/ __ \/ __ '/ __/"
Write-Host "/ /___/ /_/ / /_/ / /_/ / /_"
Write-Host "\____/\____/ .___/\__,_/\__/"
Write-Host "         /_/   Guardian Installer"
Write-Host ""
Write-Host "  CAPI URL: $CAPIUrl" -ForegroundColor Yellow
Write-Host "  Install Dir: $InstallDir" -ForegroundColor Yellow
Write-Host "  Data Dir: $DataDir" -ForegroundColor Yellow

# ============================================================
# Helper: Get file from local folder or download from GitHub
# ============================================================
function Get-FileLocalOrRepo {
    param(
        [string]$FileName,
        [string]$Destination,
        [string]$RepoBase = "https://github.com/nayamura/CrowdsecWin/raw/main"
    )

    # Use $PSScriptRoot if available, otherwise fall back to current dir
    $searchRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "." }

    # 1) Search in script directory + subfolders
    try {
        $localFile = Get-ChildItem -Path $searchRoot -Recurse -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($localFile -and (Test-Path $localFile.FullName)) {
            Copy-Item $localFile.FullName $Destination -Force
            Write-Ok "$FileName (local) -> $Destination"
            return $true
        }
    } catch { }

    # 2) Search in current working directory + subfolders
    try {
        $cwdFile = Get-ChildItem -Path "." -Recurse -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cwdFile -and (Test-Path $cwdFile.FullName)) {
            Copy-Item $cwdFile.FullName $Destination -Force
            Write-Ok "$FileName (cwd) -> $Destination"
            return $true
        }
    } catch { }

    # 3) Download from GitHub repo
    $url = "$RepoBase/$FileName"
    try {
        Write-Host "  $FileName not found locally, downloading from GitHub..." -ForegroundColor Gray
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 120
        Write-Ok "$FileName (downloaded) -> $Destination"
        return $true
    } catch {
        Write-Fail "$FileName: $_"
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
# Step 3: Verify critical binaries exist
# ============================================================
Write-Step "Verifying critical binaries"
$criticalOk = $true
if (-not (Test-Path "$InstallDir\crowdsec.exe")) {
    Write-Fail "crowdsec.exe not found! Service will not work."
    $criticalOk = $false
} else {
    Write-Ok "crowdsec.exe found"
}
if (-not (Test-Path "$InstallDir\cscli.exe")) {
    Write-Fail "cscli.exe not found! CLI will not work."
    $criticalOk = $false
} else {
    Write-Ok "cscli.exe found"
}

if (-not $criticalOk) {
    Write-Host ""
    Write-Fail "Critical binaries missing. Copy them to the script folder or ensure internet access."
    Write-Host "  Download manually from: https://github.com/nayamura/CrowdsecWin" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
# Step 4: Add to PATH
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
# Step 5: Install NSSM (local zip first, then GitHub, then choco)
# ============================================================
Write-Step "Installing NSSM (service manager)"
$nssmPath = "$InstallDir\nssm.exe"
if (Test-Path $nssmPath) {
    Write-Ok "NSSM already exists at $nssmPath"
} else {
    $nssmInstalled = $false
    $searchRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "." }

    # 5a) Look for nssm.exe directly in local folders
    try {
        $localNssm = Get-ChildItem -Path $searchRoot -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
        if (-not $localNssm) {
            $localNssm = Get-ChildItem -Path "." -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
        }
        if ($localNssm -and (Test-Path $localNssm.FullName)) {
            Copy-Item $localNssm.FullName $nssmPath -Force
            Write-Ok "NSSM (local) -> $nssmPath"
            $nssmInstalled = $true
        }
    } catch { }

    # 5b) Look for nssm-2.24.zip locally, extract it
    if (-not $nssmInstalled) {
        try {
            $localZip = Get-ChildItem -Path $searchRoot -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $localZip) {
                $localZip = Get-ChildItem -Path "." -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($localZip -and (Test-Path $localZip.FullName)) {
                Expand-Archive -Path $localZip.FullName -DestinationPath "$env:TEMP\nssm" -Force
                $nssmExe = Get-ChildItem "$env:TEMP\nssm" -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
                if ($nssmExe) {
                    Copy-Item $nssmExe.FullName $nssmPath
                    Write-Ok "NSSM (extracted from local zip) -> $nssmPath"
                    $nssmInstalled = $true
                }
                Remove-Item "$env:TEMP\nssm" -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warn "Failed to extract local NSSM zip: $_"
        }
    }

    # 5c) Download zip from GitHub
    if (-not $nssmInstalled) {
        try {
            $nssmZip = "$env:TEMP\nssm.zip"
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

    # 5d) Fallback: Chocolatey
    if (-not $nssmInstalled) {
        Write-Warn "Trying Chocolatey as fallback..."
        try {
            $choco = Get-Command choco -ErrorAction SilentlyContinue
            if ($choco) {
                choco install -y nssm
                Write-Ok "NSSM installed via Chocolatey"
            } else {
                Write-Warn "Chocolatey not installed. Install from https://chocolatey.org"
            }
        } catch {
            Write-Warn "All NSSM install methods failed. Install manually: choco install -y nssm"
        }
    }
}

# ============================================================
# Step 6: Create Windows Service
# ============================================================
Write-Step "Creating CrowdSec Windows Service"
if (Test-Path $nssmPath) {
    if (Test-Path "$InstallDir\crowdsec.exe") {
        & $nssmPath install CrowdSec "$InstallDir\crowdsec.exe" 2>$null
        & $nssmPath set CrowdSec AppDirectory $InstallDir 2>$null
        & $nssmPath set CrowdSec DisplayName "CrowdSec Guardian" 2>$null
        & $nssmPath set CrowdSec Description "CrowdSec Security Engine - CAPI: $CAPIUrl" 2>$null
        & $nssmPath set CrowdSec Start SERVICE_AUTO_START 2>$null
        & $nssmPath set CrowdSec ObjectName LocalSystem 2>$null
        Write-Ok "Service 'CrowdSec Guardian' created"
    } else {
        Write-Warn "crowdsec.exe not found, skipping service creation"
    }
} else {
    Write-Warn "NSSM not available, skipping service creation"
}

# ============================================================
# Step 7: Create basic config
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
# Step 8: Start service
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
# Step 9: Verify
# ============================================================
Write-Step "Verification"
Start-Sleep -Seconds 3
$service = Get-Service CrowdSec -ErrorAction SilentlyContinue
if ($service) {
    Write-Ok "Service status: $($service.Status)"
} else {
    Write-Warn "Service not found"
}

Write-Host ""
Write-Host "========================================"
Write-Host "  CrowdSec Guardian Installation Complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "  Install Dir:  $InstallDir"
Write-Host "  Data Dir:     $DataDir"
Write-Host "  CAPI URL:     $CAPIUrl"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Register agent:     cscli machines add"
Write-Host "  2. Register CAPI:      cscli capi register"
Write-Host "  3. Check status:       cscli machines list"
Write-Host "  4. View alerts:        cscli alerts list"
Write-Host ""
Write-Host "  Service commands:"
Write-Host "    Start:   Start-Service CrowdSec"
Write-Host "    Stop:    Stop-Service CrowdSec"
Write-Host "    Status:  Get-Service CrowdSec"
Write-Host ""
Write-Host "========================================"
Write-Host ""
