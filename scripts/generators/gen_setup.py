import sys

setup = """#!/bin/bash
# Oracle Cloud Free Tier Setup Script
# Kanban + Cline Dashboard Deployment

set -e

echo "=========================================="
echo "Oracle Cloud Free Tier Setup"
echo "Kanban + Cline Dashboard Deployment"
echo "=========================================="

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. Run as ubuntu user."
   exit 1
fi

# Update system
log_info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install essential packages
log_info "Installing essential packages..."
sudo apt install -y \
    curl wget git unzip htop \
    nginx certbot python3-certbot-nginx \
    build-essential python3 \
    ufw fail2ban

# Configure firewall
log_info "Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 41641/udp
sudo ufw --force enable

# Install Node.js 20 (LTS)
log_info "Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Verify Node.js
log_info "Node.js version: $(node --version)"
log_info "npm version: $(npm --version)"

# Install pnpm
log_info "Installing pnpm..."
corepack enable
corepack prepare pnpm@latest --activate
log_info "pnpm version: $(pnpm --version)"

# Install Tailscale
log_info "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Start Tailscale (will prompt for authentication)
log_info "Starting Tailscale..."
sudo tailscale up --ssh

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not connected yet")
log_info "Tailscale IP: $TAILSCALE_IP"

# Install PM2 globally
log_info "Installing PM2..."
sudo npm install -g pm2

# Create log directory
sudo mkdir -p /var/log/pm2
sudo chown -R ubuntu:ubuntu /var/log/pm2

# Clone Kanban repository
log_info "Cloning Kanban repository..."
cd /opt
if [ ! -d "kanban" ]; then
    sudo git clone https://github.com/modrev-ai/kanban.git
    sudo chown -R ubuntu:ubuntu kanban
fi
cd kanban

# Install Kanban dependencies
log_info "Installing Kanban dependencies..."
pnpm install --frozen-lockfile

# Build Kanban
log_info "Building Kanban..."
pnpm run build

# Build web-ui specifically
cd web-ui
pnpm run build

# Create Kanban start script
cat > /opt/kanban/start-kanban.sh << 'EOF'
#!/bin/bash
cd /opt/kanban/web-ui
export NODE_ENV=production
export PORT=3000
exec pnpm preview --host 0.0.0.0 --port 3000
EOF
chmod +x /opt/kanban/start-kanban.sh

# Clone Cline Dashboard repository
log_info "Cloning Cline Dashboard repository..."
cd /opt
if [ ! -d "cline-dashboard" ]; then
    sudo git clone https://github.com/modrev-ai/cline-kanban-executables.git cline-dashboard
    sudo chown -R ubuntu:ubuntu cline-dashboard
fi
cd cline-dashboard

# Install Cline Dashboard dependencies
log_info "Installing Cline Dashboard dependencies..."
npm install

# Initialize database
log_info "Initializing Cline Dashboard database..."
npm run db:init

# Create Cline start script
cat > /opt/cline-dashboard/start-cline.sh << 'EOF'
#!/bin/bash
cd /opt/cline-dashboard
export NODE_ENV=production
export PORT=3001
export HOST=0.0.0.0
export AGY_COMMAND=agy
export AGY_ARGS="run --prompt {prompt} --json-logs"
exec npm start
EOF
chmod +x /opt/cline-dashboard/start-cline.sh

# Create PM2 ecosystem file
log_info "Creating PM2 ecosystem configuration..."
cat > /opt/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [
    {
      name: 'kanban-web',
      script: '/opt/kanban/start-kanban.sh',
      cwd: '/opt/kanban/web-ui',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        HOST: '0.0.0.0'
      },
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      error_file: '/var/log/pm2/kanban-error.log',
      out_file: '/var/log/pm2/kanban-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
    },
    {
      name: 'cline-dashboard',
      script: '/opt/cline-dashboard/start-cline.sh',
      cwd: '/opt/cline-dashboard',
      env: {
        NODE_ENV: 'production',
        PORT: 3001,
        HOST: '0.0.0.0',
        AGY_COMMAND: 'agy',
        AGY_ARGS: 'run --prompt {prompt} --json-logs'
      },
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      error_file: '/var/log/pm2/cline-error.log',
      out_file: '/var/log/pm2/cline-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
    }
  ]
};
EOF

# Start applications with PM2
log_info "Starting applications with PM2..."
pm2 start /opt/ecosystem.config.js

# Save PM2 configuration
pm2 save

# Setup PM2 startup
log_info "Setting up PM2 startup..."
STARTUP_CMD=$(pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1)
if [[ $STARTUP_CMD == sudo* ]]; then
    log_warn "Run the following command with sudo to enable PM2 startup:"
    echo "$STARTUP_CMD"
fi

log_info "Setup complete! Check status with: pm2 status"
"""

with open(sys.argv[1], 'w') as f:
    f.write(setup)
print('Written gen_setup.py')