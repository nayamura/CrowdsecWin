# CrowdSec Guardian - Automated Windows Installer
# Run this script in PowerShell as Administrator
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

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

    # Determine script directory
    $searchRoot = "."
    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        $searchRoot = $PSScriptRoot
    } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $searchRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }

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
        Write-Fail "$FileName : $_"
        return $false
    }
}

# ============================================================
# Step 1: Create directories
# ============================================================
Write-Step "Creating directories"
$dirs = @(
    $InstallDir,
    "$DataDir\config",
    "$DataDir\config\notifications",
    "$DataDir\config\console",
    "$DataDir\patterns",
    "$DataDir\hub",
    "$DataDir\data",
    "$InstallDir\plugins"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Ok "Created: $d"
    } else {
        Write-Ok "Exists:  $d"
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

# Helper: Print full error details including inner exceptions
function Show-FullError {
    param([string]$Context, $Exception)
    Write-Fail "$Context"
    $ex = $Exception.Exception
    $level = 0
    while ($ex) {
        Write-Host "  [Error $level] $($ex.GetType().FullName)" -ForegroundColor Red
        Write-Host "  Message: $($ex.Message)" -ForegroundColor Red
        if ($ex.StackTrace) {
            Write-Host "  Stack: $($ex.StackTrace.Split("`n")[0])" -ForegroundColor DarkRed
        }
        $ex = $ex.InnerException
        $level++
    }
    if ($Exception.ScriptStackTrace) {
        Write-Host "  Script Stack: $($Exception.ScriptStackTrace)" -ForegroundColor DarkRed
    }
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

    # Determine search root
    $searchRoot = "."
    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        $searchRoot = $PSScriptRoot
    } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $searchRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }

    # 5a) Look for nssm.exe directly in local folders
    try {
        $localNssmExe = Get-ChildItem -Path $searchRoot -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
        if (-not $localNssmExe) {
            $localNssmExe = Get-ChildItem -Path "." -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
        }
        if ($localNssmExe -and (Test-Path $localNssmExe.FullName)) {
            Copy-Item $localNssmExe.FullName $nssmPath -Force
            Write-Ok "NSSM (local) -> $nssmPath"
            $nssmInstalled = $true
        }
    } catch {
        Show-FullError -Context "5a) Local nssm.exe search failed" -Exception $_
    }

    # 5b) Look for nssm-2.24.zip locally, extract it
    if (-not $nssmInstalled) {
        try {
            $localZipFile = Get-ChildItem -Path $searchRoot -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $localZipFile) {
                $localZipFile = Get-ChildItem -Path "." -Recurse -Filter "nssm-2.24.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($localZipFile -and (Test-Path $localZipFile.FullName)) {
                $tempExtract = "$env:TEMP\nssm_extract"
                if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
                Expand-Archive -Path $localZipFile.FullName -DestinationPath $tempExtract -Force
                $nssmFromZip = Get-ChildItem $tempExtract -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
                if ($nssmFromZip) {
                    Copy-Item $nssmFromZip.FullName $nssmPath -Force
                    Write-Ok "NSSM (extracted from local zip) -> $nssmPath"
                    $nssmInstalled = $true
                } else {
                    Write-Warn "nssm.exe not found inside local zip (no win64 folder)"
                }
                Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "  nssm-2.24.zip not found locally" -ForegroundColor Gray
            }
        } catch {
            Show-FullError -Context "5b) Local NSSM zip extraction failed" -Exception $_
        }
    }

    # 5c) Download zip from GitHub
    if (-not $nssmInstalled) {
        try {
            $nssmZip = "$env:TEMP\nssm.zip"
            Write-Host "  Downloading NSSM from GitHub..." -ForegroundColor Gray
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://github.com/nayamura/CrowdsecWin/raw/main/nssm-2.24.zip" -OutFile $nssmZip -UseBasicParsing -TimeoutSec 120
            $tempExtract = "$env:TEMP\nssm_download"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -Path $nssmZip -DestinationPath $tempExtract -Force
            $nssmFromZip = Get-ChildItem $tempExtract -Recurse -Filter "nssm.exe" | Where-Object { $_.DirectoryName -like "*win64*" } | Select-Object -First 1
            if ($nssmFromZip) {
                Copy-Item $nssmFromZip.FullName $nssmPath -Force
                Write-Ok "NSSM (downloaded + extracted) -> $nssmPath"
                $nssmInstalled = $true
            } else {
                Write-Warn "nssm.exe not found inside downloaded zip (no win64 folder)"
            }
            Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Show-FullError -Context "5c) NSSM download from GitHub failed" -Exception $_
        }
    }

    # 5d) Fallback: Chocolatey
    if (-not $nssmInstalled) {
        Write-Warn "Trying Chocolatey as fallback..."
        try {
            $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
            if ($chocoCmd) {
                choco install -y nssm
                Write-Ok "NSSM installed via Chocolatey"
            } else {
                Write-Warn "Chocolatey not installed. Install from https://chocolatey.org"
            }
        } catch {
            Show-FullError -Context "5d) Chocolatey NSSM install failed" -Exception $_
        }
    }

    # Final check
    if (-not $nssmInstalled) {
        Write-Fail "NSSM could not be installed by any method!"
        Write-Host ""
        Write-Host "  Manual fix: download nssm-2.24.zip from https://nssm.cc/release/nssm-2.24.zip" -ForegroundColor Yellow
        Write-Host "  Extract nssm.exe (win64 folder) to: $nssmPath" -ForegroundColor Yellow
        Write-Host ""
    }
}

# ============================================================
# Step 6: Verify crowdsec.exe can run
# ============================================================
Write-Step "Testing crowdsec.exe"
$crowdsecExe = "$InstallDir\crowdsec.exe"
if (Test-Path $crowdsecExe) {
    try {
        $testOutput = & $crowdsecExe --version 2>&1
        Write-Ok "crowdsec.exe version: $testOutput"
    } catch {
        Write-Warn "crowdsec.exe exists but may not run properly: $_"
        Write-Warn "Check that all dependencies (DLLs) are present."
    }
} else {
    Write-Fail "crowdsec.exe not found at $crowdsecExe"
}

# ============================================================
# Step 7: Create Windows Service via NSSM
# ============================================================
Write-Step "Creating CrowdSec Windows Service"
if (Test-Path $nssmPath) {
    if (Test-Path $crowdsecExe) {
        # Helper: run nssm - pass arguments as array to handle spaces in paths
        function Invoke-Nssm {
            param([string[]]$ArgsArray)
            # Filter out empty/null args to avoid Start-Process errors
            $cleanArgs = $ArgsArray | Where-Object { $_ -and $_.Trim() -ne "" }
            if ($cleanArgs.Count -eq 0) { return }
            try {
                $proc = Start-Process -FilePath $nssmPath -ArgumentList $cleanArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\nssm_out.txt" -RedirectStandardError "$env:TEMP\nssm_err.txt"
                $stdout = Get-Content "$env:TEMP\nssm_out.txt" -ErrorAction SilentlyContinue
                $stderr = Get-Content "$env:TEMP\nssm_err.txt" -ErrorAction SilentlyContinue
                if ($stdout) { Write-Host "    stdout: $($stdout -join ', ')" -ForegroundColor DarkGray }
                if ($stderr) { Write-Host "    stderr: $($stderr -join ', ')" -ForegroundColor DarkYellow }
                if ($proc.ExitCode -ne 0) {
                    Write-Warn "NSSM exit code: $($proc.ExitCode)"
                }
            } catch {
                Write-Warn "NSSM failed: $_"
            }
        }

        # Remove existing service if present
        $existing = Get-Service CrowdSec -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Warn "Removing existing CrowdSec service..."
            Invoke-Nssm @("remove", "CrowdSec", "confirm")
            Start-Sleep -Seconds 2
        }

        # Install service with NSSM - pass each arg separately so spaces in paths are safe
        Write-Host "  Installing service..." -ForegroundColor Gray
        Invoke-Nssm @("install", "CrowdSec", $crowdsecExe)
        Invoke-Nssm @("set", "CrowdSec", "AppDirectory", $InstallDir)
        Invoke-Nssm @("set", "CrowdSec", "DisplayName", "CrowdSec Guardian")
        Invoke-Nssm @("set", "CrowdSec", "Description", "CrowdSec Security Engine")
        Invoke-Nssm @("set", "CrowdSec", "Start", "SERVICE_AUTO_START")
        Invoke-Nssm @("set", "CrowdSec", "ObjectName", "LocalSystem")
        Invoke-Nssm @("set", "CrowdSec", "Type", "SERVICE_WIN32_OWN_PROCESS")

        # Set stdout/stderr log files so we can debug failures
        Invoke-Nssm @("set", "CrowdSec", "AppStdout", "$DataDir\log\service_stdout.log")
        Invoke-Nssm @("set", "CrowdSec", "AppStderr", "$DataDir\log\service_stderr.log")
        Invoke-Nssm @("set", "CrowdSec", "AppStdoutCreationDisposition", "4")
        Invoke-Nssm @("set", "CrowdSec", "AppStderrCreationDisposition", "4")
        Invoke-Nssm @("set", "CrowdSec", "AppRotateFiles", "1")
        Invoke-Nssm @("set", "CrowdSec", "AppRotateBytes", "10485760")

        # Set restart action: restart on failure
        Invoke-Nssm @("set", "CrowdSec", "AppExit", "Default", "Restart")
        Invoke-Nssm @("set", "CrowdSec", "AppRestartDelay", "5000")

        Write-Ok "Service 'CrowdSec Guardian' created"
    } else {
        Write-Warn "crowdsec.exe not found, skipping service creation"
    }
} else {
    Write-Warn "NSSM not available, skipping service creation"
}

# ============================================================
# Step 8: Create basic config
# ============================================================
Write-Step "Creating basic config"

# Ensure log directory exists
if (-not (Test-Path "$DataDir\log")) {
    New-Item -ItemType Directory -Path "$DataDir\log" -Force | Out-Null
}

$configLines = @(
    "# CrowdSec Guardian Configuration",
    "# CAPI: $CAPIUrl",
    "",
    "api:",
    "  server:",
    "    listen_uri: 127.0.0.1:8080",
    "  client:",
    "    credentials_path: $DataDir/config/local_api_credentials.yaml",
    "",
    "common:",
    "  log_dir: $DataDir/log",
    "  log_mode: file",
    "  log_level: info",
    "",
    "db:",
    "  type: sqlite",
    "  path: $DataDir/data/crowdsec.db",
    "",
    "plugin_config:",
    "  notification_dir: $DataDir/config/notifications",
    "  console_dir: $DataDir/config/console",
    "",
    "crowdsec_service:",
    "  enable: true",
    "  acquisition_dir: $DataDir/config"
)

$configLines | Out-File -FilePath "$DataDir\config\config.yaml" -Encoding UTF8
Write-Ok "Config created at $DataDir\config\config.yaml"

# ============================================================
# Step 9: Start service with detailed error reporting
# ============================================================
Write-Step "Starting CrowdSec Guardian"
Start-Sleep -Seconds 2

$serviceStarted = $false

# Try Start-Service first
try {
    Start-Service CrowdSec -ErrorAction Stop
    Start-Sleep -Seconds 3
    $svc = Get-Service CrowdSec
    if ($svc.Status -eq "Running") {
        Write-Ok "Service status: Running"
        $serviceStarted = $true
    } else {
        Write-Warn "Service status: $($svc.Status) - trying NSSM start..."
    }
} catch {
    Write-Warn "Start-Service failed: $_"
}

# Fallback: try NSSM start directly
if (-not $serviceStarted) {
    Write-Host "  Trying NSSM start..." -ForegroundColor Gray
    Invoke-Nssm @("start", "CrowdSec")
    Start-Sleep -Seconds 3
    $svc = Get-Service CrowdSec -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "Service status: Running (via NSSM)"
        $serviceStarted = $true
    }
}

# If still not running, show diagnostics
if (-not $serviceStarted) {
    Write-Fail "Could not start service"
    Write-Host ""

    # Show service stderr log if exists
    $stderrLog = "$DataDir\log\service_stderr.log"
    $stdoutLog = "$DataDir\log\service_stdout.log"
    if (Test-Path $stderrLog) {
        $logContent = Get-Content $stderrLog -Tail 20 -ErrorAction SilentlyContinue
        if ($logContent) {
            Write-Host "  Last lines from service_stderr.log:" -ForegroundColor Yellow
            $logContent | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
            Write-Host ""
        }
    }
    if (Test-Path $stdoutLog) {
        $logContent = Get-Content $stdoutLog -Tail 20 -ErrorAction SilentlyContinue
        if ($logContent) {
            Write-Host "  Last lines from service_stdout.log:" -ForegroundColor Yellow
            $logContent | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host ""
        }
    }

    Write-Host "  Manual troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Test crowdsec.exe manually:" -ForegroundColor White
    Write-Host "     cd '$InstallDir'" -ForegroundColor Cyan
    Write-Host "     .\crowdsec.exe --config '$DataDir\config\config.yaml'" -ForegroundColor Cyan
    Write-Host "  2. Check Windows Event Log:" -ForegroundColor White
    Write-Host "     Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 10" -ForegroundColor Cyan
    Write-Host ""
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
