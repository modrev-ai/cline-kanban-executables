<#
.SYNOPSIS
    Single-command startup for Kanban, Cline, AND Tailscale proxy for remote access.
    
.DESCRIPTION
    Terminates all existing Kanban/Cline processes and starts:
    1. Kanban (dev mode: npm run build; npm run dev) on port 3485
    2. Cline (dev mode: bun run build:sdk; bun run cli) 
    3. Header-rewriting proxy (kanban-proxy.js) on port 3484 for Tailscale access
    4. Configures Tailscale serve for remote access via Tailscale IP
    
    Opens each in a separate PowerShell window for visibility.

.PARAMETER SkipBuild
    Skip the build step (faster startup).
    
.PARAMETER KanbanOnly
    Start only Kanban + proxy (no Cline).
    
.PARAMETER ClineOnly
    Start only Cline (no Kanban, no proxy, no Tailscale).
    
.PARAMETER NoTailscale
    Skip Tailscale serve configuration (local proxy only).
    
.PARAMETER NoProxy
    Skip the proxy server (Kanban + Cline only, no remote access).
    
.PARAMETER NoNewWindow
    Run in current window (sequential, blocks).
    
.PARAMETER Help
    Show this help message.

.EXAMPLE
    .\start-all-with-tailscale.ps1
    # Full restart with build, all services in new windows
    
.EXAMPLE
    .\start-all-with-tailscale.ps1 -SkipBuild
    # Fast restart without building
    
.EXAMPLE
    .\start-all-with-tailscale.ps1 -KanbanOnly
    # Only Kanban + proxy + Tailscale
    
.EXAMPLE
    .\start-all-with-tailscale.ps1 -NoTailscale
    # Local only: Kanban + Cline + proxy (no Tailscale serve)
    
.EXAMPLE
    .\start-all-with-tailscale.ps1 -NoProxy
    # Local only: Kanban + Cline (no proxy, no Tailscale)
#>

param(
    [switch]$SkipBuild,
    [switch]$KanbanOnly,
    [switch]$ClineOnly,
    [switch]$NoTailscale,
    [switch]$NoProxy,
    [switch]$NoNewWindow,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

# Configuration
$kanbanPort  = 3485   # Internal Kanban port (127.0.0.1 only)
$proxyPort   = 3484   # Public proxy port (0.0.0.0, accessible via Tailscale)

$tailscalePath = "C:\\Program Files\\Tailscale\\tailscale.exe"
$clineCmdPath  = "$env:APPDATA\\npm\\cline.cmd"
$proxyScriptPath = "C:\\Workstation\\cline-kanban-executables\\prod_executable\\kanban-proxy.js"

$processes = @()

function Cleanup {
    Write-Host "`nShutting down..." -ForegroundColor Yellow
    
    # Stop Tailscale serve
    if (-not $NoTailscale -and (Test-Path $tailscalePath)) {
        Write-Host "Stopping Tailscale serve..." -ForegroundColor Yellow
        & $tailscalePath serve reset 2>&1 | Out-Null
    }
    
    # Kill all child processes
    foreach ($proc in $processes) {
        if ($proc -and -not $proc.HasExited) {
            try { $proc | Stop-Process -Force } catch {}
        }
    }
    
    Write-Host "Done." -ForegroundColor Cyan
}

# Register cleanup on exit
trap { Cleanup; break }

function Kill-Existing {
    Write-Host "[1/$script:TotalSteps] Terminating existing processes..." -ForegroundColor Yellow
    Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='bun.exe' OR Name='tsx.exe'" |
        Where-Object { $_.CommandLine -match 'kanban|cline' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
}

function Start-Kanban {
    Write-Host "[$script:Step/$script:TotalSteps] Starting Kanban on 127.0.0.1:$kanbanPort..." -ForegroundColor Cyan
    $script:Step++
    
    $buildCmd = if (-not $SkipBuild) { "npm run build; " } else { "" }
    $cmd = "cd C:\\Workstation\\kanban; ${buildCmd}`$env:KANBAN_RUNTIME_HOST='127.0.0.1'; `$env:KANBAN_RUNTIME_PORT='$kanbanPort'; npm run dev"
    
    if ($NoNewWindow) {
        # Start in background so script can continue to keep-alive loop
        $proc = Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd -PassThru
        $processes += $proc
    } else {
        $proc = Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd -PassThru
        $processes += $proc
    }
}

function Start-Cline {
    Write-Host "[$script:Step/$script:TotalSteps] Starting Cline..." -ForegroundColor Cyan
    $script:Step++
    
    $cmd = "cd C:\\Workstation\\cline; "
    if (-not $SkipBuild) { $cmd += "bun run build:sdk; " }
    $cmd += "bun run cli"
    
    if ($NoNewWindow) {
        # Start in background so script can continue to keep-alive loop
        $proc = Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd -PassThru
        $processes += $proc
    } else {
        $proc = Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd -PassThru
        $processes += $proc
    }
}

function Start-Proxy {
    Write-Host "[$script:Step/$script:TotalSteps] Starting header-rewriting proxy on 0.0.0.0:$proxyPort..." -ForegroundColor Cyan
    $script:Step++
    
    if (-not (Test-Path $proxyScriptPath)) {
        Write-Host "[ERROR] kanban-proxy.js not found at $proxyScriptPath" -ForegroundColor Red
        exit 1
    }
    
    $nodePath = "$env:APPDATA\\npm\\node_modules"
    $env:NODE_PATH = $nodePath
    
    $proxyDir = Split-Path $proxyScriptPath -Parent
    $proc = Start-Process -FilePath "node" -ArgumentList $proxyScriptPath -PassThru -NoNewWindow -WorkingDirectory $proxyDir
    $processes += $proc
    
    # Wait for proxy to start
    Write-Host "Waiting for proxy to start..." -ForegroundColor Yellow
    $proxyStarted = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $listening = netstat -an | findstr ":$proxyPort"
        if ($listening) {
            $proxyStarted = $true
            break
        }
        Write-Host "." -NoNewline
    }
    
    if (-not $proxyStarted) {
        Write-Host "`n[ERROR] Proxy failed to start on port $proxyPort." -ForegroundColor Red
        Cleanup
        exit 1
    }
    
    Write-Host "`n[OK] Proxy is listening on 0.0.0.0:$proxyPort" -ForegroundColor Green
}

function Start-Tailscale {
    Write-Host "[$script:Step/$script:TotalSteps] Configuring Tailscale serve for port $proxyPort..." -ForegroundColor Cyan
    $script:Step++
    
    if (-not (Test-Path $tailscalePath)) {
        Write-Host "[WARNING] Tailscale not found at $tailscalePath" -ForegroundColor Yellow
        return ""
    }
    
    $statusArray = & $tailscalePath status 2>&1
    $statusString = $statusArray -join "`n"
    
    if ($statusString -match "Logged out") {
        Write-Host "[WARNING] Tailscale is logged out. Skipping Tailscale serve." -ForegroundColor Yellow
        return ""
    }
    
    # Extract Tailscale IP
    $tailscaleIp = ""
    foreach ($line in $statusArray) {
        if ($line -match "^(100\\.\\d+\\.\\d+\\.\\d+)") {
            $tailscaleIp = $matches[1]
            break
        }
    }
    
    $serveResult = & $tailscalePath serve --bg --yes localhost:$proxyPort 2>&1
    if ($serveResult) { Write-Host $serveResult }
    
    $serveStatus = & $tailscalePath serve status --json 2>&1
    if ($serveStatus -match "Serve is not enabled" -or $serveStatus -match "not enabled") {
        Write-Host ""
        Write-Host "[WARNING] Tailscale Serve is not enabled on your tailnet." -ForegroundColor Yellow
        Write-Host "The server is still accessible via your Tailscale IP directly." -ForegroundColor Yellow
        Write-Host "To enable Serve, visit:" -ForegroundColor Yellow
        Write-Host "  https://login.tailscale.com/f/serve?node=n6Ds2UyBTa11CNTRL" -ForegroundColor Yellow
    }
    
    # Return Tailscale IP for display
    return $tailscaleIp
}

function Wait-For-Kanban {
    Write-Host "Waiting for Kanban server to start on 127.0.0.1:$kanbanPort..." -ForegroundColor Yellow
    $kanbanStarted = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        $portCheck = Get-NetTCPConnection -LocalPort $kanbanPort -ErrorAction SilentlyContinue
        if ($portCheck) {
            $kanbanStarted = $true
            break
        }
        if (-not $kanbanStarted) {
            $netstatCheck = netstat -an 2>$null | Select-String ":$kanbanPort.*LISTENING"
            if ($netstatCheck) {
                $kanbanStarted = $true
                break
            }
        }
        Write-Host "." -NoNewline
    }
    
    if (-not $kanbanStarted) {
        Write-Host "`n[ERROR] Kanban server failed to start on port $kanbanPort." -ForegroundColor Red
        Cleanup
        exit 1
    }
    
    Write-Host "`n[OK] Kanban server is listening on 127.0.0.1:$kanbanPort" -ForegroundColor Green
}

