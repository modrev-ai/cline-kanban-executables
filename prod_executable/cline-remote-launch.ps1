# Cline Remote Access Launch Script
# This script starts Cline's Kanban web interface accessible over Tailscale network
# Uses a header-rewriting proxy to bypass Host header validation issues

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Cline Remote Access Launcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$kanbanPort = 3485   # Internal Kanban port (127.0.0.1 only)
$proxyPort = 3484    # Public proxy port (0.0.0.0, accessible via Tailscale)

# Check if Tailscale is running and logged in
$tailscalePath = "C:\Program Files\Tailscale\tailscale.exe"
$tailscaleIp = ""

if (Test-Path $tailscalePath) {
    $statusArray = & $tailscalePath status 2>&1
    $statusString = $statusArray -join "`n"

    if ($statusString -match "Logged out") {
        Write-Host "[WARNING] Tailscale is logged out." -ForegroundColor Yellow
        Write-Host "Please run: tailscale login" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Or open the Tailscale desktop app and sign in with your account." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    else {
        # Extract Tailscale IP from the joined string
        foreach ($line in $statusArray) {
            if ($line -match "^(100\.\d+\.\d+\.\d+)") {
                $tailscaleIp = $matches[1]
                break
            }
        }

        if ($tailscaleIp) {
            Write-Host "[OK] Tailscale is connected." -ForegroundColor Green
            Write-Host "Your Tailscale IP: $tailscaleIp" -ForegroundColor Green
            Write-Host ""
        }
        else {
            Write-Host "[WARNING] Could not extract Tailscale IP." -ForegroundColor Yellow
            Write-Host "Tailscale status output:" -ForegroundColor Yellow
            $statusArray | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            Write-Host ""
        }
    }
}
else {
    Write-Host "[WARNING] Tailscale not found at expected path." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting Cline Kanban on internal port $kanbanPort..." -ForegroundColor Cyan
Write-Host "Proxy will listen on public port $proxyPort..." -ForegroundColor Cyan
Write-Host ""

# Use full path to npm's cline.cmd to avoid directory shadow from c:\Workstation\cline
$clineCmdPath = "$env:APPDATA\npm\cline.cmd"

if (-not (Test-Path $clineCmdPath)) {
    Write-Host "[ERROR] cline.cmd not found at $clineCmdPath" -ForegroundColor Red
    Write-Host "Install it with: npm install -g cline" -ForegroundColor Red
    exit 1
}

# Check for kanban-proxy.js
$proxyScriptPath = "C:\\Workstation\\cline\\kanban-proxy.js"
if (-not (Test-Path $proxyScriptPath)) {
    Write-Host "[ERROR] kanban-proxy.js not found at $proxyScriptPath" -ForegroundColor Red
    Write-Host "Please ensure the proxy script exists." -ForegroundColor Red
    exit 1
}

# Arrays to track child processes for cleanup
$processes = @()

# Cleanup function
function Cleanup {
    Write-Host ""
    Write-Host "Shutting down..." -ForegroundColor Yellow
    
    # Stop Tailscale serve
    if (Test-Path $tailscalePath) {
        Write-Host "Stopping Tailscale serve..." -ForegroundColor Yellow
        & $tailscalePath serve reset 2>&1 | Out-Null
    }
    
    # Kill all child processes
    foreach ($proc in $processes) {
        if ($proc -and -not $proc.HasExited) {
            try {
                $proc | Stop-Process -Force
            }
            catch {}
        }
    }
    
    Write-Host "Done." -ForegroundColor Cyan
}

# Register cleanup on exit via trap (compatible with all PowerShell versions)
trap {
    Cleanup
    break
}

try {
    # Step 1: Start Kanban on internal port 3485, bound to 127.0.0.1
    Write-Host "[1/3] Starting Cline Kanban on 127.0.0.1:$kanbanPort ..." -ForegroundColor Cyan
    $env:KANBAN_RUNTIME_HOST = "127.0.0.1"
    $env:KANBAN_RUNTIME_PORT = "$kanbanPort"
    
    $kanbanProcess = Start-Process `
        -FilePath $clineCmdPath `
        -ArgumentList "kanban" `
        -PassThru `
        -NoNewWindow `
        -WorkingDirectory "C:\Workstation"
    $processes += $kanbanProcess

    # Wait for Kanban to start listening
    Write-Host "Waiting for Kanban server to start..." -ForegroundColor Yellow
    $kanbanStarted = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        # Check multiple ways: netstat, port listening, and process still alive
        $portCheck = Get-NetTCPConnection -LocalPort $kanbanPort -ErrorAction SilentlyContinue
        if ($portCheck) {
            $kanbanStarted = $true
            break
        }
        # Fallback: check netstat
        if (-not $kanbanStarted) {
            $netstatCheck = netstat -an 2>$null | Select-String ":$kanbanPort.*LISTENING"
            if ($netstatCheck) {
                $kanbanStarted = $true
                break
            }
        }
        # Check if process died
        if ($kanbanProcess.HasExited) {
            break
        }
        Write-Host "." -NoNewline
    }

    if (-not $kanbanStarted) {
        Write-Host ""
        Write-Host "[ERROR] Kanban server failed to start on port $kanbanPort." -ForegroundColor Red
        Cleanup
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Kanban server is listening on 127.0.0.1:$kanbanPort" -ForegroundColor Green

    # Step 2: Start the proxy on port 3484
    Write-Host ""
    Write-Host "[2/3] Starting header-rewriting proxy on 0.0.0.0:$proxyPort ..." -ForegroundColor Cyan
    
    # Set NODE_PATH to include global npm modules for http-proxy
    $nodePath = "$env:APPDATA\npm\node_modules"
    $env:NODE_PATH = $nodePath
    
    $proxyProcess = Start-Process `
        -FilePath "node" `
        -ArgumentList "`"$proxyScriptPath`"" `
        -PassThru `
        -NoNewWindow `
        -WorkingDirectory "C:\Workstation"
    $processes += $proxyProcess

    # Wait for proxy to start listening
    Start-Sleep -Seconds 3
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
        Write-Host ""
        Write-Host "[ERROR] Proxy failed to start on port $proxyPort." -ForegroundColor Red
        Cleanup
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Proxy is listening on 0.0.0.0:$proxyPort" -ForegroundColor Green

    # Step 3: Configure Tailscale serve
    Write-Host ""
    Write-Host "[3/3] Configuring Tailscale serve for port $proxyPort..." -ForegroundColor Cyan
    
    if (Test-Path $tailscalePath) {
        $serveResult = & $tailscalePath serve --bg --yes localhost:$proxyPort 2>&1
        $serveResult | ForEach-Object { Write-Host $_ }
        
        # Check if serve failed due to tailnet policy
        $serveStatus = & $tailscalePath serve status --json 2>&1
        if ($serveStatus -match "Serve is not enabled" -or $serveStatus -match "not enabled") {
            Write-Host ""
            Write-Host "[WARNING] Tailscale Serve is not enabled on your tailnet." -ForegroundColor Yellow
            Write-Host "The server is still accessible via your Tailscale IP directly." -ForegroundColor Yellow
            Write-Host "To enable Serve, visit:" -ForegroundColor Yellow
            Write-Host "  https://login.tailscale.com/f/serve?node=n6Ds2UyBTa11CNTRL" -ForegroundColor Yellow
        }
    }

    # Success - display access information
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Cline Kanban is ready!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Architecture:" -ForegroundColor White
    Write-Host "  Phone/Tailscale -> Proxy (0.0.0.0:$proxyPort) -> Kanban (127.0.0.1:$kanbanPort)" -ForegroundColor Gray
    Write-Host ""
    
    if ($tailscaleIp) {
        Write-Host "Access from your phone at:" -ForegroundColor Green
        Write-Host "  http://${tailscaleIp}:$proxyPort" -ForegroundColor White
        Write-Host ""
        Write-Host "Or use your Tailscale hostname:" -ForegroundColor Green
        Write-Host "  http://modrev:$proxyPort" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "Local access (laptop):" -ForegroundColor Green
    Write-Host "  http://127.0.0.1:$proxyPort" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Ctrl+C to stop." -ForegroundColor Cyan

    # Keep the script running and wait for user to press Ctrl+C
    while ($true) {
        Start-Sleep -Seconds 2
        
        # Check if either process has exited unexpectedly
        if ($kanbanProcess.HasExited) {
            Write-Host ""
            Write-Host "[ERROR] Kanban server exited unexpectedly." -ForegroundColor Red
            break
        }
        if ($proxyProcess.HasExited) {
            Write-Host ""
            Write-Host "[ERROR] Proxy exited unexpectedly." -ForegroundColor Red
            break
        }
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Cleanup
}
