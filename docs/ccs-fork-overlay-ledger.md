# CCS Gateway Web Fork Overlay Ledger

This ledger tracks local overlays that sit on top of the official `farion1231/cc-switch` line. Keep it current before merging a newer official CC Switch baseline or comparing against the older `ccs-web` fork for reference.

## Baseline

- Local baseline history: `cp-yu/cc-switch-web` fork line with v3.15 behavior synced into local commits. Treat this as historical context only.
- Evidence commits:
  - `2baf9a96 Initialize ccs-gateway-web from cp-yu cc-switch-web`
  - `f446c936 Sync v3.15 JSON canonical helpers`
  - `bbb1a877 Sync v3.15 proxy lifecycle and retry behavior`
  - `79bc28ac Sync v3.15 usage summary metrics`
  - `eadc6c73 Sync v3.15 transform cache identity handling`
- Version metadata in `package.json` and `src-tauri/Cargo.toml` may lag the behavioral baseline and must not be used alone as the upgrade source of truth.

## Overlay Inventory

| Overlay | Purpose | Primary Entry Points | Default | Verification | Upgrade Risk |
| --- | --- | --- | --- | --- | --- |
| Token Saver / TokenFilterEngine | Compact large safe tool/output text before upstream dispatch. | `src-tauri/src/proxy/forwarder.rs`, `src-tauri/src/proxy/token_saver.rs`, `src-tauri/src/proxy/token_filter_engine.rs`, `src-tauri/src/proxy/body_filter.rs` | Off | `scripts/verify-token-cost-savers.ps1`; `scripts/verify-local-overlays.ps1` | Conflicts with upstream proxy transforms, request sanitizers, or future token optimization logic. |
| Token Saver request observability | Emit one request-level summary without logging raw prompt/body content. | `src-tauri/src/proxy/token_saver.rs`, `src-tauri/src/proxy/forwarder.rs` | Only active when Token Saver is enabled | `cargo test token_saver --lib`; static search for `request_summary` | Log format should remain aggregate-only; never add raw bodies, headers, keys, or tokens. |
| Caveman prompt/style presets | Provide Lite/Full/Ultra prompt presets through normal prompt enable/disable flow. | `src-tauri/src/prompt.rs`, `src-tauri/src/services/prompt.rs`, `src-tauri/src/commands/prompt.rs`, `src/components/prompts/PromptPanel.tsx` | Off | Caveman tests and smoke scripts; `scripts/verify-caveman-release-gate.ps1`; `scripts/verify-local-overlays.ps1` | Must remain prompt-level. Do not wire Caveman output compression into proxy response mutation without a new design. |
| Responses provider stickiness | Prevent provider-bound encrypted Responses continuations from failing over to another provider. | `src-tauri/src/proxy/forwarder.rs`, `src-tauri/src/proxy/response_processor.rs`, `src-tauri/src/proxy/server.rs` | Active for Codex Responses continuation state | `cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib`; `scripts/verify-local-overlays.ps1` | Official/fork 3.16 Codex Chat routing may touch the same provider/session paths. Recheck behavior after merge. |
| Responses service tier controls | Preserve or inject `service_tier=priority` for supported OpenAI Responses/Codex fast paths. | `src-tauri/src/provider.rs`, `src-tauri/src/proxy/types.rs`, `src-tauri/src/proxy/providers/transform_responses.rs`, `src-tauri/src/proxy/providers/claude.rs` | Global passthrough on; provider can disable | `cargo test --manifest-path src-tauri/Cargo.toml service_tier --lib`; `scripts/verify-local-overlays.ps1` | Upstream provider schema or OpenAI compatibility transforms may overwrite or drop the field. |
| Official Codex Chat routing/history | Preserve the official v3.16.2 Codex Chat path while keeping local provider routing and media safety overlays. | `src-tauri/src/proxy/providers/codex.rs`, `src-tauri/src/proxy/providers/codex_chat_common.rs`, `src-tauri/src/proxy/providers/codex_chat_history.rs`, `src-tauri/src/proxy/providers/streaming_codex_chat.rs`, `src-tauri/src/proxy/providers/transform_codex_chat.rs`, `src-tauri/src/proxy/media_sanitizer.rs` | Active for Codex Chat providers | `cargo test --manifest-path src-tauri/Cargo.toml codex_chat --lib`; Codex preset Vitest coverage; full `src-tauri` lib tests | Provider model mapping, streaming transforms, and history import paths overlap with upstream 3.16 Codex changes. |
| WebDAV/S3 sync protocol | Preserve WebDAV while adding S3-compatible sync with secret redaction, remote snapshot compatibility, and mutual exclusion. | `src-tauri/src/services/webdav_sync.rs`, `src-tauri/src/services/s3.rs`, `src-tauri/src/services/s3_sync.rs`, `src-tauri/src/services/s3_auto_sync.rs`, `src-tauri/src/services/sync_protocol.rs`, `src-tauri/src/commands/s3_sync.rs`, `src/components/settings/WebdavSyncSection.tsx`, `src/lib/schemas/settings.ts` | Off until configured; WebDAV and S3 are mutually exclusive | `cargo test --manifest-path src-tauri/Cargo.toml s3 --lib`; `vitest run tests/components/WebdavSyncSection.test.tsx tests/lib/settingsSchema.test.ts`; full release gate | Secrets must remain redacted on read, preserved only for intended save refreshes, and never cleared by generic settings saves. |
| Usage event bridge and display | Preserve local usage event ingestion/display for Codex, Gemini, OpenCode, and related dashboards. | `src-tauri/src/usage_events.rs`, `src-tauri/src/services/session_usage.rs`, `src-tauri/src/services/session_usage_codex.rs`, `src-tauri/src/services/session_usage_gemini.rs`, `src-tauri/src/services/session_usage_opencode.rs`, `src/hooks/useUsageEventBridge.ts`, `src/utils/usageDisplay.ts` | Active when usage events are emitted | `vitest run tests/hooks/useUsageEventBridge.test.tsx tests/utils/usageDisplay.test.ts`; full `src-tauri` lib tests | Event payload shape and local date rollups can drift across upstream/runtime changes. |
| Provider presets / i18n bootstrap | Preserve fork provider defaults and Traditional Chinese language registration during official baseline refreshes. | `src/config/*ProviderPresets.ts`, `src/config/codexTemplates.ts`, `src/i18n/index.ts`, `src/i18n/locales/zh-TW.json`, `src/hooks/useSettingsForm.ts`, `src/hooks/useSettings.ts` | Enabled through UI defaults and saved settings | `vitest run tests/config/codexChatProviderPresets.test.ts tests/config/codexTemplates.test.ts tests/hooks/useSettingsForm.test.tsx tests/lib/i18n.test.ts tests/lib/settingsSchema.test.ts` | Preset IDs, template variables, and language enum values must stay aligned across schema, UI, and tests. |
| OpenClaw priority patch | Patch local/production OpenClaw fast mode wrapper after OpenClaw install or upgrade. | `skills/openclaw-fast-priority-patch/SKILL.md`, `skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh` | External patch, not CCS runtime | Skill dry-run/check plus wrapper test on target host | OpenClaw dist filenames and minified aliases change between releases. The patch must keep detect-first behavior. |
| Docker Web / production runtime | Run CCS Gateway Web as loopback-bound Web/API plus proxy service with persistent host state. | `Dockerfile.web`, `docker-compose.ccs-web.yml`, `scripts/ccs-prod-probe.sh`, `docs/ccs-release-observability-plan.md` | Production-specific | `scripts/ccs-prod-probe.sh`; secret preflight before push | Preserve ports, mounts, auth, and rollback contract when merging fork or official changes. |

