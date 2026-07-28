@echo off
REM ==========================================
REM  Kanban + Cline + Tailscale Launcher
REM  Batch wrapper for start-all-with-tailscale.ps1
REM ==========================================

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%start-all-with-tailscale.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] PowerShell script not found: %PS_SCRIPT%
    pause
    exit /b 1
)

echo Starting Kanban + Cline + Tailscale...
echo.

REM Pass all arguments to PowerShell script
powershell.exe -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*

if errorlevel 1 (
    echo.
    echo [ERROR] Script exited with error.
    pause
)