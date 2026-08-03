# GitHub CLI & Git Setup Documentation for Oracle Server

This document provides a complete reference for setting up GitHub CLI (`gh`), Git, GPG signing, and SSH authentication on a new Oracle server (or any Linux/WSL environment).

---

## 1. Prerequisites

### Install GitHub CLI (`gh`)

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y gh
```

**RHEL/CentOS/Fedora:**
```bash
sudo dnf install -y gh
```

**Arch Linux:**
```bash
sudo pacman -S github-cli
```

**macOS (Homebrew):**
```bash
brew install gh
```

**Windows (via winget):**
```powershell
winget install --id GitHub.cli
```

Verify installation:
```bash
gh --version
```

---

## 2. GitHub CLI Authentication

### Option A: Interactive Login (Recommended)

```bash
gh auth login
```

Follow the prompts:
- **What account do you want to log into?** → `GitHub.com`
- **What is your preferred protocol for Git operations?** → `SSH` (or HTTPS)
- **Upload your SSH public key to your GitHub account?** → `Yes` (if you have one)
- **How would you like to authenticate?** → `Login with a web browser`

This will open a browser window to authenticate and save the token to `~/.config/gh/hosts.yml`.

### Option B: Token-Based Authentication (For Automation)

```bash
# Create a Personal Access Token (classic) at: https://github.com/settings/tokens
# Required scopes: repo, admin:public_key, admin:ssh_signing_key, workflow

echo "YOUR_PERSONAL_ACCESS_TOKEN" | gh auth login --with-token
```

### Verify Authentication

```bash
gh auth status
```

Expected output:
```
✓ Logged in to github.com as YOUR_USERNAME (keyring)
✓ Git operations for github.com configured to use ssh protocol
✓ Token: gho_************************************
```

---

## 3. SSH Key Setup for GitHub

### Generate SSH Key (Ed25519 - Recommended)

```bash
ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519
```

- Press Enter for default location
- Enter a strong passphrase (or leave empty for automation)

### Start SSH Agent & Add Key

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### Add SSH Key to GitHub via CLI

```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --title "Oracle Server $(date +%Y-%m-%d)"
```

### Verify SSH Connection

```bash
ssh -T git@github.com
```

Expected output:
```
Hi YOUR_USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

---

## 4. GPG Signing Setup (For Verified Commits)

### Generate GPG Key

```bash
gpg --full-generate-key
```

Select:
- **Key type:** `RSA and RSA` (default)
- **Key size:** `4096`
- **Expiration:** `0` (no expiration) or `2y`
- **Name/Email:** Match your GitHub verified email
- **Passphrase:** Strong passphrase

### List GPG Keys

```bash
gpg --list-secret-keys --keyid-format=long
```

Example output:
```
sec   rsa4096/9275158C9E1D639B 2024-01-15 [SC]
      1234567890ABCDEF1234567890ABCDEF12345678
uid                 [ultimate] Your Name <your_email@example.com>
ssb   rsa4096/ABCDEF1234567890 2024-01-15 [E]
```

### Export Public Key for GitHub

```bash
gpg --armor --export 9275158C9E1D639B
```

Copy the output (including `-----BEGIN PGP PUBLIC KEY BLOCK-----` and `-----END PGP PUBLIC KEY BLOCK-----`).

### Add GPG Key to GitHub via CLI

```bash
gh gpg-key add <(gpg --armor --export 9275158C9E1D639B)
```

Or manually at: https://github.com/settings/keys → "New GPG key"

### Configure Git to Use GPG Key

```bash
git config --global user.signingkey 9275158C9E1D639B
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global gpg.format openpgp
```

### Configure GPG Agent for Passphrase Caching

Create/update `~/.gnupg/gpg-agent.conf`:

```bash
cat > ~/.gnupg/gpg-agent.conf << 'EOF'
default-cache-ttl 86400
max-cache-ttl 86400
pinentry-program /usr/bin/pinentry-curses
EOF
```

Restart GPG agent:
```bash
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
```

### Set GPG_TTY for Terminal Pinentry

Add to `~/.bashrc` or `~/.zshrc`:

```bash
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc
source ~/.bashrc
```

### Test GPG Signing

```bash
echo "test" | gpg --clearsign
```