# Calculate total steps up front
$script:TotalSteps = 1  # Kill-Existing
if (-not $ClineOnly) { $script:TotalSteps++ }  # Start-Kanban
if (-not $ClineOnly -and -not $NoProxy) { $script:TotalSteps++ }  # Start-Proxy
if (-not $ClineOnly -and -not $NoProxy -and -not $NoTailscale) { $script:TotalSteps++ }  # Start-Tailscale
if (-not $KanbanOnly) { $script:TotalSteps++ }  # Start-Cline
if (-not $ClineOnly) { $script:TotalSteps++ }  # Wait-For-Kanban (only if Kanban runs)
$script:Step = 2  # Services start at step 2

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Kanban + Cline + Tailscale Launcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Kill-Existing

$tailscaleIp = ""

if (-not $ClineOnly) {
    Start-Kanban
    Wait-For-Kanban
    
    if (-not $NoProxy) {
        Start-Proxy
        
        if (-not $NoTailscale) {
            $tailscaleIp = Start-Tailscale
        }
    }
}

if (-not $KanbanOnly) {
    Start-Cline
}

# Success display
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  All services started!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

if (-not $ClineOnly) {
    Write-Host "Architecture:" -ForegroundColor White
    Write-Host "  Local Kanban:  http://127.0.0.1:$kanbanPort" -ForegroundColor Gray
    if (-not $NoProxy) {
        Write-Host "  Local Proxy:   http://127.0.0.1:$proxyPort" -ForegroundColor Gray
        if ($tailscaleIp -and -not $NoTailscale) {
            Write-Host "  Phone/Tailscale:" -ForegroundColor Green
            Write-Host "    http://${tailscaleIp}:$proxyPort" -ForegroundColor White
            Write-Host "    http://modrev:$proxyPort" -ForegroundColor White
        }
    }
    Write-Host ""
}

if (-not $KanbanOnly) {
    Write-Host "Cline CLI running in separate window" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Press Ctrl+C to stop all services." -ForegroundColor Cyan

# Keep script running to maintain background processes (proxy, etc.)
try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
}
catch {
    Cleanup
}
