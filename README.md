# Kanban & Cline Executables

This folder contains scripts to terminate all running Kanban and Cline processes and restart them in development mode.

## Scripts

### `start-all.bat` / `start-all.ps1` (Windows Batch/PowerShell)
Main scripts to terminate all running Kanban and Cline processes and restart them in development mode.

**Usage (Batch):**
```cmd
start\start-all.bat                    # Full restart with build
start\start-all.bat --skip-build       # Fast restart without build
start\start-all.bat --kanban-only      # Start only Kanban
start\start-all.bat --cline-only       # Start only Cline
start\start-all.bat --help             # Show help
```

**Usage (PowerShell):**
```powershell
.\start\start-all.ps1                  # Full restart with build
.\start\start-all.ps1 -SkipBuild       # Fast restart without build
.\start\start-all.ps1 -KanbanOnly      # Start only Kanban
.\start\start-all.ps1 -ClineOnly       # Start only Cline
.\start\start-all.ps1 -NoNewWindow     # Run in current window (sequential)
.\start\start-all.ps1 -Help            # Show help
```

**Examples:**
```cmd
# Fast restart both (recommended for development)
start\start-all.bat --skip-build

# Full rebuild and restart
start\start-all.bat

# Only restart Kanban
start\start-all.bat --kanban-only --skip-build

# Only restart Cline
start\start-all.bat --cline-only --skip-build
```



### `start-all-with-tailscale.bat` / `start-all-with-tailscale.ps1` (With Tailscale)
Extended scripts that also start the header-rewriting proxy and configure Tailscale for remote access.

**Usage (PowerShell):**
```powershell
.\start\start-all-with-tailscale.ps1           # Full restart with all services
.\start\start-all-with-tailscale.ps1 -SkipBuild # Fast restart
.\start\start-all-with-tailscale.ps1 -KanbanOnly # Kanban + proxy + Tailscale only
.\start\start-all-with-tailscale.ps1 -NoTailscale # Local only (no Tailscale serve)
.\start\start-all-with-tailscale.ps1 -NoProxy    # Kanban + Cline only (no proxy)
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
start\start-all.bat --skip-build
```

### From PowerShell:
```powershell
cd c:\Workstation\cline-kanban-executables
.\start\start-all.ps1 -SkipBuild
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
start\start-all.bat --skip-build
```

### PowerShell execution policy error
```powershell
powershell -ExecutionPolicy Bypass -File c:\Workstation\cline-kanban-executables\start\start-all.ps1 -SkipBuild
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
.\scripts\setup\setup-github-secrets.ps1
```

```bash
# Linux/macOS/Git Bash
./scripts/setup/setup-github-secrets.sh
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

After successful deployment, always use **port 3484** (the proxy):

- **Kanban (Public / Direct)**: `http://<oracle-ip>:3484`
- **Kanban (via Tailscale)**: `http://<tailscale-ip>:3484`

> **Note:** Port **3485** is the internal Kanban server. It binds to `127.0.0.1` only and is
> **not reachable** from the public IP by design — the proxy on 3484 rewrites the `Host`/`Origin`
> headers so Cline's host check accepts the request. Only 3484 is exposed externally.
>
> **Cloud-network ingress (port 3484):** OCI instances sit behind a VCN **Security List / NSG**,
> and by default only port 22 is open — so even when the proxy is healthy the app is unreachable
> from the internet until TCP 3484 ingress is opened. The deploy no longer tries to open this from
> inside the instance (the old approach installed the OCI CLI on the box and used instance-principal
> auth, which required a brittle tenancy-level dynamic-group + policy). Instead, open the ingress
> **once from your own workstation** using your already-configured local OCI CLI — you already have
> the permission in the OCI Console, so your local CLI does too.

#### Enabling ingress from your workstation

Prerequisite: install the OCI CLI and run `oci setup config` once
(<https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm>). Then run the helper
script, pointing it at your instance (it resolves the VNIC → subnet → security list for you):

- **Windows (PowerShell):**
  ```powershell
  ./deploy/enable-oci-ingress.ps1 -InstanceId ocid1.instance.oc1..aaaa
  ```
- **macOS / Linux / WSL (bash):**
  ```bash
  ./deploy/scripts/enable-oci-ingress.sh --instance-id ocid1.instance.oc1..aaaa
  ```

