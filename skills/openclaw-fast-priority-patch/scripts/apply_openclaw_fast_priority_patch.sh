#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
CHECK=0
RESTART=0

usage() {
  cat <<'USAGE'
Usage: apply_openclaw_fast_priority_patch.sh [--check] [--dry-run] [--restart] [--no-restart]

Environment:
  OPENCLAW_INSTALL_ROOT  OpenClaw package root. Defaults to ~/.hermes/node/lib/node_modules/openclaw.
  OPENCLAW_NODE          Node executable. Defaults to ~/.hermes/node/bin/node, then node in PATH.

The script patches installed OpenClaw dist files so fastMode=true on openai-responses
adds service_tier=priority for non-official OpenAI-compatible endpoints.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK=1
      DRY_RUN=1
      RESTART=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --restart)
      RESTART=1
      shift
      ;;
    --no-restart)
      RESTART=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[openclaw-fast-priority] %s\n' "$*"
}

fail() {
  printf '[openclaw-fast-priority] ERROR: %s\n' "$*" >&2
  exit 1
}

resolve_node() {
  if [[ -n "${OPENCLAW_NODE:-}" ]]; then
    printf '%s\n' "$OPENCLAW_NODE"
    return
  fi
  if [[ -x "$HOME/.hermes/node/bin/node" ]]; then
    printf '%s\n' "$HOME/.hermes/node/bin/node"
    return
  fi
  command -v node || true
}

check_fail() {
  local status="$1"
  shift
  log "check_status=$status"
  printf '[openclaw-fast-priority] ERROR: %s\n' "$*" >&2
  case "$status" in
    needs_patch)
      exit 1
      ;;
    unsupported_shape)
      exit 2
      ;;
    *)
      exit 1
      ;;
  esac
}

run_wrapper_test() {
  "$NODE_BIN" --input-type=module - "$PROXY_FILE" <<'JS'
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const proxyFile = process.argv[2];
const source = readFileSync(proxyFile, 'utf8');
const exportMatch = source.match(/export \{([^}]+)\};?\s*$/m);
if (!exportMatch) {
  console.error('proxy export block not found');
  process.exit(2);
}
const aliasMatch = exportMatch[1].match(/createOpenAIFastModeWrapper as ([A-Za-z_$][\w$]*)/);
if (!aliasMatch) {
  console.error('createOpenAIFastModeWrapper export alias not found');
  process.exit(2);
}
const module = await import(pathToFileURL(proxyFile).href);
const createOpenAIFastModeWrapper = module[aliasMatch[1]];
if (typeof createOpenAIFastModeWrapper !== 'function') {
  console.error(`exported wrapper is not a function: ${aliasMatch[1]}`);
  process.exit(2);
}

let observed;
const base = (model, context, options) => {
  const payload = { model: model.id, input: [] };
  options?.onPayload?.(payload, model);
  observed = payload;
  return 'ok';
};
const wrapped = createOpenAIFastModeWrapper(base);
wrapped({ provider: 'custom', api: 'openai-responses', id: 'gpt-5.5', baseUrl: 'http://127.0.0.1:15721/v1' }, {}, {});
if (observed?.service_tier !== 'priority') {
  console.error(JSON.stringify(observed));
  process.exit(1);
}
console.log('[openclaw-fast-priority] local_wrapper_test=service_tier:priority');
JS
}

INSTALL_ROOT="${OPENCLAW_INSTALL_ROOT:-$HOME/.hermes/node/lib/node_modules/openclaw}"
NODE_BIN="$(resolve_node)"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    check_fail "unsupported_shape" "Node executable not found. Set OPENCLAW_NODE."
  fi
  fail "Node executable not found. Set OPENCLAW_NODE."