Should prompt for passphrase once, then cache it.

---

## 5. Git Configuration

### Global User Config

```bash
git config --global user.name "Your Name"
git config --global user.email "your_email@example.com"
```

### Useful Aliases

```bash
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.unstage 'reset HEAD --'
git config --global alias.last 'log -1 HEAD'
git config --global alias.lg "log --oneline --graph --all --decorate"
```

### Default Branch Name

```bash
git config --global init.defaultBranch main
```

### Pull Strategy

```bash
git config --global pull.rebase false  # merge (default)
# or
git config --global pull.rebase true   # rebase
```

### Credential Helper (for HTTPS)

```bash
# Linux (libsecret/gnome-keyring)
git config --global credential.helper libsecret

# macOS
git config --global credential.helper osxkeychain

# Windows
git config --global credential.helper manager-core
```

---

## 6. Complete Server Initialization Script

Save as `setup-github.sh` and run on new server:

```bash
#!/bin/bash
set -e

echo "=== GitHub Server Setup ==="

# 1. Install GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    # Ubuntu/Debian
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update && sudo apt install -y gh
fi

# 2. Authenticate
echo "Authenticating with GitHub..."
gh auth login

# 3. SSH Key
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f ~/.ssh/id_ed25519 -N ""
fi

eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
gh ssh-key add ~/.ssh/id_ed25519.pub --title "Oracle Server $(hostname) $(date +%Y-%m-%d)"

# 4. GPG Key (if not exists)
if ! gpg --list-secret-keys --keyid-format=long | grep -q "sec"; then
    echo "Generating GPG key..."
    gpg --full-generate-key
fi

GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep "sec" | head -1 | awk '{print $2}' | cut -d'/' -f2)
git config --global user.signingkey "$GPG_KEY_ID"
git config --global commit.gpgsign true
git config --global gpg.format openpgp

# GPG Agent config
mkdir -p ~/.gnupg
cat > ~/.gnupg/gpg-agent.conf << 'EOF'
default-cache-ttl 86400
max-cache-ttl 86400
pinentry-program /usr/bin/pinentry-curses
EOF
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent

# Add GPG key to GitHub
gh gpg-key add <(gpg --armor --export "$GPG_KEY_ID")

# 5. GPG_TTY
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc
export GPG_TTY=$(tty)

# 6. Git config
git config --global user.name "$(gh api user --jq .name)"
git config --global user.email "$(gh api user --jq .email)"
git config --global init.defaultBranch main

echo "=== Setup Complete ==="
echo "Test with: git commit -S -m 'test' && git push"
```

Make executable and run:
```bash
chmod +x setup-github.sh
./setup-github.sh
```

---

## 7. Verification Checklist

After setup, verify everything works:

```bash
# 1. GitHub CLI auth
gh auth status

# 2. SSH connection
ssh -T git@github.com

# 3. GPG signing
echo "test" | gpg --clearsign

# 4. Git config
git config --list | grep -E "(user\.|gpg\.|commit\.|credential\.)"

# 5. Test signed commit
cd /tmp && mkdir test-repo && cd test-repo
git init
echo "test" > README.md
git add README.md
git commit -S -m "Test signed commit"
git log --show-signature -1
```

---

## 8. Troubleshooting

### GPG: "Inappropriate ioctl for device"
```bash
export GPG_TTY=$(tty)
echo "test" | gpg --clearsign
```

### GPG: Agent not caching
- Check `~/.gnupg/gpg-agent.conf` has correct `pinentry-program`
- Ensure `pinentry-curses` or `pinentry-tty` is installed
- Restart agent: `gpgconf --kill gpg-agent && gpgconf --launch gpg-agent`

### SSH: Permission denied
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### Git: "gpg failed to sign the data"
```bash
# Ensure GPG_TTY is set
export GPG_TTY=$(tty)
# Kill and restart agent
gpgconf --kill gpg-agent
# Test
echo "test" | gpg --clearsign
```

---

## 9. Useful References

- [GitHub CLI Manual](https://cli.github.com/manual/)
- [Generating a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)
- [Managing commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification)
- [GPG Agent Configuration](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Configuration.html)

---

*Last updated: $(date +%Y-%m-%d)*
*Generated for Oracle Cloud Infrastructure server setup*