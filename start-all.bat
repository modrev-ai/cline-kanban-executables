@echo off
REM ============================================================
REM Kanban & Cline Quick Start Script (Batch/CMD)
REM ============================================================
REM Usage:
REM   start-all.bat                    # Full restart with build
REM   start-all.bat --skip-build       # Fast restart without build
REM   start-all.bat --kanban-only      # Kanban only
REM   start-all.bat --cline-only       # Cline only
REM   start-all.bat --help             # Show help
REM ============================================================

setlocal enabledelayedexpansion

REM Default options
set SKIP_BUILD=false
set KANBAN_ONLY=false
set CLINE_ONLY=false
set SHOW_HELP=false

REM Parse arguments
for %%a in (%*) do (
    if "%%a"=="--skip-build" set SKIP_BUILD=true
    if "%%a"=="--kanban-only" set KANBAN_ONLY=true
    if "%%a"=="--cline-only" set CLINE_ONLY=true
    if "%%a"=="--help" set SHOW_HELP=true
    if "%%a"=="-h" set SHOW_HELP=true
)

if "%SHOW_HELP%"=="true" (
    echo.
    echo Kanban ^& Cline Quick Start
    echo ===========================
    echo.
    echo Usage: start-all.bat [options]
    echo.
    echo Options:
    echo   --skip-build     Skip build step (faster restart)
    echo   --kanban-only    Start only Kanban
    echo   --cline-only     Start only Cline
    echo   --help, -h       Show this help
    echo.
    echo Examples:
    echo   start-all.bat
    echo   start-all.bat --skip-build
    echo   start-all.bat --kanban-only
    echo   start-all.bat --cline-only --skip-build
    echo.
    exit /b 0
)

echo ============================================================
echo Kanban ^& Cline Process Manager
echo ============================================================

REM Function to kill processes
call :kill_processes

if "%CLINE_ONLY%"=="true" (
    echo.
    echo [2/3] Starting Cline only...
    goto :start_cline
)

if "%KANBAN_ONLY%"=="true" (
    echo.
    echo [2/3] Starting Kanban only...
    goto :start_kanban
)

REM Start both
echo.
echo [2/3] Starting Kanban...
call :start_kanban

echo.
echo [3/3] Starting Cline...
timeout /t 3 /nobreak >nul
call :start_cline

echo.
echo ============================================================
echo Done! Processes running in separate windows.
echo ============================================================
exit /b 0

:kill_processes
echo [1/3] Terminating existing processes...

REM Kill Kanban processes (node, tsx)
if "%CLINE_ONLY%"=="false" (
    taskkill /F /FI "IMAGENAME eq node.exe" /FI "WINDOWTITLE eq *kanban*" 2>nul
    taskkill /F /FI "IMAGENAME eq tsx.exe" /FI "WINDOWTITLE eq *kanban*" 2>nul
    taskkill /F /IM node.exe /FI "COMMANDLINE eq *kanban*" 2>nul
    taskkill /F /IM tsx.exe /FI "COMMANDLINE eq *kanban*" 2>nul
)

REM Kill Cline processes (bun, node)
if "%KANBAN_ONLY%"=="false" (
    taskkill /F /FI "IMAGENAME eq bun.exe" /FI "WINDOWTITLE eq *cline*" 2>nul
    taskkill /F /FI "IMAGENAME eq node.exe" /FI "WINDOWTITLE eq *cline*" 2>nul
    taskkill /F /IM bun.exe /FI "COMMANDLINE eq *cline*" 2>nul
    taskkill /F /IM node.exe /FI "COMMANDLINE eq *cline*" 2>nul
)

REM Also kill by command line pattern using wmic
wmic process where "CommandLine like '%%kanban%%' or CommandLine like '%%cline%%'" delete 2>nul

timeout /t 2 /nobreak >nul
echo [OK] Processes terminated.
goto :eof

:start_kanban
cd /d c:\Workstation\kanban
if "%SKIP_BUILD%"=="false" (
    echo Building Kanban...
    npm run build
    if errorlevel 1 (
        echo [WARN] Build failed, continuing anyway...
    )
)
start "Kanban Dev" cmd /k "cd /d c:\Workstation\kanban && set NODE_ENV=development && npm run dev"
echo [OK] Kanban started in new window.
goto :eof

:start_cline
cd /d c:\Workstation\cline
if "%SKIP_BUILD%"=="false" (
    echo Building Cline SDK...
    bun run build:sdk
    if errorlevel 1 (
        echo [WARN] Build failed, continuing anyway...
    )
)
start "Cline Dev" cmd /k "cd /d c:\Workstation\cline && bun run cli"
echo [OK] Cline started in new window.
goto :eof