fi
if [[ ! -d "$INSTALL_ROOT/dist" ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    check_fail "unsupported_shape" "OpenClaw dist directory not found: $INSTALL_ROOT/dist"
  fi
  fail "OpenClaw dist directory not found: $INSTALL_ROOT/dist"
fi
if [[ ! -f "$INSTALL_ROOT/package.json" ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    check_fail "unsupported_shape" "OpenClaw package.json not found: $INSTALL_ROOT/package.json"
  fi
  fail "OpenClaw package.json not found: $INSTALL_ROOT/package.json"
fi

VERSION="$("$NODE_BIN" -e "const p=require(process.argv[1]); console.log(p.version||'unknown')" "$INSTALL_ROOT/package.json")"
log "install_root=$INSTALL_ROOT"
log "node=$NODE_BIN"
log "openclaw_version=$VERSION"

PROXY_FILE="$(grep -RIl --include='*.js' 'function createOpenAIFastModeWrapper' "$INSTALL_ROOT/dist" | head -n 1 || true)"
EXTRA_FILE="$(grep -RIl --include='*.js' 'function applyPostPluginStreamWrappers' "$INSTALL_ROOT/dist" | head -n 1 || true)"

if [[ -z "$PROXY_FILE" ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    check_fail "unsupported_shape" "Could not locate proxy stream wrapper dist file."
  fi
  fail "Could not locate proxy stream wrapper dist file."
fi
if [[ -z "$EXTRA_FILE" ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    check_fail "unsupported_shape" "Could not locate extra params dist file."
  fi
  fail "Could not locate extra params dist file."
fi

log "proxy_file=$PROXY_FILE"
log "extra_file=$EXTRA_FILE"

if [[ "$CHECK" -eq 1 ]]; then
  "$NODE_BIN" --check "$PROXY_FILE" || check_fail "unsupported_shape" "node --check failed for proxy file: $PROXY_FILE"
  "$NODE_BIN" --check "$EXTRA_FILE" || check_fail "unsupported_shape" "node --check failed for extra params file: $EXTRA_FILE"
else
  "$NODE_BIN" --check "$PROXY_FILE"
  "$NODE_BIN" --check "$EXTRA_FILE"
fi

PATCHED=0
if grep -q 'function shouldApplyOpenAIFastModeServiceTier' "$PROXY_FILE" \
  && grep -q 'resolveOpenAIFastMode(ctx.effectiveExtraParams)' "$EXTRA_FILE"; then
  PATCHED=1
fi

if [[ "$CHECK" -eq 1 ]]; then
  log "check only; no files will be modified"
  if [[ "$PATCHED" -ne 1 ]]; then
    log "check_status=needs_patch"
    exit 1
  fi
  run_wrapper_test || {
    log "check_status=unsupported_shape"
    exit 2
  }
  log "check_status=ok"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run only; no files will be modified"
  if [[ "$PATCHED" -eq 1 ]]; then
    log "dry_run_status=already_patched"
  else
    log "dry_run_status=patch_needed"
  fi
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  export PROXY_FILE EXTRA_FILE NODE_BIN
  python3 - <<'PY'
from pathlib import Path
from datetime import datetime
import os
import re
import shutil
import subprocess

proxy = Path(os.environ["PROXY_FILE"])
extra = Path(os.environ["EXTRA_FILE"])
node = os.environ["NODE_BIN"]
stamp = datetime.now().strftime("%Y%m%d%H%M%S")

def backup(path: Path) -> Path:
    dst = path.with_name(path.name + f".bak-openclaw-fast-priority-{stamp}")
    shutil.copy2(path, dst)
    print(f"[openclaw-fast-priority] backup={dst}")
    return dst

def patch_proxy(path: Path):
    s = path.read_text(encoding="utf-8")
    changed = False
    if "function shouldApplyOpenAIFastModeServiceTier" not in s:
        old = '''function applyOpenAIFastModePayloadOverrides(params) {\n\tif (params.payloadObj.service_tier === void 0 && shouldApplyOpenAIServiceTier(params.model)) params.payloadObj.service_tier = "priority";\n}\n'''
        new = '''function shouldApplyOpenAIFastModeServiceTier(model) {\n\tconst api = normalizeOptionalLowercaseString(model.api);\n\treturn api === "openai-responses" || api === "openai-codex-responses" || shouldApplyOpenAIServiceTier(model);\n}\nfunction applyOpenAIFastModePayloadOverrides(params) {\n\tif (params.payloadObj.service_tier === void 0 && shouldApplyOpenAIFastModeServiceTier(params.model)) params.payloadObj.service_tier = "priority";\n}\n'''
        if old not in s:
            raise SystemExit(f"proxy patch target not found: {path}")
        s = s.replace(old, new, 1)
        changed = True
    old = '''\treturn (model, context, options) => {\n\t\tif (model.api !== "openai-responses" && model.api !== "openai-codex-responses" && model.api !== "azure-openai-responses" || model.provider !== "openai" && model.provider !== "openai-codex") return underlying(model, context, options);\n\t\tconst originalOnPayload = options?.onPayload;\n'''
    if old in s:
        new = '''\treturn (model, context, options) => {\n\t\tconst api = normalizeOptionalLowercaseString(model.api);\n\t\tif (api !== "openai-responses" && api !== "openai-codex-responses") return underlying(model, context, options);\n\t\tconst originalOnPayload = options?.onPayload;\n'''
        s = s.replace(old, new, 1)
        changed = True
    else:
        old = '''\treturn (model, context, options) => {\n\t\tif (!shouldApplyOpenAIServiceTier(model)) return underlying(model, context, options);\n\t\tconst originalOnPayload = options?.onPayload;\n'''
        if old in s:
            new = '''\treturn (model, context, options) => {\n\t\tconst api = normalizeOptionalLowercaseString(model.api);\n\t\tif (api !== "openai-responses" && api !== "openai-codex-responses" && !shouldApplyOpenAIServiceTier(model)) return underlying(model, context, options);\n\t\tconst originalOnPayload = options?.onPayload;\n'''
            s = s.replace(old, new, 1)
            changed = True
    if 'const api = normalizeOptionalLowercaseString(model.api);' not in s:
        raise SystemExit(f"fast wrapper condition target not found: {path}")
    if changed:
        backup(path)
        path.write_text(s, encoding="utf-8")
        print(f"[openclaw-fast-priority] patched={path}")
    else:
        print(f"[openclaw-fast-priority] already_patched={path}")

def patch_extra(path: Path):
    s = path.read_text(encoding="utf-8")
    changed = False
    proxy_s = proxy.read_text(encoding="utf-8")
    export_match = re.search(r'export \{([^}]+)\};?\s*$', proxy_s, re.M)
    if not export_match:
        raise SystemExit(f"proxy export block not found: {proxy}")
    def alias_for(name: str) -> str:
        match = re.search(rf'{re.escape(name)} as ([A-Za-z_$][\w$]*)', export_match.group(1))
        if not match:
            raise SystemExit(f"proxy export alias not found for {name}: {proxy}")
        return match.group(1)
    resolve_alias = alias_for("resolveOpenAIFastMode")
    fast_wrapper_alias = alias_for("createOpenAIFastModeWrapper")
    import_block = "\n".join(s.splitlines()[:12])
    if "resolveOpenAIFastMode" not in import_block or "createOpenAIFastModeWrapper" not in import_block:
        pattern = re.compile(r'import \{ ([^}]*) \} from "(\./proxy-stream-wrappers-[^"]+\.js)";\n')
        match = pattern.search(s)
        if not match:
            raise SystemExit(f"extra import target not found: {path}")
        imports, module_path = match.groups()
        existing = [
            item.strip()
            for item in imports.split(",")
            if item.strip()
            and " as resolveOpenAIFastMode" not in item
            and " as createOpenAIFastModeWrapper" not in item
        ]
        new_imports = ", ".join(
            [f"{resolve_alias} as resolveOpenAIFastMode", *existing, f"{fast_wrapper_alias} as createOpenAIFastModeWrapper"]
        )
        s = s[:match.start()] + f'import {{ {new_imports} }} from "{module_path}";\n' + s[match.end():]
        changed = True
    marker = "if (resolveOpenAIFastMode(ctx.effectiveExtraParams)) ctx.agent.streamFn = createOpenAIFastModeWrapper(ctx.agent.streamFn);"
    if marker not in s:
        old = '''\tif (!ctx.providerWrapperHandled) {\n\t\tctx.agent.streamFn = createDeepSeekV4OpenAICompatibleThinkingWrapper({\n'''
        if old not in s:
            raise SystemExit(f"extra wrapper insertion target not found: {path}")
        new = f'''\t{marker}\n\tif (!ctx.providerWrapperHandled) {{\n\t\tctx.agent.streamFn = createDeepSeekV4OpenAICompatibleThinkingWrapper({{\n'''
        s = s.replace(old, new, 1)
        changed = True
    if changed:
        backup(path)
        path.write_text(s, encoding="utf-8")
        print(f"[openclaw-fast-priority] patched={path}")
    else:
        print(f"[openclaw-fast-priority] already_patched={path}")

patch_proxy(proxy)
patch_extra(extra)
subprocess.check_call([node, "--check", str(proxy)])
subprocess.check_call([node, "--check", str(extra)])
PY
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  run_wrapper_test
else
  log "local wrapper test skipped in dry run"
fi

if [[ "$RESTART" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
  if systemctl --user list-unit-files openclaw-gateway.service >/dev/null 2>&1; then
    log "restarting openclaw-gateway.service"
    systemctl --user restart openclaw-gateway.service
    sleep 1
    systemctl --user is-active openclaw-gateway.service
  else
    log "openclaw-gateway.service not found under systemctl --user; restart OpenClaw manually"
  fi
else
  log "restart skipped"
fi

log "done"
