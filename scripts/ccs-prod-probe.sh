#!/usr/bin/env bash

set -euo pipefail

TARGET_NAME="${CCS_TARGET_NAME:-local}"
WEB_BASE_URL="${CCS_WEB_BASE_URL:-http://127.0.0.1:17666}"
PROXY_BASE_URL="${CCS_PROXY_BASE_URL:-http://127.0.0.1:15721}"
DEFAULT_NGINX_BASE_URL="http://127.0.0.1:30033"
NGINX_BASE_URL="${CCS_NGINX_BASE_URL:-}"
REQUIRE_NGINX="${CCS_REQUIRE_NGINX:-false}"
REQUIRE_CONTAINER_NO_NGINX="${CCS_REQUIRE_CONTAINER_NO_NGINX:-true}"
CONTAINER_NAME="${CCS_CONTAINER_NAME:-ccs-gateway-web}"
TAIL_LINES="${CCS_LOG_TAIL_LINES:-120}"
TIMEOUT="${CCS_CURL_TIMEOUT:-5}"
SKIP_PROXY="${CCS_SKIP_PROXY:-false}"
REQUIRE_AUTH="${CCS_REQUIRE_AUTH:-false}"
PROBE_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_TMP_DIR"' EXIT

print_section() {
  printf '\n== %s ==\n' "$1"
}

curl_status() {
  local url="$1"
  curl -sS --max-time "$TIMEOUT" -o "$PROBE_TMP_DIR/body.txt" -w '%{http_code}' "$url"
}

probe_url() {
  local label="$1"
  local url="$2"
  local expected="${3:-200}"
  local code

  printf '%-28s %s\n' "$label" "$url"
  if code="$(curl_status "$url")"; then
    printf 'HTTP %s\n' "$code"
    if [[ "$expected" != "any" && "$code" != "$expected" ]]; then
      printf 'Expected HTTP %s, got %s\n' "$expected" "$code" >&2
      return 1
    fi
  else
    printf 'Request failed\n' >&2
    return 1
  fi
}

