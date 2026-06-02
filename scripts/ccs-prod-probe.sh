#!/usr/bin/env bash

set -euo pipefail

TARGET_NAME="${CCS_TARGET_NAME:-local}"
WEB_BASE_URL="${CCS_WEB_BASE_URL:-http://127.0.0.1:17666}"
PROXY_BASE_URL="${CCS_PROXY_BASE_URL:-http://127.0.0.1:15721}"
NGINX_BASE_URL="${CCS_NGINX_BASE_URL:-}"
CONTAINER_NAME="${CCS_CONTAINER_NAME:-ccs-gateway-web}"
TAIL_LINES="${CCS_LOG_TAIL_LINES:-120}"
TIMEOUT="${CCS_CURL_TIMEOUT:-5}"
SKIP_PROXY="${CCS_SKIP_PROXY:-false}"
REQUIRE_AUTH="${CCS_REQUIRE_AUTH:-false}"

print_section() {
  printf '\n== %s ==\n' "$1"
}

curl_status() {
  local url="$1"
  curl -sS --max-time "$TIMEOUT" -o /tmp/ccs-probe-body.txt -w '%{http_code}' "$url"
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

print_section "Target"
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
    -o /tmp/ccs-probe-unauth.txt \
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
  printf '\nRecent logs for %s:\n' "$CONTAINER_NAME"
  docker logs --tail "$TAIL_LINES" "$CONTAINER_NAME" 2>&1 || true
else
  printf 'docker not found on this host\n'
fi

print_section "Listening Ports"
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E ':(17666|15721|30034)\b' || true
else
  netstat -ltnp 2>/dev/null | grep -E ':(17666|15721|30034)\b' || true
fi
