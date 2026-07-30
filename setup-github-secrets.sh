#!/bin/bash
# GitHub Secrets Setup Script for Oracle Compute Deployment
# Run this script to configure GitHub repository secrets for deployment

set -e

REPO_OWNER="modrev-ai"
REPO_NAME="cline-kanban-executables"

# Oracle compute instance details (provided by user)
ORACLE_HOST="129.159.69.183"
ORACLE_USER="opc"
SSH_KEY_PATH="C:/Users/jshin/.ssh/ssh-key-2026-07-30.key"
DEPLOY_PATH="/home/opc/cline-kanban"

echo "========================================="
echo "GitHub Secrets Setup for Oracle Deployment"
echo "========================================="
echo ""
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Oracle Host: $ORACLE_HOST"
echo "Oracle User: $ORACLE_USER"
echo "SSH Key: $SSH_KEY_PATH"
echo "Deploy Path: $DEPLOY_PATH"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed."
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo "ERROR: Not authenticated with GitHub CLI."
    echo "Run: gh auth login"
    exit 1
fi

# Read SSH private key
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH key not found at $SSH_KEY_PATH"
    exit 1
fi

SSH_KEY=$(cat "$SSH_KEY_PATH" | sed ':a;N;$!ba;s/\n/\\n/g')

echo "Setting up GitHub secrets..."

# Set ORACLE_HOST
echo "Setting ORACLE_HOST..."
gh secret set ORACLE_HOST --body "$ORACLE_HOST" --repo "$REPO_OWNER/$REPO_NAME"

# Set ORACLE_USER
echo "Setting ORACLE_USER..."
gh secret set ORACLE_USER --body "$ORACLE_USER" --repo "$REPO_OWNER/$REPO_NAME"

# Set ORACLE_SSH_KEY
echo "Setting ORACLE_SSH_KEY..."
gh secret set ORACLE_SSH_KEY --body "$SSH_KEY" --repo "$REPO_OWNER/$REPO_NAME"

# Set DEPLOY_PATH
echo "Setting DEPLOY_PATH..."
gh secret set DEPLOY_PATH --body "$DEPLOY_PATH" --repo "$REPO_OWNER/$REPO_NAME"

echo ""
echo "========================================="
echo "All secrets configured successfully!"
echo "========================================="
echo ""
echo "Secrets configured:"
echo "  - ORACLE_HOST: $ORACLE_HOST"
echo "  - ORACLE_USER: $ORACLE_USER"
echo "  - ORACLE_SSH_KEY: [private key set]"
echo "  - DEPLOY_PATH: $DEPLOY_PATH"
echo ""
echo "You can now trigger the deployment workflow from GitHub Actions:"
echo "  gh workflow run deploy-oracle.yml --repo $REPO_OWNER/$REPO_NAME"
echo ""
echo "Or go to: https://github.com/$REPO_OWNER/$REPO_NAME/actions/workflows/deploy-oracle.yml"