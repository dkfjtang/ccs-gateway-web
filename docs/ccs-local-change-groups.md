# CCS Gateway Web Local Change Groups

This file groups the current dirty worktree into release/review buckets. Keep it updated before staging, committing, or rebasing onto a newer official `farion1231/cc-switch` baseline.

## Group 1 - Fork Overlay Governance

Purpose: make official `farion1231/cc-switch` the primary upstream and keep local overlays auditable before future CC Switch upgrades. `ccs-web` is now an auxiliary reference, not the primary upstream.

Files:

- `docs/ccs-fork-overlay-ledger.md`
- `docs/ccs-local-change-groups.md`
- `docs/ccs-official-upstream-migration.md`
- `scripts/verify-official-upstream-alignment.ps1`
- `scripts/verify-local-overlays.ps1`
- `docs/session-summaries/*`

Related regression-watch entry points:

- `skills/cc-switch-release/*`
- active user entry links in `README.md`, `SUPPORT.md`, `SECURITY.md`, `CONTRIBUTING.md`, `docs/user-manual/**`, and Flatpak metadata

Validation:

- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1`
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1`

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
- `src-tauri/src/services/provider/mod.rs`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml service_tier --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml update_current_claude_provider_syncs_live_when_proxy_takeover_detected_without_backup --lib`
- `rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --check'`

## Group 5 - Official 3.16.2 Core Backend

Purpose: align with official CC Switch `v3.16.2` backend behavior while preserving local routing, token, sync, and provider overlays.

Current dirty files:

