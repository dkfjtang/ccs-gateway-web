# 2026-05-29 - Token Saver / Caveman Production Release

## Key Information

- Workspace: `<repo-root>`.
- User asked to evaluate and deploy token-saving features in an overlay/patch style so future `ccs-web` upgrades do not require a broad reimplementation.
- Local test environment designated by user:
  - Web/API: `http://127.0.0.1:17666`
  - Proxy: `http://127.0.0.1:15721`
  - Container used during local validation: `ccs-gateway-web-usage-status-filter-test`
  - Local test image after publish: `ccs-gateway-web:<tag>-<timestamp>`
- Production targets:
  - `<host-a>`: `<ssh-user>@<host-a>:<ssh-port>`
  - `<host-b>`: `<ssh-user>@<host-b>:<ssh-port>`
  - SSH passwords were used only through host-specific environment variable names. No secret values were stored.

## Implementation / Behavior Decisions

- Token Saver remains an explicit optimizer-controlled feature. It is enabled in tested environments with:
  - `tokenSaver: true`
  - `tokenSaverMinChars: 4000`
  - `tokenSaverKeepChars: 800`
  - `cavemanOutputCompression: false`
- Caveman is intentionally not wired into proxy runtime. It remains prompt/profile-only or reserved; runtime response rewriting is disabled.
- Token Saver is implemented as a small overlay with a single normal hot-path hook:
  - `src-tauri/src/proxy/forwarder.rs`: `token_saver::optimize(&mut request_body, &optimizer_config)`
  - Main logic stays in `src-tauri/src/proxy/token_saver.rs` and `src-tauri/src/proxy/token_filter_engine.rs`.
- Safety rules verified in tests: do not compress user input, assistant replies, error tool outputs, structured object results, JSON-looking tool outputs, git diff, or unknown long text. Only safe long tool/function output classes may be compacted.

## Verification Results

- Local runtime verification on `127.0.0.1:15721` confirmed recent Codex requests used provider `<provider-name>` and returned HTTP 200.
- Local optimizer config showed Token Saver on and Caveman off.
- Automated local gates passed:
  - `scripts\verify-token-cost-savers.ps1`
  - `npm run typecheck`
  - `scripts/ccs-secret-preflight.sh` after adding WSL safe.directory for `<repo-root-wsl>`
- `verify-token-cost-savers.ps1` covered:
  - `token_saver` tests: 22 passed
  - `token_filter_engine` tests: 12 passed
  - `caveman` prompt tests: 2 passed
  - static check that Caveman is not wired into proxy runtime
  - static check that Token Saver has exactly one forwarder hook

## Production Release Result

- Source tarball for remote builds:
  - `<repo-root>\.run\release\ccs-gateway-web-<artifact>-<timestamp>`
  - Size: `17221249` bytes
  - File-only tar packaging excluded `.git`, `node_modules`, `target`, `dist`, `.run`, `.env*` except `.env.web`.
- New production image tag on both hosts:
  - `ccs-gateway-web:<tag>-<timestamp>`
- Both hosts built the image remotely from the tarball.
- Final production container runtime contract preserved:
  - container name: `ccs-gateway-web`
  - command: `/usr/local/bin/cc-switch-web`
  - ports: `127.0.0.1:17666:17666`, `127.0.0.1:15721:15721`
  - mounts: `/root/.openclaw:/root/.openclaw:ro`, `/root/.cc-switch:/root/.cc-switch`
  - restart policy: `unless-stopped`
  - env retained from old container: `CC_SWITCH_START_PROXY=true`, `CC_SWITCH_HOST=0.0.0.0`, `CC_SWITCH_PORT=17666`, `CC_SWITCH_AUTO_PORT=false`, `RUST_LOG=cc_switch_server=info,tower_http=info`
- Network preserved per host:
  - `<host-a>`: `ccs-gateway-web_default`
  - `<host-b>`: `bridge`

## Production Validation Evidence

- `<host-a>` final checks:
  - Web health: `200`
  - Proxy status: `200`
  - NGINX health: `200`
  - NGINX `/.env`: `404`
  - Auth enabled: `true`
  - unauthenticated `get_settings`: `401`
  - current image: `ccs-gateway-web:<tag>-<timestamp>`
  - rollback container: `ccs-gateway-web-backup-before-<reason>-<timestamp>`
  - rollback image: `ccs-gateway-web:<tag>-<timestamp>`
  - `/root/.cc-switch/cc-switch.db` optimizer_config confirmed Token Saver on and Caveman off.
- `<host-b>` final checks:
  - Web health: `200`
  - Proxy status: `200`
  - NGINX health: `200`
  - NGINX `/.env`: `404`
  - Auth enabled: `true`
  - unauthenticated `get_settings`: `401`
  - current image: `ccs-gateway-web:<tag>-<timestamp>`
  - rollback container: `ccs-gateway-web-backup-before-<reason>-<timestamp>`
  - rollback image: `ccs-gateway-web:<tag>-<timestamp>`
  - `/root/.cc-switch/cc-switch.db` optimizer_config confirmed Token Saver on and Caveman off.
- Production DB continuity was checked by reading table counts from `/root/.cc-switch/cc-switch.db`; provider/config/log tables were not empty.
- Recent production logs after release had no `error`, `panic`, permission, failed/refused/reset hits in the scanned window.
- OpenClaw gateway service was `active` on both hosts.

## Incident / Lesson

- First production deploy attempt on `<host-a>` started a new container without copying old container env. Web health returned `200`, but proxy status on `15721` stayed unavailable because `CC_SWITCH_START_PROXY=true` was missing. The deploy script automatically rolled back to the previous container.
- Fix: production replacement must inherit the original container env, not only ports/mounts/network/restart/cmd. `CC_SWITCH_START_PROXY=true` is required for the production proxy port.
- Future deploy automation must treat env as part of the runtime contract and should fail before replacement if expected env is missing.

## Independent Review / Test Notes

- `review-assistant` initially flagged missing evidence for persistence, rollback readiness, and production feature smoke. Those were addressed by DB reads, rollback container/image checks, and production config/log/request-log checks.
- `test-assistant` classified the deployment as production基础验收通过 but not full business E2E validation until the user tests real OpenClaw business calls.

## Follow-ups

- User should continue real OpenClaw production business-path testing.
- Consider turning the release process into a maintained deploy script that:
  - reads original container env/ports/mounts/network/restart/cmd from `docker inspect`,
  - builds from a filtered tarball,
  - creates a named rollback container,
  - performs health/auth/NGINX/persistence checks,
  - never logs credential values.
- Consider adding non-sensitive compression-hit metadata if future cost-saving proof needs per-request Token Saver hit evidence. Do not log request bodies or secrets.

## Dropped Noise

- Raw Docker build dependency download logs, long asset manifests, repeated progress updates, PowerShell quoting mistakes without durable lesson, and all credential values were intentionally not preserved.
