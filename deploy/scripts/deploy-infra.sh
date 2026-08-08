#!/bin/bash
set -euo pipefail

ORACLE_USER="${ORACLE_USER}"
DEPLOY_PATH="${DEPLOY_PATH}"

echo "=== [1/4] Verifying system packages (using pre-installed binaries, no dnf) ==="
# Oracle Linux typically has git, curl, wget, firewalld pre-installed
# Verify they exist instead of installing via dnf (avoids slow repo metadata updates)
for cmd in git curl wget firewall-cmd; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "WARNING: $cmd not found - Oracle Linux should have these pre-installed"
    case "$cmd" in
      firewall-cmd)
        # firewalld is typically pre-installed on Oracle Linux, try starting service
        echo "firewall-cmd not found - attempting to start firewalld service..."
        sudo systemctl enable --now firewalld 2>/dev/null || echo "Warning: Could not start firewalld service"
        ;;
      *)
        echo "ERROR: Required command '$cmd' not available. Please ensure Oracle Linux base image includes git, curl, wget"
        exit 1
        ;;
    esac
  else
    echo "$cmd is available"
  fi
done

echo "=== [2/4] Configuring swap (4GB) ==="
if [ ! -f /swapfile ]; then
  # Use dd with status=none for faster swap creation, fallocate as fallback
  sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none 2>/dev/null || sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
else
  CURRENT_SIZE=$(stat -c%s /swapfile 2>/dev/null || echo 0)
  if [ "$CURRENT_SIZE" -lt 4294967296 ]; then
    sudo swapoff /swapfile
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none 2>/dev/null || sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
  fi
fi

echo "=== [3/4] Installing Node.js 22 via binary download (fastest, no repo updates) ==="
# Remove any existing nodejs to avoid conflicts (using direct binary removal, no dnf)
sudo rm -f /usr/bin/node /usr/bin/npm /usr/bin/npx 2>/dev/null || true
sudo rm -rf /usr/local/lib/nodejs 2>/dev/null || true
sudo rm -rf /usr/lib/node_modules 2>/dev/null || true
# Also remove any dnf-installed nodejs if present (but don't use dnf to do it)
sudo rpm -e --nodeps nodejs npm 2>/dev/null || true

# Download and install Node.js 22 binary directly (bypasses NodeSource repo entirely)
NODE_VERSION="22.14.0"
ARCH="x64"
cd /tmp
echo "Downloading Node.js ${NODE_VERSION} binary..."
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" -o node.tar.xz
tar -xf node.tar.xz
sudo rm -rf /usr/local/lib/nodejs
sudo mkdir -p /usr/local/lib/nodejs
sudo mv "node-v${NODE_VERSION}-linux-${ARCH}" /usr/local/lib/nodejs/node-v${NODE_VERSION}

# Create symlinks
sudo ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}/bin/node /usr/bin/node
sudo ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}/bin/npm /usr/bin/npm
sudo ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}/bin/npx /usr/bin/npx

# Verify installation
/usr/bin/node --version
/usr/bin/npm --version

NODE_MAJOR=$(/usr/bin/node --version | sed 's/v\([0-9]*\).*/\1/')
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "ERROR: Node.js version is $NODE_MAJOR, but version 22 or higher is required"
  exit 1
fi
echo "Node.js version $NODE_MAJOR meets requirement (>= 22)"

echo "=== [4/4] Configuring npm, installing global packages, firewall, and services ==="
# Configure npm for speed
sudo npm config set prefer-offline true
sudo npm config set audit false
sudo npm config set fund false
sudo npm config set maxsockets 1

# Configure git
sudo git config --global url."https://github.com/".insteadOf "git@github.com:"
sudo git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

echo "=== Installing http-proxy, cline, and kanban as ORACLE_USER (not root) ==="
# Configure npm for ORACLE_USER
sudo -u "${ORACLE_USER}" bash -c 'npm config set prefix ~/.npm-global && npm config set prefer-offline true && npm config set audit false && npm config set fund false && npm config set maxsockets 1'

