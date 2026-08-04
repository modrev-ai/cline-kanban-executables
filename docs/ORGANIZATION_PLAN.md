# Repository Organization Plan

## Current Structure Analysis

The repository currently has a flat structure with many files at the root level:

### Root Files (17 files)
- `deploy-oracle.yml` - GitHub Actions workflow
- `install-oci.ps1` - Oracle Cloud Infrastructure installation script
- `ORACLE_DEPLOYMENT_COMPLETE.md` - Documentation
- `ORACLE_DEPLOYMENT.md` - Documentation
- `package.json` - Node.js package configuration
- `README.md` - Main documentation
- `setup-github-secrets.ps1` - Windows setup script
- `setup-github-secrets.sh` - Linux/macOS setup script
- `setup.sh` - Setup script
- `start-all-with-tailscale.bat` - Windows batch script
- `start-all-with-tailscale.ps1` - Windows PowerShell script
- `start-all.bat` - Windows batch script
- `start-all.ps1` - Windows PowerShell script
- `WORKFLOW.md` - Documentation
- `YAML_VALIDATION.md` - Documentation

### Directories
- `prod_executable/` - Production executables (3 files)
- `scripts/` - Python scripts (16 files - many appear to be code generators)
- `server/` - Node.js server (index.js + db/)
- `server_init/` - Server initialization docs (1 file)

## Proposed Organization

```
cline-kanban-executables/
├── .github/
│   └── workflows/
│       └── deploy-oracle.yml          # GitHub Actions workflow
├── docs/
│   ├── ORACLE_DEPLOYMENT.md
│   ├── ORACLE_DEPLOYMENT_COMPLETE.md
│   ├── WORKFLOW.md
│   ├── YAML_VALIDATION.md
│   └── README.md                      # Move main README here or keep at root
├── scripts/
│   ├── generators/                    # Code generation scripts
│   │   ├── gen_deploy.py
│   │   ├── gen_final.py
│   │   ├── gen_setup.py
│   │   ├── gen_setup_part1.py
│   │   ├── gen_workflow.py
│   │   └── gen_workflow_part1.py
│   ├── writers/                       # File writing scripts
│   │   ├── write_deploy.py
│   │   ├── write_deploy_final.py
│   │   ├── write_deploy_part1.py
│   │   ├── write_final.py
│   │   ├── write_setup.py
│   │   ├── write_setup_final.py
│   │   ├── write_workflow.py
│   │   ├── write_workflow_final.py
│   │   └── write_workflow_part1.py
│   ├── setup-github-secrets.ps1
│   ├── setup-github-secrets.sh
│   └── setup.sh
├── server/
│   ├── index.js
│   └── db/
│       ├── init.js
│       └── tasks.js
├── server_init/
│   └── GITHUB_SERVER_SETUP.md
├── prod_executable/
│   ├── cline-remote-launch.ps1
│   ├── cline-remote-launch.sh
│   └── kanban-proxy.js
├── deploy/
│   ├── install-oci.ps1
│   └── deploy-oracle.yml              # Copy or symlink from .github/workflows
├── start/
│   ├── start-all.bat
│   ├── start-all.ps1
│   ├── start-all-with-tailscale.bat
│   └── start-all-with-tailscale.ps1
├── package.json
└── README.md                          # Keep at root with links to docs/
```

## Key Changes

1. **Move GitHub workflow** to `.github/workflows/` (standard location)
2. **Create `docs/` directory** for all documentation files
3. **Organize `scripts/`** into `generators/` and `writers/` subdirectories
4. **Create `deploy/` directory** for deployment-related files
4. **Create `start/` directory** for startup scripts
5. **Keep `server/`, `prod_executable/`, `server_init/`** as they are well-organized
6. **Keep `package.json` and `README.md`** at root (standard Node.js practice)

## Implementation Steps

1. Create new directory structure
2. Move files to appropriate locations
3. Update any references in scripts/workflows
4. Verify everything still works