#!/usr/bin/env bash

set -euo pipefail

SITE_NAME="${CCS_NGINX_SITE_NAME:-ccs-gateway-web-30033}"
LISTEN_PORT="${CCS_NGINX_LISTEN_PORT:-30033}"
UPSTREAM_URL="${CCS_NGINX_UPSTREAM_URL:-http://127.0.0.1:17666}"
ALLOWED_UPSTREAM_URL="http://127.0.0.1:17666"
ALLOWED_LISTEN_PORT="30033"
ALLOWED_SITE_NAME="ccs-gateway-web-30033"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PATH="$REPO_ROOT/deploy/nginx/ccs-gateway-web-30033.conf"
AVAILABLE_PATH="/etc/nginx/sites-available/$SITE_NAME"
ENABLED_PATH="/etc/nginx/sites-enabled/$SITE_NAME"
backup_conf=""
installed_conf=false

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

restore_previous_site() {
  if [[ "$installed_conf" != "true" ]]; then
    return
  fi

  if [[ -n "$backup_conf" && -f "$backup_conf" ]]; then
    install -m 0644 "$backup_conf" "$AVAILABLE_PATH"
    ln -sfn "$AVAILABLE_PATH" "$ENABLED_PATH"
    echo "restored_previous_nginx_site=1" >&2
  else
    rm -f "$AVAILABLE_PATH" "$ENABLED_PATH"
    echo "removed_failed_nginx_site=1" >&2
  fi
}

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

if ! is_valid_port "$LISTEN_PORT"; then
  echo "Invalid NGINX listen port: $LISTEN_PORT" >&2
  exit 1
fi

if [[ "$SITE_NAME" != "$ALLOWED_SITE_NAME" ]]; then
  echo "Refusing unsupported NGINX site name: $SITE_NAME" >&2
  echo "Only $ALLOWED_SITE_NAME is allowed for this deployment." >&2
  exit 1
fi

if [[ "$UPSTREAM_URL" != "$ALLOWED_UPSTREAM_URL" ]]; then
  echo "Refusing unsafe NGINX upstream: $UPSTREAM_URL" >&2
  echo "Only $ALLOWED_UPSTREAM_URL is allowed; do not expose the model proxy through NGINX." >&2
  exit 1
fi

if [[ "$LISTEN_PORT" != "$ALLOWED_LISTEN_PORT" ]]; then
  echo "Refusing unsupported NGINX listen port: $LISTEN_PORT" >&2
  echo "Only $ALLOWED_LISTEN_PORT is allowed for this deployment." >&2
  exit 1
fi

tmp_conf="$(mktemp)"
if [[ -f "$AVAILABLE_PATH" ]]; then
  backup_conf="$(mktemp)"
  cp -a "$AVAILABLE_PATH" "$backup_conf"
fi
trap 'status=$?; if [[ "$status" -ne 0 ]]; then restore_previous_site; fi; rm -f "$tmp_conf" "$backup_conf"; exit "$status"' EXIT
sed \
  -e "s/listen 0.0.0.0:30033;/listen 0.0.0.0:$LISTEN_PORT;/" \
  -e "s#proxy_pass http://127.0.0.1:17666;#proxy_pass $UPSTREAM_URL;#" \
  "$TEMPLATE_PATH" > "$tmp_conf"

install -m 0644 "$tmp_conf" "$AVAILABLE_PATH"
installed_conf=true

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
