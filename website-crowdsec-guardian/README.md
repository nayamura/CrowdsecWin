# CrowdSec Guardian - Windows Installation Guide

Custom build of CrowdSec for Windows with CAPI pointing to https://186.72.108.182

## Quick Install (Automated)

Run in PowerShell as Administrator:

```powershell
iwr -useb https://raw.githubusercontent.com/nayamura/CrowdsecWin/main/website-crowdsec-guardian/install.ps1 | iex
```

## Manual Install

See [install.ps1](install.ps1) for the full step-by-step process.

## Contents

- `install.ps1` - Automated installer script
- `crowdsec.exe` - Main CrowdSec service binary
- `cscli.exe` - CrowdSec CLI tool
- `notification-*.exe` - Notification plugins
- `config/` - Configuration files