url_port() {
  local url="$1"
  local host_port
  local port

  if [[ "$url" != http://* && "$url" != https://* ]]; then
    printf 'Unsupported URL scheme: %s\n' "$url" >&2
    return 1
  fi

  host_port="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/]+).*#\1#')"
  if [[ "$host_port" =~ ^\[.*\]:(.*)$ ]]; then
    port="${BASH_REMATCH[1]}"
  elif [[ "$host_port" =~ ^\[.*\]$ ]]; then
    if [[ "$url" == https://* ]]; then
      port="443"
    else
      port="80"
    fi
  elif [[ "$host_port" == *:* ]]; then
    port="${host_port##*:}"
  elif [[ "$url" == https://* ]]; then
    port="443"
  else
    port="80"
  fi

  if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
    printf 'Invalid port parsed from URL: %s\n' "$url" >&2
    return 1
  fi

  printf '%s\n' "$port"
}

has_listener() {
  local address_kind="$1"
  local port="$2"
  local patterns=()
  local pattern

  case "$address_kind" in
    any4)
      patterns=("0\\.0\\.0\\.0:${port}" "\\*:${port}")
      ;;
    loopback4)
      patterns=("127\\.0\\.0\\.1:${port}")
      ;;
    any6)
      patterns=("\\[::\\]:${port}" "::+:${port}")
      ;;
    *)
      printf 'Unknown listener address kind: %s\n' "$address_kind" >&2
      return 1
      ;;
  esac

  for pattern in "${patterns[@]}"; do
    if printf '%s\n' "$listening_ports" | grep -Eq "(^|[[:space:]])${pattern}([[:space:]]|$)"; then
      return 0
    fi
  done

  return 1
}

print_section "Target"
if [[ "$REQUIRE_NGINX" == "true" && -z "$NGINX_BASE_URL" ]]; then
  NGINX_BASE_URL="$DEFAULT_NGINX_BASE_URL"
fi

printf 'name=%s\n' "$TARGET_NAME"
printf 'web=%s\n' "$WEB_BASE_URL"
if [[ "$SKIP_PROXY" != "true" ]]; then
  printf 'proxy=%s\n' "$PROXY_BASE_URL"
else
  printf 'proxy=skipped\n'
fi
if [[ -n "$NGINX_BASE_URL" ]]; then
  printf 'nginx=%s\n' "$NGINX_BASE_URL"
fi

print_section "Health"
probe_url "Web health" "$WEB_BASE_URL/health" "200"
if [[ "$SKIP_PROXY" != "true" ]]; then
  probe_url "Proxy status" "$PROXY_BASE_URL/status" "200"
else
  printf 'Proxy status skipped because CCS_SKIP_PROXY=true\n'
fi
if [[ -n "$NGINX_BASE_URL" ]]; then
  probe_url "NGINX health" "$NGINX_BASE_URL/health" "200"
  probe_url "NGINX env guard" "$NGINX_BASE_URL/.env" "404"
  probe_url "NGINX env variant guard" "$NGINX_BASE_URL/.env.web" "404"
  probe_url "NGINX hidden file guard" "$NGINX_BASE_URL/.git/config" "404"
  probe_url "NGINX well-known passthrough" "$NGINX_BASE_URL/.well-known/ccs-probe" "200"
fi

print_section "Auth Boundary"
auth_status="$(curl -sS --max-time "$TIMEOUT" \
  -H 'Content-Type: application/json' \
  -X POST "$WEB_BASE_URL/api/invoke" \
  -d '{"command":"auth.status","payload":{}}' || true)"
printf '%s\n' "$auth_status"

if [[ "$REQUIRE_AUTH" == "true" && "$auth_status" != *'"enabled":true'* ]]; then
  printf 'Web Auth is required but auth.status did not report enabled=true\n' >&2
  exit 1
fi

unauth_code="$(
  curl -sS --max-time "$TIMEOUT" \
    -H 'Content-Type: application/json' \
    -o "$PROBE_TMP_DIR/unauth.txt" \
    -w '%{http_code}' \
    -X POST "$WEB_BASE_URL/api/invoke" \
    -d '{"command":"get_settings","payload":{}}' || true
)"
printf 'Unauthenticated get_settings HTTP %s\n' "$unauth_code"

if [[ "$REQUIRE_AUTH" == "true" && "$unauth_code" != "401" ]]; then
  printf 'Web Auth is required but unauthenticated get_settings returned HTTP %s\n' "$unauth_code" >&2
  exit 1
fi

print_section "Container"
if command -v docker >/dev/null 2>&1; then
  docker ps --filter "name=$CONTAINER_NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
  if [[ "$REQUIRE_CONTAINER_NO_NGINX" == "true" ]]; then
    if ! container_processes="$(docker top "$CONTAINER_NAME" 2>/dev/null)"; then
      printf 'Cannot inspect container processes for %s\n' "$CONTAINER_NAME" >&2
      exit 1
    fi
    if printf '%s\n' "$container_processes" | grep -Eq '(^|[[:space:]/])nginx([[:space:]]|$)'; then
      printf 'Container %s must not run nginx, but nginx was found in process list\n' "$CONTAINER_NAME" >&2
      exit 1
    fi
  fi
  printf '\nRecent logs for %s:\n' "$CONTAINER_NAME"
  docker logs --tail "$TAIL_LINES" "$CONTAINER_NAME" 2>&1 || true
else
  printf 'docker not found on this host\n'
fi

print_section "Listening Ports"
if command -v ss >/dev/null 2>&1; then
  listening_ports="$(ss -ltnp || true)"
  printf '%s\n' "$listening_ports" | grep -E ':(17666|15721|30033)\b' || true
else
  listening_ports="$(netstat -ltnp 2>/dev/null || true)"
  printf '%s\n' "$listening_ports" | grep -E ':(17666|15721|30033)\b' || true
fi

if [[ "$REQUIRE_NGINX" == "true" ]]; then
  nginx_port="$(url_port "$NGINX_BASE_URL")"
  if ! has_listener any4 "$nginx_port"; then
    printf 'NGINX is required but 0.0.0.0:%s is not listening\n' "$nginx_port" >&2
    exit 1
  fi
  if has_listener any6 "$nginx_port"; then
    printf 'NGINX IPv6 listener [::]:%s is not allowed for this deployment\n' "$nginx_port" >&2
    exit 1
  fi

  web_port="$(url_port "$WEB_BASE_URL")"
  if ! has_listener loopback4 "$web_port"; then
    printf 'Web port must listen on 127.0.0.1:%s\n' "$web_port" >&2
    exit 1
  fi
  if has_listener any4 "$web_port"; then
    printf 'Web port must not listen on 0.0.0.0:%s\n' "$web_port" >&2
    exit 1
  fi

  if [[ "$SKIP_PROXY" != "true" ]]; then
    proxy_port="$(url_port "$PROXY_BASE_URL")"
    if ! has_listener loopback4 "$proxy_port"; then
      printf 'Proxy port must listen on 127.0.0.1:%s\n' "$proxy_port" >&2
      exit 1
    fi
    if has_listener any4 "$proxy_port"; then
      printf 'Proxy port must not listen on 0.0.0.0:%s\n' "$proxy_port" >&2
      exit 1
    fi
  fi
fi
