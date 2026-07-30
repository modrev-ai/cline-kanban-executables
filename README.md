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

---

## GitHub Actions Deployment to Oracle Compute

This repository includes a GitHub Actions workflow (`.github/workflows/deploy-oracle.yml`) for deploying to an Oracle Cloud Infrastructure compute instance.

### Prerequisites

1. **GitHub CLI** installed and authenticated (`gh auth login`)
2. **Oracle Compute Instance** with:
   - Public IP accessible via SSH
   - User `opc` with sudo access
   - SSH key configured

### Setup Secrets

Run the setup script to configure GitHub repository secrets:

```powershell
# Windows PowerShell
.\setup-github-secrets.ps1
```

```bash
# Linux/macOS/Git Bash
./setup-github-secrets.sh
```

This configures the following secrets:
- `ORACLE_HOST` - Oracle instance IP (default: 129.159.69.183)
- `ORACLE_USER` - SSH user (default: opc)
- `ORACLE_SSH_KEY` - Private SSH key content
- `DEPLOY_PATH` - Deployment directory (default: /home/opc/cline-kanban)

### Trigger Deployment

**Via GitHub CLI:**
```bash
gh workflow run deploy-oracle.yml --repo modrev-ai/cline-kanban-executables
```

**Via GitHub Web UI:**
1. Go to: https://github.com/modrev-ai/cline-kanban-executables/actions/workflows/deploy-oracle.yml
2. Click "Run workflow"
3. Select environment (production)
4. Click "Run workflow"

### What the Workflow Does

1. **SSH Connection** - Connects to Oracle instance using configured SSH key
2. **Deploy Files** - Copies `prod_executable/`, start scripts, and README
3. **Install Dependencies** - Installs Node.js dependencies and http-proxy globally
4. **Create Systemd Services** - Sets up two services:
   - `kanban-proxy.service` - Header rewriting proxy on port 3484
   - `kanban-server.service` - Cline Kanban server on port 3485
5. **Start Services** - Enables and starts both services
6. **Verify** - Checks service status and port listening

### Access After Deployment

After successful deployment:

- **Kanban Proxy (via Tailscale)**: `http://<tailscale-ip>:3484`
- **Kanban Server (Direct)**: `http://<oracle-ip>:3485`

### Manual Service Management

On the Oracle instance:

```bash
# Check status
sudo systemctl status kanban-proxy kanban-server

# View logs
sudo journalctl -u kanban-proxy -f
sudo journalctl -u kanban-server -f

# Restart services
sudo systemctl restart kanban-proxy kanban-server

# Stop services
sudo systemctl stop kanban-proxy kanban-server
```

### Oracle Instance Requirements

- **OS**: Oracle Linux 8/9 or Ubuntu 20.04/22.04
- **Node.js**: 18+ installed
- **npm**: Available globally
- **Tailscale**: Installed and authenticated (for remote access)
- **Firewall**: Ports 3484, 3485 open (or use Tailscale)

Install Tailscale on Oracle:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```