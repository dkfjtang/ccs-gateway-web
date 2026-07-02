#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
SCOPE="${CCS_PREFLIGHT_SCOPE:-changed}"

print_section() {
  printf '\n== %s ==\n' "$1"
}

run_check() {
  local name="$1"
  shift

  print_section "$name"
  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    failures=$((failures + 1))
  fi
}

check_git_clean() {
  git status --short
}

changed_files() {
  if [[ "$SCOPE" == "all" ]]; then
    {
      git ls-files
      git ls-files -o --exclude-standard
    } | sort -u
    return
  fi

  {
    git diff --name-only --diff-filter=ACMRTUXB HEAD --
    git ls-files -o --exclude-standard
  } | sort -u
}

check_for_tracked_env_files() {
  local matches
  matches="$(
    changed_files |
      grep -Ei '(^|/)(\.env|\.env\..*|.*secret.*|.*password.*|.*credential.*|.*private.*|id_rsa|id_ed25519|.*\.(pem|p12|pfx|key))$' |
      grep -Ev '(^|/)(\.env\.web|scripts/ccs-secret-preflight\.sh)$' || true
  )"

  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
    printf '\nReview every tracked file above before pushing.\n' >&2
    return 1
  fi
}

check_dockerignore() {
  grep -qxF '.env' .dockerignore
  grep -qxF '.env.*' .dockerignore
  grep -qxF '!.env.web' .dockerignore
  grep -qxF '.git' .dockerignore
  grep -qxF 'node_modules' .dockerignore
  grep -qxF '.codex' .dockerignore
  grep -qxF '.learnings' .dockerignore
  grep -qxF '.serena' .dockerignore
  grep -qxF '.run' .dockerignore
  grep -qxF '.upstream' .dockerignore
  grep -qxF '.worktrees' .dockerignore
  grep -qxF 'tmp' .dockerignore
}

check_sensitive_literals() {
  local files
  files="$(changed_files | grep -Ev '(^|/)(package-lock.json|pnpm-lock.yaml|CHANGELOG.md|scripts/ccs-secret-preflight\.sh|.*\.lock|.*\.(svg|png|jpg|jpeg|ico|icns)|\.env\.web)$' || true)"
  [[ -n "$files" ]] || return 0

  local pattern
  pattern='(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|((AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|aws_secret_access_key|aws_session_token|secretAccessKey|secret_access_key|sessionToken|session_token)[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9/+=_-]{30,}))'

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    local matches
    matches="$(grep -nIE "$pattern" "$file" || true)"
    if [[ -z "$matches" ]]; then
      continue
    fi

    if [[ "$file" == "src-tauri/src/services/s3.rs" ]]; then
      matches="$(
        printf '%s\n' "$matches" |
          grep -Ev 'AKIAIOSFODNN7EXAMPLE|AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE|wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY|TESTSECRET' || true
      )"
    fi

    if [[ "$file" == "deplink.html" ]]; then
      matches="$(
        printf '%s\n' "$matches" |
          grep -Ev 'ctx7sk-4ddd4f66-e752-4022-b1f6-c8cf6279b80d|sk-ant-your-api-key-here|sk-proj-your-api-key-here' || true
      )"
    fi

    if [[ -n "$matches" ]]; then
      printf '%s\n' "$matches"
      return 1
    fi
  done <<< "$files"

  return 0
}

check_large_new_files() {
  local large_files
  large_files="$(
    git ls-files -o --exclude-standard |
      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        size="$(wc -c < "$file")"
        if (( size > 5242880 )); then
          printf '%s %s bytes\n' "$file" "$size"
        fi
      done
  )"

  if [[ -n "$large_files" ]]; then
    printf '%s\n' "$large_files"
    return 1
  fi
}

check_optional_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --source . --no-banner
  else
    printf 'SKIP: gitleaks not installed; regex checks were still executed.\n'
  fi
}

run_check "Git status" check_git_clean
run_check "Env/private filename scan" check_for_tracked_env_files
run_check "Docker context exclusions" check_dockerignore
run_check "Sensitive literal scan" check_sensitive_literals
run_check "Large untracked file scan" check_large_new_files
run_check "Optional gitleaks scan" check_optional_gitleaks

if (( failures > 0 )); then
  printf '\nPreflight failed with %s issue(s). Do not push until reviewed.\n' "$failures" >&2
  exit 1
fi

printf '\nPreflight complete. No blocking issue found by local checks.\n'
