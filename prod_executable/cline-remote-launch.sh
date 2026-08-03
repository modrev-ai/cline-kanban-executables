#!/bin/bash
# Cline Remote Access Launch Script for Linux (Oracle Cloud)
# This script starts Cline's Kanban web interface accessible over Tailscale network
# Uses a header-rewriting proxy to bypass Host header validation issues

set -e

echo "========================================"
echo "  Cline Remote Access Launcher (Linux)"
echo "========================================"
echo ""

# Configuration
KANBAN_PORT=3485   # Internal Kanban port (127.0.0.1 only)
PROXY_PORT=3484    # Public proxy port (0.0.0.0, accessible via Tailscale)

# Check if Tailscale is running and logged in
TAILSCALE_PATH="/usr/bin/tailscale"
TAILSCALE_IP=""

if command -v tailscale &> /dev/null; then
    STATUS_OUTPUT=$(tailscale status 2>&1 || true)
    
    if echo "$STATUS_OUTPUT" | grep -q "Logged out"; then
        echo "[WARNING] Tailscale is logged out."
        echo "Please run: tailscale login"
        echo ""
        exit 1
    else
        # Extract Tailscale IP
        TAILSCALE_IP=$(echo "$STATUS_OUTPUT" | grep -E '^100\.' | head -1 | awk '{print $1}')
        
        if [ -n "$TAILSCALE_IP" ]; then
            echo "[OK] Tailscale is connected."
            echo "Your Tailscale IP: $TAILSCALE_IP"
            echo ""
        else
            echo "[WARNING] Could not extract Tailscale IP."
            echo "Tailscale status output:"
            echo "$STATUS_OUTPUT"
            echo ""
        fi
    fi
else
    echo "[WARNING] Tailscale not found."
fi

echo ""
echo "Starting Cline Kanban on internal port $KANBAN_PORT..."
echo "Proxy will listen on public port $PROXY_PORT..."
echo ""

# Check for cline command
CLINE_CMD=$(which cline 2>/dev/null || true)
if [ -z "$CLINE_CMD" ]; then
    echo "[ERROR] cline command not found in PATH"
    echo "Install it with: npm install -g cline"
    exit 1
fi

# Check for kanban-proxy.js
PROXY_SCRIPT_PATH="/home/opc/cline-kanban/prod_executable/kanban-proxy.js"
if [ ! -f "$PROXY_SCRIPT_PATH" ]; then
    echo "[ERROR] kanban-proxy.js not found at $PROXY_SCRIPT_PATH"
    exit 1
fi

# Arrays to track child processes for cleanup
PIDS=()

# Cleanup function
cleanup() {
    echo ""
    echo "Shutting down..." >&2
    
    # Stop Tailscale serve
    if command -v tailscale &> /dev/null; then
        echo "Stopping Tailscale serve..." >&2
        tailscale serve reset 2>&1 | true
    fi
    
    # Kill all child processes
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait a bit for graceful shutdown
    sleep 2
    
    # Force kill if still running
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    echo "Done." >&2
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# Step 1: Start Kanban on internal port 3485, bound to 127.0.0.1
echo "[1/3] Starting Cline Kanban on 127.0.0.1:$KANBAN_PORT ..."
export KANBAN_RUNTIME_HOST="127.0.0.1"
export KANBAN_RUNTIME_PORT="$KANBAN_PORT"

cd /home/opc/cline-kanban
cline kanban &
KANABAN_PID=$!
PIDS+=($KANABAN_PID)

# Wait for Kanban to start listening
echo "Waiting for Kanban server to start..."
KANABAN_STARTED=false
for i in {1..60}; do
    sleep 2
    if ss -tlnp | grep -q ":$KANBAN_PORT "; then
        KANABAN_STARTED=true
        break
    fi
    # Check if process died
    if ! kill -0 "$KANABAN_PID" 2>/dev/null; then
        break
    fi
    echo -n "."
done

if [ "$KANABAN_STARTED" = false ]; then
    echo ""
    echo "[ERROR] Kanban server failed to start on port $KANBAN_PORT."
    exit 1
fi

echo ""
echo "[OK] Kanban server is listening on 127.0.0.1:$KANBAN_PORT"

# Step 2: Start the proxy on port 3484
echo ""
echo "[2/3] Starting header-rewriting proxy on 0.0.0.0:$PROXY_PORT ..."

# Set NODE_PATH to include global npm modules for http-proxy
export NODE_PATH="/home/opc/.npm-global/lib/node_modules"

cd /home/opc/cline-kanban/prod_executable
node kanban-proxy.js &
PROXY_PID=$!
PIDS+=($PROXY_PID)

# Wait for proxy to start listening
sleep 3
PROXY_STARTED=false
for i in {1..15}; do
    sleep 1
    if ss -tlnp | grep -q ":$PROXY_PORT "; then
        PROXY_STARTED=true
        break
    fi
    echo -n "."
done

if [ "$PROXY_STARTED" = false ]; then
    echo ""
    echo "[ERROR] Proxy failed to start on port $PROXY_PORT."
    exit 1
fi

echo ""
echo "[OK] Proxy is listening on 0.0.0.0:$PROXY_PORT"

# Step 3: Configure Tailscale serve
echo ""
echo "[3/3] Configuring Tailscale serve for port $PROXY_PORT..."

if command -v tailscale &> /dev/null; then
    SERVE_RESULT=$(tailscale serve --bg --yes localhost:$PROXY_PORT 2>&1 || true)
    echo "$SERVE_RESULT"
    
    # Check if serve failed due to tailnet policy
    SERVE_STATUS=$(tailscale serve status --json 2>&1 || true)
    if echo "$SERVE_STATUS" | grep -q "Serve is not enabled\|not enabled"; then
        echo ""
        echo "[WARNING] Tailscale Serve is not enabled on your tailnet."
        echo "The server is still accessible via your Tailscale IP directly."
        echo "To enable Serve, visit:"
        echo "  https://login.tailscale.com/f/serve?node=n6Ds2UyBTa11CNTRL"
    fi
fi

# Success - display access information
echo ""
echo "========================================"
echo "  Cline Kanban is ready!"
echo "========================================"
echo ""
echo "Architecture:"
echo "  Phone/Tailscale -> Proxy (0.0.0.0:$PROXY_PORT) -> Kanban (127.0.0.1:$KANBAN_PORT)"
echo ""

if [ -n "$TAILSCALE_IP" ]; then
    echo "Access from your phone at:"
    echo "  http://${TAILSCALE_IP}:$PROXY_PORT"
    echo ""
    echo "Or use your Tailscale hostname:"
    echo "  http://modrev:$PROXY_PORT"
    echo ""
fi

echo "Local access (server):"
echo "  http://127.0.0.1:$PROXY_PORT"
echo ""
echo "Press Ctrl+C to stop."

# Keep the script running and wait for user to press Ctrl+C
while true; do
    sleep 2
    
    # Check if either process has exited unexpectedly
    if ! kill -0 "$KANABAN_PID" 2>/dev/null; then
        echo ""
        echo "[ERROR] Kanban server exited unexpectedly."
        break
    fi
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
        echo ""
        echo "[ERROR] Proxy exited unexpectedly."
        break
    fi
done