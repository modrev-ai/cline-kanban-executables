# GitHub Actions CI/CD Workflow Documentation

## Oracle Compute Deployment Pipeline

This document describes the modular GitHub Actions CI/CD pipeline for deploying the Kanban application to Oracle Cloud Infrastructure (OCI) Compute instances.

---

## 🏗️ Architecture Overview

The pipeline is split into **5 reusable workflows** that execute sequentially:

```
┌─────────────────┐
│  validate-yaml  │  ← Validates all YAML files in repo
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌─────────┐ ┌──────────┐
│ build-  │ │ auth-    │
│ package │ │ setup    │
└────┬────┘ └────┬─────┘
     │           │
     └─────┬─────┘
           ▼
    ┌─────────────┐
    │ deploy-to-  │
    │ oci         │
    └──────┬──────┘
           ▼
    ┌─────────────┐
    │ health-     │
    │ check       │
    └─────────────┘
```

### Execution Sequence

| Stage | Workflow | Purpose | Runs On |
|-------|----------|---------|---------|
| 1 | `validate-yaml` | Syntax validation for all YAML files | `ubuntu-latest` |
| 2 | `build-package` | Package application artifacts | `windows-latest` |
| 3 | `auth-setup` | SSH key setup & OCI connectivity test | `windows-latest` |
| 4 | `deploy-to-oci` | Deploy files, install deps, configure services | `windows-latest` |
| 5 | `health-check` | Verify deployment via HTTP & system checks | `windows-latest` |

---

## 📁 Workflow Files

### 1. `.github/workflows/validate-yaml.yml`
**Trigger:** `push`, `pull_request`, `workflow_call`
- Validates all `.yml` and `.yaml` files in the repository
- Uses Python PyYAML for syntax checking
- Fails fast on any invalid YAML

### 2. `.github/workflows/build-package.yml`
**Trigger:** `workflow_call`
**Inputs:**
- `environment` (string, required) - Deployment environment
- `force` (boolean, optional) - Force deployment flag

**Outputs:**
- `artifact-path` - Local staging directory path
- `deploy-files` - JSON array of files to deploy

**Steps:**
1. Checkout repository
2. Verify all required source files exist
3. Package artifacts into `deploy-staging/`:
   - `prod_executable/*` (CLI launchers, kanban-proxy.js)
   - Start scripts (`start-all.bat`, `start-all.ps1`, etc.)
   - `README.md`
4. Upload as `deployment-artifacts` artifact (1-day retention)

### 3. `.github/workflows/auth-setup.yml`
**Trigger:** `workflow_call`
**Inputs:**
- `environment` (string, required)

**Required Secrets:**
- `ORACLE_HOST` - Oracle Compute public IP/hostname
- `ORACLE_USER` - SSH username (typically `opc`)
- `ORACLE_SSH_KEY_B64` - Base64-encoded SSH private key
- `DEPLOY_PATH` - Remote deployment directory path

**Outputs:**
- `ssh-key-path` - Path to decoded SSH key on runner
- `known-hosts-path` - Path to known_hosts file

**Steps:**
1. Decode base64 SSH key, write to `~/.ssh/oracle_key`
2. Set restrictive file permissions (Windows `icacls`)
3. Run `ssh-keyscan` to populate `known_hosts`
4. Test SSH connectivity
5. Create remote deployment directory

### 4. `.github/workflows/deploy-to-oci.yml`
**Trigger:** `workflow_call`
**Inputs:**
- `environment` (string, required)
- `ssh-key-path` (string, required) - From auth-setup output
- `known-hosts-path` (string, required) - From auth-setup output
- `artifact-name` (string, optional, default: `deployment-artifacts`)

**Required Secrets:**
- `ORACLE_HOST`, `ORACLE_USER`, `DEPLOY_PATH`
- `GH_PAT` (optional) - GitHub PAT for private repo access

**Steps:**
1. Download `deployment-artifacts` artifact
2. **Deploy application files** via SCP:
   - `prod_executable/*` → `$DEPLOY_PATH/prod_executable/`
   - Start scripts → `$DEPLOY_PATH/`
   - `README.md` → `$DEPLOY_PATH/`
3. **Install Node.js & dependencies** on Oracle:
   - Create 4GB swap file (OOM prevention)
   - Install Node.js 22.14.0 via binary tarball
   - Install git, configure npm for low memory
   - Install `http-proxy` globally
   - Install latest `cline` from `modrev-ai/cline`
4. **Create & deploy systemd service files:**
   - `kanban-proxy.service` (port 3484)
   - `kanban-server.service` (port 3485)
5. **Configure firewall** (firewalld + iptables fallback)
6. **Enable & start services** with verification
7. **Wait for service stabilization** (10s)

### 5. `.github/workflows/health-check.yml`
**Trigger:** `workflow_call`
**Inputs:**
- `environment` (string, required)
- `ssh-key-path` (string, required)
- `known-hosts-path` (string, required)

**Required Secrets:**
- `ORACLE_HOST`, `ORACLE_USER`, `DEPLOY_PATH`

**Steps:**
1. **Check service status** via `systemctl status`
2. **Verify local port bindings** on Oracle (`ss -tlnp`)
3. **Test local HTTP connectivity** (curl to 127.0.0.1:3484/3485)
4. **Remote HTTP health checks** (5 retries, 10s delay):
   - `http://$ORACLE_HOST:3484` (Kanban Proxy)
   - `http://$ORACLE_HOST:3485` (Kanban Server)
