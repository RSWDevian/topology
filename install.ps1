# ─────────────────────────────────────────────────────────────
#  MeshLink — WireGuard Installer (Windows)
#  Run in PowerShell as Administrator:
#
#    Host   → .\install.ps1 -Role host
#    Member → .\install.ps1 -Role member
#
#  Requirements: PowerShell 5.1+ (already on Windows 10/11)
# ─────────────────────────────────────────────────────────────

param(
    [ValidateSet("host", "member")]
    [string]$Role = "member",
    [int]$WGPort = 51820,
    [int]$BackendPort = 3000
)

# ── Colour helpers ───────────────────────────────────────────
function Log    { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn   { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Err    { param($msg) Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }
function Section{ param($msg) Write-Host "`n── $msg ──" -ForegroundColor Cyan }

# ── Must be Administrator ────────────────────────────────────
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Run PowerShell as Administrator and try again."
}

Write-Host ""
Write-Host "  MESHLINK — WireGuard Setup (Windows)" -ForegroundColor White
Write-Host "  Role   : $Role" -ForegroundColor White
Write-Host "  WG Port: $WGPort" -ForegroundColor White
Write-Host ""

# ── 1. Install WireGuard ─────────────────────────────────────
Section "1. Installing WireGuard"

# Check if winget is available (Windows 10 1709+ / Windows 11)
$useWinget = Get-Command winget -ErrorAction SilentlyContinue

if ($useWinget) {
    Write-Host "  Installing via winget..."
    winget install --id WireGuard.WireGuard --silent --accept-package-agreements --accept-source-agreements
    Log "WireGuard installed via winget"
} else {
    # Fallback: direct download from wireguard.com
    Warn "winget not found — downloading WireGuard installer directly..."
    $installerUrl  = "https://download.wireguard.com/windows-client/wireguard-installer.exe"
    $installerPath = "$env:TEMP\wireguard-installer.exe"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
    Remove-Item $installerPath -Force
    Log "WireGuard installed via direct download"
}

# Locate wg.exe and wireguard.exe
$wgPaths = @(
    "C:\Program Files\WireGuard\wg.exe",
    "C:\Program Files (x86)\WireGuard\wg.exe"
)
$wgExe = $wgPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $wgExe) {
    Err "wg.exe not found after install. Check C:\Program Files\WireGuard\"
}
Log "wg.exe found at: $wgExe"

# Add WireGuard to PATH for this session and permanently
$wgDir = Split-Path $wgExe
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$wgDir*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$wgDir", "Machine")
    $env:PATH = "$env:PATH;$wgDir"
    Log "WireGuard added to system PATH"
} else {
    Log "WireGuard already in PATH"
}

# ── 2. Create WireGuard config directory ─────────────────────
Section "2. Creating WireGuard config directory"

$WGConfigDir = "C:\ProgramData\WireGuard"
if (-not (Test-Path $WGConfigDir)) {
    New-Item -ItemType Directory -Path $WGConfigDir -Force | Out-Null
}
Log "Config directory ready: $WGConfigDir"

# ── 3. Configure Windows Firewall ────────────────────────────
Section "3. Configuring Windows Firewall"

# Remove old rules if they exist (clean slate)
Remove-NetFirewallRule -DisplayName "MeshLink WireGuard*" -ErrorAction SilentlyContinue

# WireGuard UDP inbound
New-NetFirewallRule `
    -DisplayName "MeshLink WireGuard UDP In" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort $WGPort `
    -Action Allow `
    -Profile Any | Out-Null
Log "Firewall: allowed inbound UDP $WGPort (WireGuard)"

# Backend API TCP inbound (host only needs this)
New-NetFirewallRule `
    -DisplayName "MeshLink Backend TCP In" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $BackendPort `
    -Action Allow `
    -Profile Any | Out-Null
Log "Firewall: allowed inbound TCP $BackendPort (MeshLink backend)"

# HTTP/HTTPS for frontend
New-NetFirewallRule `
    -DisplayName "MeshLink HTTP In" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Profile Any | Out-Null

New-NetFirewallRule `
    -DisplayName "MeshLink HTTPS In" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Any | Out-Null
Log "Firewall: allowed inbound TCP 80/443 (HTTP/HTTPS)"

