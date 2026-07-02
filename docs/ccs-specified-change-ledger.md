# CCS Specified Change Ledger

This ledger records fork-specific changes that were explicitly requested during official upstream alignment. Use it before treating a difference from official `farion1231/cc-switch` as a regression.

## Current Alignment Target

- Official baseline: `farion1231/cc-switch` `v3.16.3`.
- Fork release version: `3.16.3-ccs-gateway.1`.
- Official source reference: `.upstream/cc-switch-v3.16.3` and `.upstream/cc-switch-v3.16.3.zip` remain local-only references and must not be tracked.

## Fixed Review Rulings

| ID | Area | Fixed ruling | Review implication | Evidence |
| --- | --- | --- | --- | --- |
| S-001 | Usage dashboard refresh | The default Usage Dashboard auto-refresh interval is `30000` ms. | Do not flag the 30s default as a regression from the previous 5s behavior; tests must assert 30s. | `src/components/usage/UsageDashboard.tsx`, `tests/components/UsageDashboard.test.tsx` |
| S-002 | Codex session history migration | The official `v3.16.3` Codex unified session history migration is intentionally not implemented in this fork. | Do not add the official history rewrite as part of routine upstream alignment. Any broader Codex history rewrite needs a separate opt-in migration project. | `docs/ccs-official-upstream-migration.md`, `docs/ccs-local-change-groups.md` |
| S-003 | Desktop updater channel | Fork desktop builds must use the fork release channel, not official `farion1231/cc-switch` updater artifacts. | Do not replace the fork updater endpoint with the official upstream endpoint during version alignment. | `src-tauri/tauri.conf.json`, `scripts/verify-official-upstream-alignment.ps1` |
| S-004 | Local overlays | Existing fork overlays remain product behavior unless explicitly retired: Token Saver, Responses stickiness, service tier priority forwarding, managed-account guards, local Web/server compatibility, local WSL publish flow, and usage event display. | Do not overwrite local overlays with official files without preserving or deliberately retiring the overlay and updating this ledger. | `docs/ccs-fork-overlay-ledger.md`, `scripts/verify-local-overlays.ps1` |
| S-005 | Usage accounting alignment | `pricing_model` is part of the local accounting contract for request logs, daily rollups, and usage stats. Cache token pricing must respect app-type semantics. | Do not collapse usage aggregation back to only `model` or remove app-specific cache token handling. | `src-tauri/src/proxy/usage/calculator.rs`, `src-tauri/src/proxy/usage/logger.rs`, `src-tauri/src/database/dao/usage_rollup.rs`, `src-tauri/src/services/usage_stats.rs` |
| S-006 | Usage dashboard scope | Usage Dashboard supports global app/provider/model filters and keeps local usage display behavior for Codex, Gemini, OpenCode, Claude Desktop, and related dashboards. | Do not treat provider/model filters, provider-name display folding, quota USD display, or configurable polling as accidental divergence. | `src/components/usage/UsageDashboard.tsx`, `src/lib/query/usage.ts`, `src/types/usage.ts` |
| S-007 | Custom User-Agent | Provider-level custom User-Agent is a fork feature for local proxy/model-fetch/stream-check compatibility. Official fingerprints must remain protected where required. | Review custom User-Agent changes against both compatibility and official-client fingerprint preservation. | `src-tauri/src/provider.rs`, `src-tauri/src/proxy/forwarder.rs`, `src-tauri/src/services/model_fetch.rs`, `src-tauri/src/services/stream_check.rs` |
| S-008 | About/updater/health safe subset | Do not overwrite local `AboutSection` or updater wrapper wholesale with official UI/runtime code. The updater wrapper must preserve the install handle consumed by `UpdateContext`; health remains unchanged unless official/local behavior diverges. | Treat official About/updater/health changes as selective migrations, not full-file replacement. | `tests/lib/updater.test.ts`, `src/lib/updater.ts`, `src/contexts/UpdateContext.tsx` |
| S-009 | Local proxy environment privacy | Local operator proxy environment values are machine-local release inputs, not repository state. Public files may use placeholders or runtime variables, but must not hard-code concrete `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` values such as host-specific `:7890` endpoints. | Keep local proxy preservation in ignored local compose/runtime configuration. Run `scripts/ccs-secret-preflight.sh` before publishing changes; do not record real proxy endpoints in docs, scripts, tests, or release notes. | `scripts/ccs-secret-preflight.sh`, `AGENTS.md`, `docker-compose.ccs-web.yml` |
| S-010 | Content-encoding expansion gate | Current slim mainline intentionally supports decoded non-streaming upstream responses for gzip, deflate, and brotli, including zlib-wrapped deflate fallback. Broader request-body/error-body/multi-layer/zstd content-encoding support is not a cleanup change. | Do not import historical `content_encoding.rs` or related broad hunks as part of stash cleanup or routine upstream alignment. Treat it as a separate feature branch requiring handler, forwarder, response-processor, error-body, request-size, and streaming-regression tests. | `src-tauri/src/proxy/response_processor.rs`, `src-tauri/src/proxy/handlers.rs`, `src-tauri/src/proxy/forwarder.rs` |

## Review Checklist

Before claiming official alignment is ready:

1. Confirm every intentional divergence above is still documented here.
2. Confirm `scripts/verify-official-upstream-alignment.ps1` and `scripts/verify-local-overlays.ps1` still protect the relevant high-risk rulings.
3. If a future upstream version implements the same behavior differently, compare behavior first and only remove a local ruling after updating this ledger.
4. If a ruling is retired, record the replacement behavior and the validation command in the same change.