- `src-tauri/src/codex_config.rs`
- `src-tauri/src/codex_history_migration.rs`
- `src-tauri/src/commands/mod.rs`
- `src-tauri/src/commands/s3_sync.rs`
- `src-tauri/src/commands/settings.rs`
- `src-tauri/src/proxy/providers/codex.rs`
- `src-tauri/src/proxy/providers/codex_chat_common.rs`
- `src-tauri/src/proxy/providers/codex_chat_history.rs`
- `src-tauri/src/proxy/providers/streaming_codex_chat.rs`
- `src-tauri/src/proxy/providers/transform_codex_chat.rs`
- `src-tauri/src/proxy/media_sanitizer.rs`
- `src-tauri/src/settings.rs`
- `src-tauri/src/lib.rs`
- `src-tauri/src/services/mod.rs`
- `src-tauri/src/services/codex_oauth_models.rs`
- `src-tauri/src/services/s3.rs`
- `src-tauri/src/services/s3_auto_sync.rs`
- `src-tauri/src/services/s3_sync.rs`
- `src-tauri/src/services/sync_protocol.rs`
- `src-tauri/src/usage_events.rs`
- `src-tauri/src/database/mod.rs`
- `src/components/settings/CodexAuthSettings.tsx`
- `src/components/settings/WebdavSyncSection.tsx`
- `src/hooks/useUsageEventBridge.ts`
- `src/hooks/useTauriEvent.ts`
- `tests/hooks/useUsageEventBridge.test.tsx`
- `tests/hooks/useSettingsForm.test.tsx`
- `vitest.config.ts`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml codex_chat --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml s3 --lib`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml --lib -- --test-threads=1`
- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/hooks/useSettingsForm.test.tsx tests/hooks/useUsageEventBridge.test.tsx tests/hooks/useSettings.test.tsx tests/components/WebdavSyncSection.test.tsx tests/integration/App.test.tsx tests/components/ProviderForm.codexMeta.test.tsx tests/config/codexTemplates.test.ts tests/config/codexChatProviderPresets.test.ts tests/config/therouterProviderPresets.test.ts tests/config/therouterOpenCodeOpenClawPresets.test.ts tests/utils/deepClone.test.ts tests/utils/usageDisplay.test.ts src/lib/version.test.ts"`
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-ccs-3-16-2-release-gate.ps1`
- If GitHub or crates.io index access is reset after proxy retry, use the same gate with `-OfflineCargo` to verify Cargo checks from the local lockfile/cache while keeping the default gate online.

## Group 6 - Server RPC / Web Core Bridge

Purpose: expose the new backend functionality through the Web server RPC layer without diverging from the Tauri command compatibility list.

Current dirty files:

- `crates/core/src/lib.rs`
- `crates/server/src/api/dispatch.rs`
- `crates/server/src/api/ws.rs`
- `crates/server/Cargo.lock`
- `crates/core/Cargo.lock`

Related regression-watch entry points:

- `crates/server/src/api/invoke.rs`
- `crates/server/tests/tauri_rpc_consistency.rs`
- `src/lib/transport/wsTransport.ts`

Validation:

- `rtk cargo test --manifest-path crates/server/Cargo.toml`
- `rtk cargo test --manifest-path crates/core/Cargo.toml`

## Group 7 - Frontend Settings / Sync UI / API Contracts

Purpose: keep S3/WebDAV mutual exclusion, settings API, schema, UI save semantics, and event refresh behavior coherent across desktop and Web transports.

Current dirty files:

- `src/App.tsx`
- `src/components/FirstRunNoticeDialog.tsx`
- `src/components/UsageScriptModal.tsx`
- `src/components/settings/CodexAuthSettings.tsx`
- `src/components/settings/SettingsPage.tsx`
- `src/components/settings/WebdavSyncSection.tsx`
- `src/components/providers/forms/ProviderForm.tsx`
- `src/hooks/useSettings.ts`
- `src/hooks/useSettingsForm.ts`
- `src/hooks/useTauriEvent.ts`
- `src/hooks/useUsageEventBridge.ts`
- `src/lib/api/settings.ts`
- `src/lib/schemas/settings.ts`
- `src/types.ts`
- `src/utils/deepClone.ts`
- `src/utils/providerConfigUtils.ts`
- `src/utils/usageDisplay.ts`
- `tests/components/WebdavSyncSection.test.tsx`
- `tests/components/ProviderForm.codexMeta.test.tsx`
- `tests/hooks/useSettingsForm.test.tsx`
- `tests/hooks/useUsageEventBridge.test.tsx`
- `tests/lib/*`
- `tests/utils/deepClone.test.ts`
- `tests/utils/usageDisplay.test.ts`

Validation:

- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/hooks/useSettingsForm.test.tsx tests/hooks/useUsageEventBridge.test.tsx tests/components/WebdavSyncSection.test.tsx tests/components/ProviderForm.codexMeta.test.tsx tests/lib/settingsSchema.test.ts tests/utils/deepClone.test.ts tests/utils/usageDisplay.test.ts"`

## Group 8 - Codex Provider Presets / Templates

Purpose: keep official Codex Chat provider defaults, model catalogs, reasoning metadata, and fork preset overlays reviewable apart from backend transport changes.

Current dirty files:

- `src/config/codexProviderPresets.ts`
- `src/config/claudeDesktopProviderPresets.ts`
- `src/config/claudeProviderPresets.ts`
- `src/config/geminiProviderPresets.ts`
- `src/config/openclawProviderPresets.ts`
- `src/config/opencodeProviderPresets.ts`
- `src-tauri/src/resources/*`
- `tests/config/codexChatProviderPresets.test.ts`
- `tests/config/codexTemplates.test.ts`
- `tests/config/therouterProviderPresets.test.ts`
- `tests/config/therouterOpenCodeOpenClawPresets.test.ts`

Validation:

- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/config/codexChatProviderPresets.test.ts tests/config/codexTemplates.test.ts tests/config/therouterProviderPresets.test.ts tests/config/therouterOpenCodeOpenClawPresets.test.ts"`

## Group 9 - Language / i18n zh-TW

Purpose: keep Traditional Chinese registration aligned across UI language settings, persisted settings, and locale resources.

Current dirty files:

- `src/i18n/index.ts`
- `src/i18n/locales/zh-TW.json`
- `src/i18n/locales/en.json`
- `src/i18n/locales/ja.json`
- `src/i18n/locales/zh.json`
- `src/components/settings/LanguageSettings.tsx`
- `src-tauri/src/settings.rs`
- `tests/lib/i18n.test.ts`
- `tests/lib/settingsSchema.test.ts`

Validation:

- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/lib/i18n.test.ts tests/lib/settingsSchema.test.ts"`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml settings --lib`

## Group 10 - Usage Events / Rollups

Purpose: preserve local usage event ingestion and display for Codex, Gemini, OpenCode, and backend usage rollups.

Current dirty files:

- `src-tauri/src/commands/usage.rs`
- `src-tauri/src/database/dao/usage_rollup.rs`
- `src-tauri/src/services/session_usage.rs`
- `src-tauri/src/services/session_usage_codex.rs`
- `src-tauri/src/services/session_usage_gemini.rs`
- `src-tauri/src/services/session_usage_opencode.rs`
- `src-tauri/src/proxy/usage/logger.rs`
- `src-tauri/src/usage_events.rs`
- `src/hooks/useUsageEventBridge.ts`
- `src/utils/usageDisplay.ts`
- `tests/hooks/useUsageEventBridge.test.tsx`
- `tests/utils/usageDisplay.test.ts`

Validation:

- `rtk cargo test --manifest-path src-tauri/Cargo.toml usage --lib`
- `rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/hooks/useUsageEventBridge.test.tsx tests/utils/usageDisplay.test.ts"`

## Group 11 - Fork Identity / User Entry / Release Skill

Purpose: make the fork release/support/update identity explicit and prevent users from being routed to official artifacts that do not contain local overlays.

Current dirty files:

- `README.md`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `SUPPORT.md`
- `flatpak/com.ccswitch.desktop.metainfo.xml`
- `docs/user-manual/README.md`
- `docs/user-manual/en/README.md`
- `docs/user-manual/zh/README.md`
- `docs/user-manual/ja/README.md`
- `docs/user-manual/en/1-getting-started/1.2-installation.md`
- `docs/user-manual/zh/1-getting-started/1.2-installation.md`
- `docs/user-manual/ja/1-getting-started/1.2-installation.md`
- `docs/user-manual/en/5-faq/5.2-questions.md`
- `docs/user-manual/zh/5-faq/5.2-questions.md`
- `docs/user-manual/ja/5-faq/5.2-questions.md`
- `skills/cc-switch-release/SKILL.md`
- `skills/cc-switch-release/references/release-facts.md`

Validation:

- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1`

## Group 12 - Docker Web / Production Runtime

Purpose: production-safe Web/API + proxy deployment with loopback-bound ports, auth, secret preflight, and reusable probes.

Current dirty files:

- `.gitignore`
- `crates/server/Cargo.lock`
- `docs/ccs-release-observability-plan.md`
- `scripts/verify-ccs-3-16-2-release-gate.ps1`
- `scripts/ccs-secret-preflight.sh`

Related regression-watch entry points:

- `Dockerfile.web`
- `.dockerignore`
- `docker-compose.ccs-web.yml`
- `scripts/ccs-prod-probe.sh`
- `docs/ccs-production-runbook.md`

Validation:

- `rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && ./scripts/ccs-secret-preflight.sh'`
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-ccs-3-16-2-release-gate.ps1`
- local Docker build and smoke per `docs/ccs-release-observability-plan.md`

## Group 13 - Version Metadata

Purpose: make the official 3.16.2 alignment explicit instead of leaving stale runtime package metadata.

Files:

- `package.json`
- `package-lock.json`
- `src-tauri/Cargo.toml`
- `src-tauri/Cargo.lock`
- `src-tauri/tauri.conf.json`
- `src/lib/version.ts`
- `src/lib/version.test.ts`

Current fork version policy:

- Base version: `3.16.2`
- Fork suffix: `ccs-gateway`
- Patch counter: increment the numeric suffix for local overlay release candidates
- Current value: `3.16.2-ccs-gateway.1`
- Desktop updater endpoint: fork release channel only; do not point fork builds at official `farion1231/cc-switch` updater artifacts.

## Staging Guidance

Stage and review these groups separately. Avoid mixing Group 12 production runtime edits with Group 2/3 proxy and prompt logic unless a release explicitly requires both.

Recommended staging order:

1. Group 1, so the upstream/overlay audit map lands first.
2. Group 11 and Group 13, so fork identity and version metadata are coherent before runtime review.
3. Groups 5 and 6, backend implementation and Web RPC bridge.
4. Groups 7, 8, 9, and 10, frontend contracts, presets, i18n, and usage display.
5. Groups 2, 3, and 4, preserving older local overlays around the new official baseline.
6. Group 12 last, so release/runtime gates review the final integrated tree.
