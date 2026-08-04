<#
.SYNOPSIS
    Kanban Local Startup - Standalone executable for localhost Kanban development.

.DESCRIPTION
    Terminates existing Kanban processes and starts Kanban in development mode.
    Opens in a separate PowerShell window for visibility.

.PARAMETER SkipBuild
    Skip the build step (faster startup).

.PARAMETER Help
    Show this help message.

.EXAMPLE
    .\kanban-local.ps1
    # Full restart with build

.EXAMPLE
    .\kanban-local.ps1 -SkipBuild
    # Fast restart without building
#>

param(
    [switch]$SkipBuild,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$kanbanPath = "C:\Workstation\kanban"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Kanban Local Startup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Kill existing Kanban processes
Write-Host "[1/3] Terminating existing Kanban processes..." -ForegroundColor Yellow
Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='tsx.exe'" |
    Where-Object { $_.CommandLine -match 'kanban' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 2
Write-Host "[OK] Processes terminated." -ForegroundColor Green

# Build if not skipped
if (-not $SkipBuild) {
    Write-Host "[2/3] Building Kanban..." -ForegroundColor Cyan
    Set-Location $kanbanPath
    npm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Build failed, continuing anyway..." -ForegroundColor Yellow
    }
} else {
    Write-Host "[2/3] Skipping build (-SkipBuild specified)" -ForegroundColor Yellow
}

# Start Kanban
Write-Host "[3/3] Starting Kanban on localhost..." -ForegroundColor Cyan
Set-Location $kanbanPath
$cmd = "`$env:NODE_ENV='development'; npm run dev"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd -PassThru
Write-Host "[OK] Kanban started in new window." -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Kanban running!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Access at: http://localhost:3485 (or configured port)" -ForegroundColor Gray