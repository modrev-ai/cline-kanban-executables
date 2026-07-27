# Kanban & Cline Executables

This folder contains scripts to terminate all running Kanban and Cline processes and restart them in development mode.

## Scripts

### `start-all.bat` (Windows Batch/CMD)
Windows batch script for CMD/PowerShell.

**Usage:**
```cmd
start-all.bat                    # Full restart with build
start-all.bat --skip-build       # Fast restart without build
start-all.bat --kanban-only      # Start only Kanban
start-all.bat --cline-only       # Start only Cline
start-all.bat --help             # Show help
```

**Examples:**
```cmd
# Fast restart both (recommended for development)
start-all.bat --skip-build

# Full rebuild and restart
start-all.bat

# Only restart Kanban
start-all.bat --kanban-only --skip-build

# Only restart Cline
start-all.bat --cline-only --skip-build
```

---

### `start-all.ps1` (PowerShell)
PowerShell script with more robust process detection and colored output.

**Usage:**
```powershell
.\start-all.ps1                  # Full restart with build
.\start-all.ps1 -SkipBuild       # Fast restart without build
.\start-all.ps1 -KanbanOnly      # Start only Kanban
.\start-all.ps1 -ClineOnly       # Start only Cline
.\start-all.ps1 -NoNewWindow     # Run in current window (sequential)
.\start-all.ps1 -Help            # Show help
```

**Examples:**
```powershell
# Fast restart both (recommended for development)
.\start-all.ps1 -SkipBuild

# Full rebuild and restart
.\start-all.ps1

# Only restart Kanban in new window
.\start-all.ps1 -KanbanOnly -SkipBuild

# Only restart Cline in current window
.\start-all.ps1 -ClineOnly -NoNewWindow -SkipBuild
```

---

## What These Scripts Do

1. **Terminate existing processes** - Kills all running `node`, `tsx`, and `bun` processes related to Kanban or Cline
2. **Build (optional)** - Runs `npm run build` for Kanban and `bun run build:sdk` for Cline (skipped with `--skip-build` / `-SkipBuild`)
3. **Start Kanban** - Opens in new window: `cd c:\Workstation\kanban && npm run dev` (with `NODE_ENV=development`)
4. **Start Cline** - Opens in new window: `cd c:\Workstation\cline && bun run cli`

---

## Quick Start

### From CMD:
```cmd
cd c:\Workstation\cline-kanban-executables
start-all.bat --skip-build
```

### From PowerShell:
```powershell
cd c:\Workstation\cline-kanban-executables
.\start-all.ps1 -SkipBuild
```

---

## Process Verification

After running, verify processes are running:

```cmd
tasklist | findstr /i "node bun tsx"
```

Expected output:
- **Kanban**: 4+ `node.exe` processes (dev server, Vite, etc.)
- **Cline**: 2+ `bun.exe` processes (CLI, SDK hub)

---

## Troubleshooting

### "Script not recognized" error
Run from the correct directory:
```cmd
cd c:\Workstation\cline-kanban-executables
start-all.bat --skip-build
```

### PowerShell execution policy error
```powershell
powershell -ExecutionPolicy Bypass -File c:\Workstation\cline-kanban-executables\start-all.ps1 -SkipBuild
```

### Processes not terminating
Run as Administrator, or manually kill:
```cmd
taskkill /F /IM node.exe /FI "COMMANDLINE eq *kanban*"
taskkill /F /IM bun.exe /FI "COMMANDLINE eq *cline*"
```

### Port already in use
The scripts kill existing processes first. If ports are still busy, wait a few seconds and re-run.

---

## Paths Used

| Project | Path | Dev Command |
|---------|------|-------------|
| Kanban | `c:\Workstation\kanban` | `npm run dev` |
| Cline | `c:\Workstation\cline` | `bun run cli` |

Modify the scripts if your paths differ.