## Observability Contract

Token Saver logs are aggregate-only:

```text
[TokenSaver] request_summary candidate_fields=... compressed_fields=... skipped_below_threshold=... skipped_json_like=... skipped_too_large=... skipped_not_smaller=... skipped_empty_output=... original_chars=... output_chars=... saved_chars=... omitted_chars=...
```

Responses stickiness logs are state-transition-only:

```text
[sticky_recorded_session]
[sticky_recorded_response]
[sticky_applied]
[sticky_missed]
[sticky_blocked_unavailable]
[sticky_evicted]
```

Neither path may log request bodies, prompts, headers, API keys, tokens, encrypted content, cookies, or raw provider credentials.

## Merge Checklist

Before following a newer official `farion1231/cc-switch` baseline:

1. Snapshot or commit current local overlay work in separated commits.
2. Refresh `docs/ccs-local-change-groups.md` so the dirty worktree is grouped by review/release bucket.
3. Run `scripts/verify-local-overlays.ps1` and require `overlay_status=overlay_ready`.
4. Compare changed official upstream files against every entry in this ledger.
5. Re-run `scripts/verify-token-cost-savers.ps1` after proxy or provider transform conflicts are resolved.
6. Run `scripts/verify-ccs-3-16-2-release-gate.ps1` for the full Codex Chat, sync, usage, provider preset, i18n, Docker, and secret verification sweep.
7. Re-run the relevant Caveman smoke/gate only when prompt UI, prompt service, Web runtime, or packaging paths changed.
8. Probe OpenClaw priority patch with `apply_openclaw_fast_priority_patch.sh --check` on the target OpenClaw version before declaring the last-hop route healthy.
9. Use `ccs-web-reference` only when an official upstream conflict needs historical fork context.

## Current Decision

Treat official `farion1231/cc-switch` as the primary upstream from now on. Use `ccs-web` only as an auxiliary reference for diffing, history lookup, and overlay comparison.

Before each upstream refresh:

1. Compare the current local tree against official `farion1231/cc-switch` first.
2. Use `ccs-web` only to recover old overlay context or to explain older fork-specific behavior.
3. Re-validate every overlay in this ledger against the new official baseline.
