# CCS Gateway Web Local Change Groups

This file groups the current dirty worktree into release/review buckets. Keep it updated before staging, committing, or rebasing onto a newer `ccs-web` fork baseline.

## Group 1 - Fork Overlay Governance

Purpose: make local overlays auditable and repeatable before future `ccs-web` / official CC Switch upgrades.

Files:

- `docs/ccs-fork-overlay-ledger.md`
- `docs/ccs-local-change-groups.md`
- `scripts/verify-local-overlays.ps1`
- `docs/session-summaries/*`

Validation:

- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1`

## Group 2 - Token Saver / TokenFilterEngine

Purpose: request-side safe text compaction and aggregate-only observability.

Files:

- `src-tauri/src/proxy/forwarder.rs`
- `src-tauri/src/proxy/token_saver.rs`
- `src-tauri/src/proxy/token_filter_engine.rs`
- `src-tauri/src/proxy/body_filter.rs`
- `src-tauri/src/proxy/types.rs`
- `src-tauri/fixtures/token-cost-savers/*`
- `docs/ccs-token-cost-saver-patch.md`
- `docs/ccs-9router-upgrade-spec.md`
- `scripts/verify-token-cost-savers.ps1`
- `scripts/report-token-saver-usage.ps1`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml token_saver --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml token_filter_engine --lib`
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-token-cost-savers.ps1`

## Group 3 - Caveman Prompt Profiles

Purpose: Lite / Full / Ultra prompt-level profiles without proxy response rewriting.

Files:

- `src-tauri/src/commands/prompt.rs`
- `src-tauri/src/prompt.rs`
- `src-tauri/src/services/prompt.rs`
- `src/components/prompts/PromptPanel.tsx`
- `tests/components/PromptPanel.test.tsx`
- `tests/components/PromptPanel.integration.test.tsx`
- `docs/ccs-caveman-source-audit.md`
- `docs/ccs-caveman-release-readiness.md`
- `scripts/verify-caveman-*.ps1`
- `scripts/new-caveman-*.ps1`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml caveman --lib`
- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/components/PromptPanel.test.tsx"`
- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/components/PromptPanel.integration.test.tsx"`
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1`

## Group 4 - Responses Stickiness / Service Tier / OpenClaw Integration

Purpose: keep long Codex Responses continuations provider-bound and preserve / inject `service_tier=priority` where configured.

Current dirty files:

- `src-tauri/src/provider.rs`
- `src-tauri/src/proxy/forwarder.rs`
- `src-tauri/src/session_manager/providers/openclaw.rs`
- `skills/openclaw-fast-priority-patch/*`

Related regression-watch entry points:

- `src-tauri/src/proxy/providers/claude.rs`
- `src-tauri/src/proxy/providers/transform_responses.rs`
- `src-tauri/src/proxy/response_processor.rs`
- `src-tauri/src/proxy/server.rs`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml service_tier --lib`
- `rtk wsl.exe -d Ubuntu-24.04 -- bash -lc 'cd /mnt/f/development/ccs-gateway-web && skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --check'`

## Group 5 - Docker Web / Production Runtime

Purpose: production-safe Web/API + proxy deployment with loopback-bound ports, auth, secret preflight, and reusable probes.

Current dirty files:

- `.dockerignore`
- `.gitignore`
- `docker-compose.ccs-web.yml`
- `crates/server/Cargo.lock`
- `docs/ccs-release-observability-plan.md`
- `scripts/ccs-prod-probe.sh`
- `scripts/ccs-secret-preflight.sh`

Related regression-watch entry points:

- `Dockerfile.web`
- `docs/ccs-production-runbook.md`

Validation:

- `rtk wsl.exe -d Ubuntu-24.04 -- bash -lc 'cd /mnt/f/development/ccs-gateway-web && ./scripts/ccs-secret-preflight.sh'`
- local Docker build and smoke per `docs/ccs-release-observability-plan.md`

## Group 6 - Version Metadata

Purpose: make the fork baseline explicit instead of leaving stale `3.14.1` runtime package metadata.

Files:

- `package.json`
- `package-lock.json`
- `src-tauri/Cargo.toml`
- `src-tauri/Cargo.lock`
- `src-tauri/tauri.conf.json`

Current fork version policy:

- Base version: `3.15.0`
- Fork suffix: `ccs-gateway`
- Patch counter: increment the numeric suffix for local overlay release candidates
- Current value: `3.15.0-ccs-gateway.1`

## Staging Guidance

Stage and review these groups separately. Avoid mixing Group 5 production runtime edits with Group 2/3 proxy and prompt logic unless a release explicitly requires both.
