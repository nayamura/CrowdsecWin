# CrowdSec Windows Custom Build

Custom build of CrowdSec for Windows with CAPI pointing to https://186.72.108.182

## Contents

- crowdsec.exe - Main CrowdSec service binary
- cscli.exe - CrowdSec CLI tool
- notification-*.exe - Notification plugins (slack, email, http, sentinel, file, splunk)
- config/ - Configuration files
- build_msi.ps1 - PowerShell script to generate the MSI installer

## Building the MSI

Run on Windows with WiX Toolset v3 installed:

```powershell
.\build_msi.ps1 -version "1.0.0"
```

## Installation

Download and run the MSI installer, or install manually:

1. Copy binaries to C:\Program Files\CrowdSec\
2. Copy config files to C:\ProgramData\CrowdSec\config\
3. Run `cscli machines add` to register the agent
4. Run `cscli capi register` to register with Central API
5. Start the CrowdSec service
