<# 
.SYNOPSIS
    Sets up GitHub repository secrets for Oracle Compute deployment.

.DESCRIPTION
    This script configures the required GitHub secrets for the deploy-oracle.yml workflow.
    Requires GitHub CLI (gh) to be installed and authenticated.

.PARAMETER RepoOwner
    GitHub repository owner (default: modrev-ai)

.PARAMETER RepoName
    GitHub repository name (default: cline-kanban-executables)

.PARAMETER OracleHost
    Oracle Compute instance IP address (default: 129.159.69.183)

.PARAMETER OracleUser
    SSH username for Oracle instance (default: opc)

.PARAMETER SshKeyPath
    Path to SSH private key (default: C:\Users\jshin\.ssh\ssh-key-2026-07-30.key)

.PARAMETER DeployPath
    Deployment path on Oracle instance (default: /home/opc/cline-kanban)

.EXAMPLE
    .\setup-github-secrets.ps1

.EXAMPLE
    .\setup-github-secrets.ps1 -OracleHost "129.159.69.183" -SshKeyPath "C:\path\to\key"
#>

param(
    [string]$RepoOwner = "modrev-ai",
    [string]$RepoName = "cline-kanban-executables",
    [string]$OracleHost = "129.159.69.183",
    [string]$OracleUser = "opc",
    [string]$SshKeyPath = "C:\Users\jshin\.ssh\ssh-key-2026-07-30.key",
    [string]$DeployPath = "/home/opc/cline-kanban"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  GitHub Secrets Setup for Oracle Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository: $RepoOwner/$RepoName" -ForegroundColor White
Write-Host "Oracle Host: $OracleHost" -ForegroundColor White
Write-Host "Oracle User: $OracleUser" -ForegroundColor White
Write-Host "SSH Key: $SshKeyPath" -ForegroundColor White
Write-Host "Deploy Path: $DeployPath" -ForegroundColor White
Write-Host ""

# Check if gh CLI is installed
try {
    $ghVersion = gh --version 2>$null | Select-Object -First 1
    if (-not $ghVersion) {
        throw "GitHub CLI not found"
    }
    Write-Host "✓ GitHub CLI found: $ghVersion" -ForegroundColor Green
}
catch {
    Write-Error "ERROR: GitHub CLI (gh) is not installed or not in PATH."
    Write-Error "Install from: https://cli.github.com/"
    exit 1
}

# Check if authenticated
try {
    gh auth status 2>$null | Out-Null
    Write-Host "✓ Authenticated with GitHub" -ForegroundColor Green
}
catch {
    Write-Error "ERROR: Not authenticated with GitHub CLI."
    Write-Error "Run: gh auth login"
    exit 1
}

# Check SSH key exists
if (-not (Test-Path $SshKeyPath)) {
    Write-Error "ERROR: SSH key not found at $SshKeyPath"
    exit 1
}

# Read SSH private key
$sshKey = Get-Content $SshKeyPath -Raw
Write-Host "✓ SSH key loaded" -ForegroundColor Green

Write-Host ""
Write-Host "Setting up GitHub secrets..." -ForegroundColor Yellow

# Set ORACLE_HOST
Write-Host "Setting ORACLE_HOST..." -NoNewline
gh secret set ORACLE_HOST --body $OracleHost --repo "$RepoOwner/$RepoName" 2>$null
Write-Host " ✓" -ForegroundColor Green

# Set ORACLE_USER
Write-Host "Setting ORACLE_USER..." -NoNewline
gh secret set ORACLE_USER --body $OracleUser --repo "$RepoOwner/$RepoName" 2>$null
Write-Host " ✓" -ForegroundColor Green

# Set ORACLE_SSH_KEY
Write-Host "Setting ORACLE_SSH_KEY..." -NoNewline
gh secret set ORACLE_SSH_KEY --body $sshKey --repo "$RepoOwner/$RepoName" 2>$null
Write-Host " ✓" -ForegroundColor Green

# Set DEPLOY_PATH
Write-Host "Setting DEPLOY_PATH..." -NoNewline
gh secret set DEPLOY_PATH --body $DeployPath --repo "$RepoOwner/$RepoName" 2>$null
Write-Host " ✓" -ForegroundColor Green

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  All secrets configured successfully!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Secrets configured:" -ForegroundColor White
Write-Host "  - ORACLE_HOST: $OracleHost" -ForegroundColor White
Write-Host "  - ORACLE_USER: $OracleUser" -ForegroundColor White
Write-Host "  - ORACLE_SSH_KEY: [private key set]" -ForegroundColor White
Write-Host "  - DEPLOY_PATH: $DeployPath" -ForegroundColor White
Write-Host ""
Write-Host "You can now trigger the deployment workflow:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Via GitHub CLI:" -ForegroundColor White
Write-Host "    gh workflow run deploy-oracle.yml --repo $RepoOwner/$RepoName" -ForegroundColor Gray
Write-Host ""
Write-Host "  Via Web UI:" -ForegroundColor White
Write-Host "    https://github.com/$RepoOwner/$RepoName/actions/workflows/deploy-oracle.yml" -ForegroundColor Gray
Write-Host ""