5. **Generate deployment summary** in GitHub Step Summary:
   - Environment, host, deploy path, timestamp
   - Service list with ports
   - Access URLs (Tailscale IP if available)

---

## 🔐 Required GitHub Secrets

Configure these in **Repository Settings → Secrets and variables → Actions**:

| Secret | Description | Example |
|--------|-------------|---------|
| `ORACLE_HOST` | Public IP or hostname of OCI Compute instance | `129.146.xxx.xxx` |
| `ORACLE_USER` | SSH username for Oracle instance | `opc` |
| `ORACLE_SSH_KEY_B64` | Base64-encoded SSH private key (RSA/Ed25519) | `base64 -w0 < ~/.ssh/id_rsa` |
| `DEPLOY_PATH` | Absolute path on Oracle for deployment | `/home/opc/kanban` |
| `GH_PAT` | GitHub Personal Access Token (for private cline repo) | `ghp_xxxxxxxxxxxx` |

### Generating `ORACLE_SSH_KEY_B64`

```bash
# On Linux/macOS
base64 -w0 < ~/.ssh/id_rsa

# On Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.ssh\id_rsa"))
```

---

## 🚀 Triggering Deployment

### Manual Dispatch (Primary)
```bash
# Via GitHub CLI
gh workflow run deploy-oracle.yml -f environment=production

# Or via GitHub UI: Actions → Deploy to Oracle Compute → Run workflow
```

### Inputs
| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | `production` | Target environment |
| `force` | boolean | `false` | Force deployment even if no changes |

---

## 🔄 Data Flow Between Workflows

```
build-package (outputs)
  ├─ artifact-path ──────────────────┐
  └─ deploy-files ───────────────────┤
                                     ▼
auth-setup (outputs)          deploy-to-oci (inputs)
  ├─ ssh-key-path ──────────────────► ssh-key-path
  └─ known-hosts-path ──────────────► known-hosts-path
                                     │
                                     ▼
                              health-check (inputs)
                                ├─ ssh-key-path
                                └─ known-hosts-path
```

**Artifact passing:** `build-package` uploads `deployment-artifacts` → `deploy-to-oci` downloads it.

---

## 🛠️ Local Development & Testing

### Validate YAML Locally
```bash
# Install PyYAML
pip install pyyaml

# Validate all YAML files
python -c "
import yaml, glob, sys
failed = 0
for f in glob.glob('**/*.yml', recursive=True) + glob.glob('**/*.yaml', recursive=True):
    try:
        yaml.safe_load(open(f))
        print(f'OK: {f}')
    except Exception as e:
        print(f'ERROR: {f}: {e}')
        failed = 1
sys.exit(failed)
"
```

### Test SSH Connectivity
```bash
# Decode key locally for testing
echo "$ORACLE_SSH_KEY_B64" | base64 -d > /tmp/test_key
chmod 600 /tmp/test_key
ssh -i /tmp/test_key -o StrictHostKeyChecking=no opc@$ORACLE_HOST "echo 'Connected'"
```

---

## 📋 Deployment Checklist

Before running the pipeline, verify:

- [ ] All GitHub Secrets configured correctly
- [ ] Oracle Compute instance is running and accessible
- [ ] SSH key pair generated and public key added to `~/.ssh/authorized_keys` on Oracle
- [ ] Security lists/NSG allow inbound ports 22, 3484, 3485
- [ ] Tailscale installed on Oracle (optional, for private access)
- [ ] `GH_PAT` has `repo` scope if `modrev-ai/cline` is private

---

## 🐛 Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| SSH key decode fails | Whitespace/newlines in secret | Ensure secret is single-line base64 |
| `ssh-keyscan` timeout | Network/firewall blocking port 22 | Check OCI security lists |
| Node.js install OOM | Free tier 1GB RAM | Swap file creation (4GB) handles this |
| systemd service not found | Line ending issues | Scripts use Unix LF, deployed via SCP |
| Health check fails | Services not ready | 5 retries × 10s = 50s max wait |

### Debug Commands (Run on Oracle)
```bash
# Check service logs
journalctl -u kanban-proxy -f
journalctl -u kanban-server -f

# Check ports
ss -tlnp | grep -E "3484|3485"

# Check processes
ps aux | grep -E "kanban|cline|node"

# Test locally
curl -v http://127.0.0.1:3484
curl -v http://127.0.0.1:3485
```

---

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-08-04 | Modularized into 5 reusable workflows; added WORKFLOW.md |
| 1.0.0 | 2026-07-XX | Initial monolithic deploy-oracle.yml |

---

## 🔗 Related Files

- `.github/workflows/deploy-oracle.yml` - Main orchestration workflow
- `.github/workflows/validate-yaml.yml` - YAML validation
- `.github/workflows/build-package.yml` - Artifact packaging
- `.github/workflows/auth-setup.yml` - SSH/OCI authentication
- `.github/workflows/deploy-to-oci.yml` - Core deployment logic
- `.github/workflows/health-check.yml` - Post-deployment verification
- `setup-github-secrets.ps1` / `.sh` - Secret configuration helpers