You can target `--subnet-id` / `-SubnetId` or `--security-list-id` / `-SecurityListId` instead, and
override `--port` / `-Port` (default 3484), `--source` / `-Source` (default `0.0.0.0/0`), and
`--profile` / `-Profile`. The script is idempotent — it's a no-op if the port is already open.

To do it manually instead, add an ingress rule to the subnet's Security List (or the instance's NSG):
**Stateless No · Source CIDR `0.0.0.0/0` · TCP · Destination Port `3484`**.

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

---

## Project Structure

```
cline-kanban-executables/
├── .github/workflows/          # GitHub Actions CI/CD workflows
│   ├── deploy-oracle.yml       # Main deployment workflow
│   ├── validate-yaml.yml       # YAML syntax validation
│   ├── build-package.yml       # Build and package artifacts
│   ├── auth-setup.yml          # SSH auth & environment prep
│   ├── deploy-to-oci.yml       # Deploy to Oracle Compute
│   ├── health-check.yml        # Post-deployment verification
│   └── test-dispatch.yml       # Test workflow (development)
├── deploy/                     # Deployment configurations
│   ├── deploy-oracle.yml       # Legacy deployment workflow
│   └── install-oci.ps1         # OCI installation script
├── docs/                       # Documentation
│   ├── ORACLE_DEPLOYMENT.md    # Oracle Cloud deployment guide
│   ├── ORACLE_DEPLOYMENT_COMPLETE.md  # Complete deployment notes
│   ├── WORKFLOW.md             # CI/CD pipeline documentation
│   ├── YAML_VALIDATION.md      # YAML validation details
│   └── ORGANIZATION_PLAN.md    # Project organization plan (moved here)
├── prod_executable/            # Production executables (deployed to Oracle)
│   ├── cline-remote-launch.ps1 # Windows remote launch script
│   ├── cline-remote-launch.sh  # Linux/macOS remote launch script
│   └── kanban-proxy.js         # Header rewriting proxy server
├── scripts/                    # Utility scripts
│   ├── generators/             # Code generators
│   ├── writers/                # File writers
│   └── setup/                  # Setup & configuration scripts
│       ├── setup-github-secrets.ps1  # GitHub secrets setup (Windows)
│       ├── setup-github-secrets.sh   # GitHub secrets setup (Linux/macOS)
│       └── setup.sh            # Oracle Cloud Free Tier setup
├── start/                      # Start scripts for local development
│   ├── start-all.bat           # Windows batch start script
│   ├── start-all.ps1           # PowerShell start script
│   ├── start-all-with-tailscale.bat  # With Tailscale (Windows)
│   └── start-all-with-tailscale.ps1  # With Tailscale (PowerShell)
└── README.md                   # This file
```

---

## Documentation

For detailed documentation, see the [`docs/`](docs/) folder:

| Document | Description |
|----------|-------------|
| [WORKFLOW.md](docs/WORKFLOW.md) | Complete CI/CD pipeline documentation |
| [ORACLE_DEPLOYMENT.md](docs/ORACLE_DEPLOYMENT.md) | Oracle Cloud Free Tier deployment guide |
| [ORACLE_DEPLOYMENT_COMPLETE.md](docs/ORACLE_DEPLOYMENT_COMPLETE.md) | Complete deployment notes |
| [YAML_VALIDATION.md](docs/YAML_VALIDATION.md) | YAML validation details |
| [ORGANIZATION_PLAN.md](docs/ORGANIZATION_PLAN.md) | Project organization plan |

---

## Setup Scripts

The [`scripts/setup/`](scripts/setup/) folder contains utility scripts for initial configuration:

| Script | Platform | Purpose |
|--------|----------|---------|
| `setup-github-secrets.ps1` | Windows PowerShell | Configure GitHub repository secrets for Oracle deployment |
| `setup-github-secrets.sh` | Linux/macOS/Git Bash | Configure GitHub repository secrets for Oracle deployment |
| `setup.sh` | Linux (Ubuntu) | Full Oracle Cloud Free Tier instance setup (Node.js, Tailscale, PM2, etc.) |

**Usage:**
```powershell
# Windows - Configure GitHub secrets
.\scripts\setup\setup-github-secrets.ps1
```

```bash
# Linux/macOS - Configure GitHub secrets
./scripts/setup/setup-github-secrets.sh
```

```bash
# On Oracle instance - Full server setup
./scripts/setup/setup.sh
```
