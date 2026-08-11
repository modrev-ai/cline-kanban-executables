#!/usr/bin/env bash
# =============================================================================
# Runs ON the Oracle box (Oracle Linux). Idempotent — safe to re-run.
# Invoked by .github/workflows/deploy-vaultwarden.yml after the stack files and
# a generated ./.env have been copied to ~/vaultwarden. Reads config from ./.env.
# Does NOT touch the existing kanban stack (ports 3484/3485) — Vaultwarden uses
# 80/443 and its own containers only.
# =============================================================================
set -euo pipefail

APP_DIR="${REMOTE_DIR:-$HOME/vaultwarden}"
cd "$APP_DIR"

# Read a single KEY=VALUE from .env without sourcing (values may contain spaces,
# e.g. the cron expression, which would break `source`).
get_env() { grep -E "^$1=" .env | head -n1 | cut -d= -f2-; }

VW_DOMAIN="$(get_env VW_DOMAIN)"
ENABLE_BACKUP="$(get_env ENABLE_BACKUP)"
BACKUP_ZIP_PASSWORD="$(get_env BACKUP_ZIP_PASSWORD)"
RCLONE_REMOTE_NAME="$(get_env RCLONE_REMOTE_NAME)"
: "${VW_DOMAIN:?VW_DOMAIN missing from .env}"

echo "=== [1/6] Ensure Docker Engine + compose plugin ==="
if ! command -v docker >/dev/null 2>&1; then
	echo "Docker not found — installing (Oracle Linux / docker-ce)…"
	sudo dnf install -y dnf-utils || true
	sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
	sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
sudo systemctl enable --now docker
sudo docker compose version

echo "=== [2/6] Open host firewall for 80/443 ==="
if command -v firewall-cmd >/dev/null 2>&1 && sudo systemctl is-active --quiet firewalld; then
	sudo firewall-cmd --permanent --add-service=http  || true
	sudo firewall-cmd --permanent --add-service=https || true
	sudo firewall-cmd --reload || true
fi
sudo iptables -I INPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
sudo mkdir -p /etc/iptables && sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null 2>&1 || true

echo "=== [3/6] Preflight: ports 80/443 free (or already ours) ==="
for p in 80 443; do
	if sudo ss -tlnH "( sport = :$p )" | grep -q LISTEN; then
		if ! sudo docker ps --format '{{.Names}}' | grep -qx caddy; then
			echo "ERROR: port $p is in use by a non-Vaultwarden process:" >&2
			sudo ss -tlnp "( sport = :$p )" >&2
			exit 1
		fi
	fi
done

echo "=== [4/6] Prepare data dir + lock file permissions ==="
mkdir -p data/vw-data
chmod 700 data
chmod 600 .env 2>/dev/null || true
[ -f rclone.conf ] && chmod 600 rclone.conf || true

echo "=== [5/6] Decide backup profile ==="
PROFILE_ARGS=()
if [ "${ENABLE_BACKUP:-false}" = "true" ]; then
	if [ -f rclone.conf ] && [ -n "${BACKUP_ZIP_PASSWORD:-}" ]; then
		PROFILE_ARGS=(--profile backup)
		echo "Backup ENABLED (rclone remote: ${RCLONE_REMOTE_NAME:-<parsed from rclone.conf>})"
	else
		echo "WARNING: ENABLE_BACKUP=true but rclone.conf or BACKUP_ZIP_PASSWORD is missing."
		echo "         Deploying the vault WITHOUT backup. Add the secrets and re-run to enable it."
	fi
fi

echo "=== [6/6] docker compose pull + up ==="
sudo docker compose --env-file .env "${PROFILE_ARGS[@]}" pull
sudo docker compose --env-file .env "${PROFILE_ARGS[@]}" up -d --remove-orphans

echo "=== Waiting for the vault to answer through Caddy (TLS issuance ~30-60s) ==="
ok=false
for i in $(seq 1 24); do
	code=$(curl -sk -o /dev/null -w '%{http_code}' "https://${VW_DOMAIN}/alive" --max-time 10 || echo 000)
	echo "  attempt $i: https://${VW_DOMAIN}/alive -> $code"
	if [ "$code" = "200" ]; then ok=true; break; fi
	sleep 5
done

echo "=== Container status ==="
sudo docker compose ps
if [ "$ok" = true ]; then
	echo "=== SUCCESS: vault is live at https://${VW_DOMAIN} ==="
else
	echo "WARNING: /alive did not return 200 yet."
	echo "  Most likely cause: Caddy is still issuing the certificate, OR the OCI VCN"
	echo "  Security List does not allow inbound 80/443 (host firewall alone isn't enough)."
	echo "=== Recent Caddy logs ==="
	sudo docker compose logs --tail=50 caddy || true
	exit 1
fi
