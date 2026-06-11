#!/usr/bin/env bash

set -euo pipefail

SITE_NAME="${CCS_NGINX_SITE_NAME:-ccs-gateway-web-30033}"
LISTEN_PORT="${CCS_NGINX_LISTEN_PORT:-30033}"
UPSTREAM_URL="${CCS_NGINX_UPSTREAM_URL:-http://127.0.0.1:17666}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PATH="$REPO_ROOT/deploy/nginx/ccs-gateway-web-30033.conf"
AVAILABLE_PATH="/etc/nginx/sites-available/$SITE_NAME"
ENABLED_PATH="/etc/nginx/sites-enabled/$SITE_NAME"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must run as root on the WSL/Ubuntu host." >&2
  echo "Try: sudo bash scripts/install-wsl-nginx-ccs.sh" >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx is not installed on this WSL/Ubuntu host." >&2
  echo "Install it first: sudo apt-get update && sudo apt-get install -y nginx" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "NGINX template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

tmp_conf="$(mktemp)"
sed \
  -e "s/listen 30033;/listen $LISTEN_PORT;/" \
  -e "s/listen \\[::\\]:30033;/listen [::]:$LISTEN_PORT;/" \
  -e "s#proxy_pass http://127.0.0.1:17666;#proxy_pass $UPSTREAM_URL;#" \
  "$TEMPLATE_PATH" > "$tmp_conf"

install -m 0644 "$tmp_conf" "$AVAILABLE_PATH"
rm -f "$tmp_conf"

ln -sfn "$AVAILABLE_PATH" "$ENABLED_PATH"
nginx -t

if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  systemctl reload nginx
else
  nginx -s reload 2>/dev/null || nginx
fi

echo "nginx_site=$SITE_NAME"
echo "nginx_listen_port=$LISTEN_PORT"
echo "nginx_upstream=$UPSTREAM_URL"
echo "nginx_status=installed"