echo "=== Installing http-proxy ==="
# Check if http-proxy is already installed
INSTALLED_HTTP_PROXY_VERSION=""
if sudo -u "${ORACLE_USER}" bash -c 'npm list -g http-proxy --depth=0' &>/dev/null; then
  INSTALLED_HTTP_PROXY_VERSION=$(sudo -u "${ORACLE_USER}" bash -c 'npm list -g http-proxy --depth=0 2>/dev/null | grep http-proxy@ | sed "s/.*http-proxy@\([^ ]*\).*/\1/"' || echo "")
  echo "Currently installed http-proxy version: $INSTALLED_HTTP_PROXY_VERSION"
else
  echo "http-proxy not currently installed globally"
fi

# Get latest http-proxy version from npm
HTTP_PROXY_LATEST_VERSION=$(npm view http-proxy version 2>/dev/null || echo "1.18.1")
echo "Latest http-proxy version from npm: $HTTP_PROXY_LATEST_VERSION"

# Only install/update if version differs
if [ "$INSTALLED_HTTP_PROXY_VERSION" != "$HTTP_PROXY_LATEST_VERSION" ]; then
  echo "Installing/updating http-proxy to $HTTP_PROXY_LATEST_VERSION..."
  sudo -u "${ORACLE_USER}" bash -c 'npm install -g http-proxy --omit=optional --maxsockets=1' 2>&1 | tail -10
else
  echo "http-proxy is already at the latest version ($HTTP_PROXY_LATEST_VERSION), skipping installation"
fi

echo "=== Installing cline from modrev-ai/cline (latest release) ==="
# Check if cline is already installed with the correct version
# Use curl + grep/sed instead of python3 for better compatibility
# Filter out placeholder versions (vX.Y.Z-modrev.N) and get the latest actual release
CLINE_LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/modrev-ai/cline/releases" 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' | grep -v '^vX\.Y\.Z-modrev\.N$' | head -1 || echo "v4.1.3-modrev.1")
echo "Latest cline version from modrev-ai/cline: $CLINE_LATEST_VERSION"

# Check currently installed cline version - use the actual binary to get version
INSTALLED_CLINE_VERSION=""
if sudo -u "${ORACLE_USER}" bash -c 'command -v cline' &>/dev/null; then
  INSTALLED_CLINE_VERSION=$(sudo -u "${ORACLE_USER}" bash -c 'cline --version 2>/dev/null' | head -1 || echo "")
  echo "Currently installed cline version: $INSTALLED_CLINE_VERSION"
else
  echo "cline not currently installed"
fi

# Normalize versions for comparison (remove leading 'v' if present)
NORMALIZED_LATEST="${CLINE_LATEST_VERSION#v}"
NORMALIZED_INSTALLED="${INSTALLED_CLINE_VERSION#v}"

# Force reinstall if version differs OR if we can't verify the installed version matches modrev-ai
# Also check if the installed cline is actually from modrev-ai by checking its package.json
FORCE_CLINE_INSTALL=false
if [ "$NORMALIZED_INSTALLED" != "$NORMALIZED_LATEST" ]; then
  echo "Version mismatch: installed=$NORMALIZED_INSTALLED, expected=$NORMALIZED_LATEST"
  FORCE_CLINE_INSTALL=true
elif [ -z "$INSTALLED_CLINE_VERSION" ]; then
  echo "No cline version detected"
  FORCE_CLINE_INSTALL=true
else
  # Verify the installed cline is from modrev-ai by checking package.json
  CLINE_PKG_PATH=$(sudo -u "${ORACLE_USER}" bash -c 'npm root -g 2>/dev/null' 2>/dev/null)/cline/package.json
  if [ -f "$CLINE_PKG_PATH" ]; then
    CLINE_REPO=$(grep -o '"repository"[^}]*' "$CLINE_PKG_PATH" 2>/dev/null | head -1 || echo "")
    if [[ ! "$CLINE_REPO" =~ modrev-ai/cline ]]; then
      echo "Installed cline is not from modrev-ai/cline (repository: $CLINE_REPO), forcing reinstall"
      FORCE_CLINE_INSTALL=true
    fi
  else
    echo "Could not verify cline package source, forcing reinstall to ensure modrev-ai version"
    FORCE_CLINE_INSTALL=true
  fi
