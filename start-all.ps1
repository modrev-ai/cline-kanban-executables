<#
.SYNOPSIS
    Single-command startup for Kanban and Cline - kills existing processes and starts fresh.
    
.DESCRIPTION
    Terminates all existing Kanban/Cline processes and starts them in development mode.
    Opens each in a separate PowerShell window for visibility.
    
.PARAMETER SkipBuild
    Skip the build step (faster startup).
    
.PARAMETER KanbanOnly
    Start only Kanban.
    
.PARAMETER ClineOnly
    Start only Cline.
    
.PARAMETER NoNewWindow
    Run in current window (sequential, blocks).
    
.EXAMPLE
    .\start-all.ps1
    # Full restart with build, both projects in new windows
    
.EXAMPLE
    .\start-all.ps1 -SkipBuild
    # Fast restart without building
    
.EXAMPLE
    .\start-all.ps1 -KanbanOnly
    # Only Kanban
    
.EXAMPLE
    .\start-all.ps1 -ClineOnly -NoNewWindow
    # Only Cline in current window
#>

param(
    [switch]$SkipBuild,
    [switch]$KanbanOnly,
    [switch]$ClineOnly,
    [switch]$NoNewWindow,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

function Kill-Existing {
    Write-Host "[1/$script:TotalSteps] Terminating existing processes..." -ForegroundColor Yellow
    # Get-Process does not populate CommandLine on Windows; use CimInstance instead.
    Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='bun.exe' OR Name='tsx.exe'" |
        Where-Object { $_.CommandLine -match 'kanban|cline' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
}

function Start-Kanban {
    Write-Host "[$script:Step/$script:TotalSteps] Starting Kanban..." -ForegroundColor Cyan
    $script:Step++
    # Build the command as a string so the flag value is baked in — $using: only works
    # inside Invoke-Command remoting/runspaces, not in Start-Process -Command strings.
    $buildCmd = if (-not $SkipBuild) { "npm run build; " } else { "" }
    $cmd = "cd c:\Workstation\kanban; ${buildCmd}npm run dev"

    if ($NoNewWindow) {
        Invoke-Expression $cmd
    }
    else {
        Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd
    }
}

function Start-Cline {
    Write-Host "[$script:Step/$script:TotalSteps] Starting Cline..." -ForegroundColor Cyan
    $script:Step++
    $cmd = "cd c:\Workstation\cline; "
    if (-not $SkipBuild) { $cmd += "bun run build:sdk; " }
    $cmd += "bun run cli"

    if ($NoNewWindow) {
        Invoke-Expression $cmd
    }
    else {
        Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd
    }
}

# Main — compute step count up front so progress labels are always accurate.
$script:TotalSteps = 2  # kill + done
if (-not $KanbanOnly -and -not $ClineOnly) { $script:TotalSteps += 2 }
elseif ($KanbanOnly -or $ClineOnly)        { $script:TotalSteps += 1 }
$script:Step = 2  # Kill-Existing is always step 1; services start at 2.

Write-Host "=== Kanban & Cline Quick Start ===" -ForegroundColor Green

Kill-Existing

if ($KanbanOnly) {
    Start-Kanban
}
elseif ($ClineOnly) {
    Start-Cline
}
else {
    Start-Kanban
    if (-not $NoNewWindow) { Start-Sleep 3 }
    Start-Cline
}

Write-Host "[$script:TotalSteps/$script:TotalSteps] Done!" -ForegroundColor Green
if (-not $NoNewWindow) {
    Write-Host "Processes running in separate windows." -ForegroundColor Gray
}