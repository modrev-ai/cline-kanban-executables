@echo off
REM ============================================================
REM Kanban Local Startup - Standalone executable for localhost
REM ============================================================
REM Usage:
REM   kanban-local.bat              # Full restart with build
REM   kanban-local.bat --skip-build # Fast restart without build
REM   kanban-local.bat --help       # Show help
REM ============================================================

setlocal enabledelayedexpansion

REM Default options
set SKIP_BUILD=false
set SHOW_HELP=false

REM Parse arguments
for %%a in (%*) do (
    if "%%a"=="--skip-build" set SKIP_BUILD=true
    if "%%a"=="--help" set SHOW_HELP=true
    if "%%a"=="-h" set SHOW_HELP=true
)

if "%SHOW_HELP%"=="true" (
    echo.
    echo Kanban Local Startup
    echo ====================
    echo.
    echo Usage: kanban-local.bat [options]
    echo.
    echo Options:
    echo   --skip-build     Skip build step (faster restart)
    echo   --help, -h       Show this help
    echo.
    echo Examples:
    echo   kanban-local.bat
    echo   kanban-local.bat --skip-build
    echo.
    exit /b 0
)

echo ============================================================
echo Kanban Local Process Manager
echo ============================================================

REM Kill existing Kanban processes
echo [1/3] Terminating existing Kanban processes...
taskkill /F /FI "IMAGENAME eq node.exe" /FI "WINDOWTITLE eq *kanban*" 2>nul
taskkill /F /FI "IMAGENAME eq tsx.exe" /FI "WINDOWTITLE eq *kanban*" 2>nul
taskkill /F /IM node.exe /FI "COMMANDLINE eq *kanban*" 2>nul
taskkill /F /IM tsx.exe /FI "COMMANDLINE eq *kanban*" 2>nul
wmic process where "CommandLine like '%%kanban%%'" delete 2>nul
timeout /t 2 /nobreak >nul
echo [OK] Processes terminated.

REM Build if not skipped
if "%SKIP_BUILD%"=="false" (
    echo.
    echo [2/3] Building Kanban...
    cd /d c:\Workstation\kanban
    npm run build
    if errorlevel 1 (
        echo [WARN] Build failed, continuing anyway...
    )
) else (
    echo.
    echo [2/3] Skipping build (--skip-build specified)
)

REM Start Kanban
echo.
echo [3/3] Starting Kanban on localhost...
cd /d c:\Workstation\kanban
start "Kanban Dev" cmd /k "cd /d c:\Workstation\kanban && set NODE_ENV=development && npm run dev"
echo [OK] Kanban started in new window.

echo.
echo ============================================================
echo Done! Kanban running at http://localhost:3485 (or configured port)
echo ============================================================
exit /b 0