fi

if [ "$FORCE_CLINE_INSTALL" = true ]; then
  echo "Installing/updating cline to $CLINE_LATEST_VERSION from modrev-ai/cline..."
  # Use the tarball URL from GitHub releases
  # Capture both stdout and stderr to see what's happening
  echo "Running npm install command..."
  sudo -u "${ORACLE_USER}" bash -c "npm install -g https://github.com/modrev-ai/cline/archive/refs/tags/${CLINE_LATEST_VERSION}.tar.gz --omit=optional --maxsockets=1" 2>&1
  CLINE_INSTALL_EXIT_CODE=$?
  echo "npm install exit code: $CLINE_INSTALL_EXIT_CODE"
  if [ $CLINE_INSTALL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Failed to install cline from modrev-ai/cline (exit code: $CLINE_INSTALL_EXIT_CODE)"
    exit $CLINE_INSTALL_EXIT_CODE
  fi
  echo "npm install completed successfully"
  echo "DEBUG: Starting symlink creation..."
  
  # Find and create proper symlink for cline binary - use npm global bin directly since PATH may not include it
  # The binary might be in different locations depending on npm prefix
  # IMPORTANT: Check npm global bin FIRST (newly installed version), then /usr/local/bin (old version)
  CLINE_BIN_PATH=""
  
  # Get the actual npm global bin for the oracle user
  echo "DEBUG: Getting npm global bin..."
  NPM_GLOBAL_BIN=$(sudo -u "${ORACLE_USER}" bash -c 'npm bin -g 2>/dev/null' 2>/dev/null)
  echo "DEBUG: npm bin -g returned: '$NPM_GLOBAL_BIN'"
  if [ -z "$NPM_GLOBAL_BIN" ]; then
    NPM_GLOBAL_BIN="/home/${ORACLE_USER}/.npm-global/bin"
    echo "DEBUG: Using fallback npm global bin: $NPM_GLOBAL_BIN"
  fi
  echo "npm global bin: $NPM_GLOBAL_BIN"
  
  # Also get npm global root to find the package
  echo "DEBUG: Getting npm global root..."
  NPM_GLOBAL_ROOT=$(sudo -u "${ORACLE_USER}" bash -c 'npm root -g 2>/dev/null' 2>/dev/null)
  echo "DEBUG: npm root -g returned: '$NPM_GLOBAL_ROOT'"
  echo "npm global root: $NPM_GLOBAL_ROOT"
  
  # Check multiple possible locations for the cline binary
  # Priority: npm global bin -> npm global root/cline/bin -> ~/.npm-global/bin -> /usr/local/bin
  echo "DEBUG: Checking for cline binary at ${NPM_GLOBAL_BIN}/cline"
  if [ -f "${NPM_GLOBAL_BIN}/cline" ]; then
    CLINE_BIN_PATH="${NPM_GLOBAL_BIN}/cline"
    echo "DEBUG: Found at npm global bin"
  elif [ -n "$NPM_GLOBAL_ROOT" ] && [ -f "${NPM_GLOBAL_ROOT}/cline/bin/cline" ]; then
    CLINE_BIN_PATH="${NPM_GLOBAL_ROOT}/cline/bin/cline"
    echo "DEBUG: Found at npm global root/cline/bin/cline"
  elif [ -n "$NPM_GLOBAL_ROOT" ] && [ -f "${NPM_GLOBAL_ROOT}/cline/cli.js" ]; then
    # Some packages have cli.js instead of bin/cline
    CLINE_BIN_PATH="${NPM_GLOBAL_ROOT}/cline/cli.js"
    echo "DEBUG: Found at npm global root/cline/cli.js"
  elif [ -f "/home/${ORACLE_USER}/.npm-global/bin/cline" ]; then
    CLINE_BIN_PATH="/home/${ORACLE_USER}/.npm-global/bin/cline"
    echo "DEBUG: Found at ~/.npm-global/bin/cline"
  elif [ -f "/usr/local/bin/cline" ]; then
    CLINE_BIN_PATH="/usr/local/bin/cline"
    echo "DEBUG: Found at /usr/local/bin/cline"
  fi
  
  if [ -n "$CLINE_BIN_PATH" ] && [ -f "$CLINE_BIN_PATH" ]; then
    echo "Found cline binary at: $CLINE_BIN_PATH"
    echo "DEBUG: Creating symlink..."
    sudo ln -sf "$CLINE_BIN_PATH" /usr/bin/cline
    echo "DEBUG: Symlink created"
  else
    echo "WARNING: Could not find cline binary at npm global bin"
    echo "Checking npm global bin directory:"
    sudo -u "${ORACLE_USER}" bash -c 'ls -la ~/.npm-global/bin/' || true
    echo "Checking npm global root:"
    sudo -u "${ORACLE_USER}" bash -c 'ls -la ~/.npm-global/lib/node_modules/' || true
    echo "Searching for cline in npm global root:"
    sudo -u "${ORACLE_USER}" bash -c 'find ~/.npm-global/lib/node_modules/cline -type f \( -name "cline" -o -name "cli.js" \) 2>/dev/null | head -20' || true
    # Also check /usr/local/bin
    ls -la /usr/local/bin/ | grep cline || true
  fi
  
  # Verify the symlink points to the correct (new) version
  echo "Verifying cline symlink points to correct version..."
  echo "DEBUG: Running /usr/bin/cline --version"
  /usr/bin/cline --version
  echo "DEBUG: cline --version completed"
else
  echo "cline is already at the correct modrev-ai version ($CLINE_LATEST_VERSION), skipping installation"
  # Ensure symlink exists even if skipping installation
  if [ ! -f "/usr/bin/cline" ]; then
    if [ -f "/home/${ORACLE_USER}/.npm-global/bin/cline" ]; then
      sudo ln -sf /home/${ORACLE_USER}/.npm-global/bin/cline /usr/bin/cline
    elif [ -f "/usr/local/bin/cline" ]; then
      sudo ln -sf /usr/local/bin/cline /usr/bin/cline
    fi
  fi
fi

echo "=== Installing kanban from modrev-ai/kanban (latest main branch) ==="
# Since modrev-ai/kanban doesn't have GitHub releases, we use the main branch tarball
# Get the latest commit SHA from main branch for version tracking
KANABAN_LATEST_SHA=$(curl -fsSL "https://api.github.com/repos/modrev-ai/kanban/commits/main" 2>/dev/null | grep '"sha"' | head -1 | sed 's/.*"sha": "\([^"]*\)".*/\1/' | cut -c1-7 || echo "main")
echo "Latest kanban commit from modrev-ai/kanban: $KANABAN_LATEST_SHA"

# Check currently installed kanban version - use package.json to get actual version
INSTALLED_KANABAN_VERSION=""
INSTALLED_KANABAN_REPO=""
if sudo -u "${ORACLE_USER}" bash -c 'npm list -g kanban --depth=0' &>/dev/null; then
  INSTALLED_KANABAN_VERSION=$(sudo -u "${ORACLE_USER}" bash -c 'npm list -g kanban --depth=0 2>/dev/null | grep kanban@ | sed "s/.*kanban@\([^ ]*\).*/\1/"' || echo "")
  echo "Currently installed kanban version: $INSTALLED_KANABAN_VERSION"
  # Check if it's from modrev-ai/kanban by looking at package.json
  KANABAN_PKG_PATH=$(sudo -u "${ORACLE_USER}" bash -c 'npm root -g 2>/dev/null' 2>/dev/null)/kanban/package.json
  if [ -f "$KANABAN_PKG_PATH" ]; then
    INSTALLED_KANABAN_REPO=$(grep -o '"repository"[^}]*' "$KANABAN_PKG_PATH" 2>/dev/null | head -1 || echo "")
    echo "Installed kanban repository: $INSTALLED_KANABAN_REPO"
  fi
else
  echo "kanban not currently installed globally"
fi

# Force reinstall if not from modrev-ai/kanban or if we can't verify
FORCE_KANABAN_INSTALL=false
if [ -z "$INSTALLED_KANABAN_VERSION" ]; then
  echo "No kanban version detected"
  FORCE_KANABAN_INSTALL=true
elif [[ ! "$INSTALLED_KANABAN_REPO" =~ modrev-ai/kanban ]]; then
  echo "Installed kanban is not from modrev-ai/kanban (repository: $INSTALLED_KANABAN_REPO), forcing reinstall"
  FORCE_KANABAN_INSTALL=true
else
  echo "kanban is already from modrev-ai/kanban, skipping installation"
fi

if [ "$FORCE_KANABAN_INSTALL" = true ]; then
  echo "Installing/updating kanban to latest from modrev-ai/kanban main branch..."
  # Use the tarball URL from GitHub main branch
  sudo -u "${ORACLE_USER}" bash -c "npm install -g https://github.com/modrev-ai/kanban/tarball/main --omit=optional --maxsockets=1" 2>&1 | tail -10
  
  # Find and create proper symlink for kanban binary
  if [ -f "/home/${ORACLE_USER}/.npm-global/bin/kanban" ]; then
    echo "Found kanban binary at: /home/${ORACLE_USER}/.npm-global/bin/kanban"
    sudo ln -sf /home/${ORACLE_USER}/.npm-global/bin/kanban /usr/bin/kanban
  else
    echo "WARNING: Could not find kanban binary at npm global bin"
    sudo -u "${ORACLE_USER}" bash -c 'ls -la ~/.npm-global/bin/' || true
    sudo -u "${ORACLE_USER}" bash -c 'find ~/.npm-global/lib/node_modules/kanban -type f -name "*.js" 2>/dev/null | head -20' || true
  fi
else
  echo "kanban is already from modrev-ai/kanban, skipping installation"
  # Ensure symlink exists even if skipping installation
  if [ ! -f "/usr/bin/kanban" ]; then
    if [ -f "/home/${ORACLE_USER}/.npm-global/bin/kanban" ]; then
      sudo ln -sf /home/${ORACLE_USER}/.npm-global/bin/kanban /usr/bin/kanban
    fi
  fi
fi

echo "=== Verifying cline kanban command (built into cline) ==="
# kanban is a built-in command of cline, not a separate package
# Verify it's available using the full path
if /usr/bin/cline kanban --help &>/dev/null; then
  echo "cline kanban command is available"
else
  echo "WARNING: cline kanban command not found - may need to rebuild cline"
fi

echo "=== Creating cline symlink ==="
# Find actual cline binary location - use npm global bin directly
if [ -f "/home/${ORACLE_USER}/.npm-global/bin/cline" ]; then
  echo "Found cline at: /home/${ORACLE_USER}/.npm-global/bin/cline"
  sudo ln -sf /home/${ORACLE_USER}/.npm-global/bin/cline /usr/bin/cline
elif [ -f "/usr/local/bin/cline" ]; then
  echo "Found cline at: /usr/local/bin/cline"
  sudo ln -sf /usr/local/bin/cline /usr/bin/cline
else
  echo "WARNING: Could not find cline binary at npm global bin or /usr/local/bin"
fi

echo "=== Creating kanban symlink ==="
# Find actual kanban binary location - use npm global bin directly
if [ -f "/home/${ORACLE_USER}/.npm-global/bin/kanban" ]; then
  echo "Found kanban at: /home/${ORACLE_USER}/.npm-global/bin/kanban"
  sudo ln -sf /home/${ORACLE_USER}/.npm-global/bin/kanban /usr/bin/kanban
else
  echo "WARNING: Could not find kanban binary at npm global bin"
fi

echo "=== Verifying installation ==="
node --version
npm --version
cline --version || (echo "cline not found, checking npm global bin:" && ls -la /usr/local/bin/ | grep cline || true)
cline kanban --help 2>&1 | head -5 || echo "cline kanban help check completed"

echo "=== Configuring firewalld (single pass, no retries) ==="
# Check if firewalld is installed
if ! command -v firewall-cmd &> /dev/null; then
  echo "firewall-cmd not found, attempting to start firewalld service directly..."
  # firewalld is typically pre-installed on Oracle Linux, just start it
  sudo systemctl enable --now firewalld 2>/dev/null || echo "Warning: Could not start firewalld service"
  sleep 2
fi

# Start and enable firewalld if not running
if ! systemctl is-active --quiet firewalld; then
  echo "firewalld not running, starting and enabling..."
  sudo systemctl enable --now firewalld
  # Wait for firewalld to be ready
  sleep 2
fi

# Add ports to firewalld (single attempt, continue on failure)
for port in 3484 3485; do
  sudo firewall-cmd --permanent --add-port=${port}/tcp 2>/dev/null && echo "Added port ${port}/tcp to firewalld (permanent)" || echo "Warning: Failed to add port ${port}/tcp permanently"
done

# Reload firewalld (single attempt)
sudo firewall-cmd --reload 2>/dev/null && echo "firewalld reloaded successfully" || echo "Warning: firewalld reload failed"

echo "=== Configuring iptables as fallback ==="
sudo iptables -I INPUT -p tcp --dport 3484 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT -p tcp --dport 3485 -j ACCEPT 2>/dev/null || true

echo "=== Saving iptables rules ==="
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null 2>&1 || true

echo "=== Creating systemd service files ==="
echo "=== Creating kanban-proxy service ==="
sudo tee /etc/systemd/system/kanban-proxy.service > /dev/null << SVC_EOF
[Unit]
Description=Kanban Header Rewriting Proxy
After=network.target

[Service]
Type=simple
User=${ORACLE_USER}
WorkingDirectory=${DEPLOY_PATH}/prod_executable
Environment=NODE_PATH=/home/${ORACLE_USER}/.npm-global/lib/node_modules:/usr/local/lib/node_modules
ExecStart=/usr/bin/node kanban-proxy.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC_EOF

echo "=== Creating kanban-server service ==="
sudo tee /etc/systemd/system/kanban-server.service > /dev/null << SVC_EOF
[Unit]
Description=Kanban Server (Cline)
After=network.target

[Service]
Type=simple
User=${ORACLE_USER}
WorkingDirectory=${DEPLOY_PATH}
Environment=KANBAN_RUNTIME_HOST=127.0.0.1
Environment=KANBAN_RUNTIME_PORT=3485
Environment=NODE_ENV=production
Environment=NODE_PATH=/home/${ORACLE_USER}/.npm-global/lib/node_modules:/usr/local/lib/node_modules
ExecStart=/usr/bin/cline kanban
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC_EOF

echo "=== Fixing SELinux context for service files ==="
sudo restorecon -v /etc/systemd/system/kanban-proxy.service /etc/systemd/system/kanban-server.service

echo "=== Reloading systemd ==="
sudo systemctl daemon-reload

echo "=== Verifying unit files syntax ==="
sudo systemd-analyze verify /etc/systemd/system/kanban-proxy.service
sudo systemd-analyze verify /etc/systemd/system/kanban-server.service

echo "=== Verifying unit files loaded ==="
systemctl list-unit-files | grep -E "kanban-proxy|kanban-server" || (echo "ERROR: Unit files not found after daemon-reload" && exit 1)

echo "=== Enabling and starting services ==="
sudo systemctl enable kanban-proxy
sudo systemctl start kanban-proxy
sudo systemctl enable kanban-server
sudo systemctl start kanban-server

echo "=== Waiting for services to start ==="
sleep 5

echo "=== Verifying services are running ==="
systemctl is-active kanban-proxy && echo "kanban-proxy is active" || (echo "ERROR: kanban-proxy failed to start" && systemctl status kanban-proxy && exit 1)
systemctl is-active kanban-server && echo "kanban-server is active" || (echo "ERROR: kanban-server failed to start" && systemctl status kanban-server && exit 1)

echo "=== Service files created successfully ==="
cat /etc/systemd/system/kanban-proxy.service
cat /etc/systemd/system/kanban-server.service

echo "=== Infrastructure deployment complete ==="