# ── 4. Enable IP routing (needed for mesh traffic) ───────────
Section "4. Enabling IP routing"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "IPEnableRouter" -Value 1 -Type DWord
Log "IP routing enabled (takes effect after reboot)"

# ── 5. Host only — Install Node.js & Docker Desktop ──────────
if ($Role -eq "host") {
    Section "5. Installing Node.js & Docker (host only)"

    # Node.js
    $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCheck) {
        if ($useWinget) {
            winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
            Log "Node.js installed"
        } else {
            $nodeUrl  = "https://nodejs.org/dist/v20.11.0/node-v20.11.0-x64.msi"
            $nodePath = "$env:TEMP\node-installer.msi"
            Invoke-WebRequest -Uri $nodeUrl -OutFile $nodePath -UseBasicParsing
            Start-Process msiexec -ArgumentList "/i `"$nodePath`" /quiet" -Wait
            Remove-Item $nodePath -Force
            Log "Node.js installed via direct download"
        }
    } else {
        Log "Node.js already present: $(node --version)"
    }

    # Docker Desktop
    $dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCheck) {
        Warn "Docker not found."
        if ($useWinget) {
            Write-Host "  Installing Docker Desktop (this may take a few minutes)..."
            winget install --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
            Log "Docker Desktop installed — please start it manually after this script"
        } else {
            Write-Host "  Please install Docker Desktop manually from:" -ForegroundColor Yellow
            Write-Host "  https://www.docker.com/products/docker-desktop/" -ForegroundColor Cyan
        }
    } else {
        Log "Docker already present: $(docker --version)"
    }
}

# ── 6. Create wg-reload helper script (PowerShell) ───────────
Section "6. Creating WireGuard reload helper"

$reloadScript = @'
# wg-reload.ps1 — hot reload WireGuard config
# Usage: .\wg-reload.ps1 [interface_name]
param([string]$Iface = "wg0")

$configPath = "C:\ProgramData\WireGuard\$Iface.conf"
if (-not (Test-Path $configPath)) {
    Write-Error "Config not found: $configPath"
    exit 1
}

$svc = Get-Service -Name "WireGuardTunnel`$$Iface" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    # Stop and restart to apply new config (WireGuard Windows tunnel service)
    Stop-Service  "WireGuardTunnel`$$Iface" -Force
    Start-Sleep 1
    Start-Service "WireGuardTunnel`$$Iface"
    Write-Host "WireGuard $Iface reloaded"
} else {
    # Install and start as a tunnel service
    & "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice $configPath
    Write-Host "WireGuard $Iface started"
}
'@

$helperPath = "C:\ProgramData\WireGuard\wg-reload.ps1"
$reloadScript | Out-File -FilePath $helperPath -Encoding UTF8 -Force
Log "wg-reload helper saved to: $helperPath"

# ── 7. Detect public IP ──────────────────────────────────────
Section "7. Detecting network info"
try {
    $PublicIP = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing).Content.Trim()
} catch {
    $PublicIP = "unknown (check manually)"
}
$LocalIP = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } |
    Select-Object -First 1).IPAddress

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor White
Write-Host "  Installation complete! (Windows)" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor White
Write-Host "  Role       : $Role"        -ForegroundColor White
Write-Host "  Public IP  : $PublicIP"    -ForegroundColor White
Write-Host "  Local IP   : $LocalIP"     -ForegroundColor White
Write-Host "  WG Port    : $WGPort/UDP"  -ForegroundColor White
Write-Host "  Config dir : $WGConfigDir" -ForegroundColor White
Write-Host ""

if ($Role -eq "host") {
    Write-Host "  Next steps (Host):" -ForegroundColor Yellow
    Write-Host "  1. Forward UDP $WGPort on your router → $LocalIP"
    Write-Host "  2. Start Docker Desktop"
    Write-Host "  3. cd topology && docker compose up -d"
    Write-Host "  4. Open http://localhost → Host Setup"
} else {
    Write-Host "  Next steps (Member):" -ForegroundColor Yellow
    Write-Host "  1. Get the frontend URL from your host"
    Write-Host "  2. Open it → Member Setup → fill in host details"
    Write-Host "  3. Click Apply — WireGuard tunnel will start automatically"
}
Write-Host ""
Write-Host "  NOTE: A restart may be required for IP routing to take effect." -ForegroundColor Yellow
Write-Host ""