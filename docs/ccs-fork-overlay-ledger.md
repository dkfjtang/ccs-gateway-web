# CCS Gateway Web Fork Overlay Ledger

This ledger tracks local overlays that sit on top of the `ccs-web` v3.15 fork line. Keep it current before merging a newer `ccs-web` or official CC Switch baseline.

## Baseline

- Local baseline: `cp-yu/cc-switch-web` fork line with v3.15 behavior synced into local commits.
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

Before following a newer `ccs-web` fork baseline:

1. Snapshot or commit current local overlay work in separated commits.
2. Refresh `docs/ccs-local-change-groups.md` so the dirty worktree is grouped by review/release bucket.
3. Run `scripts/verify-local-overlays.ps1` and require `overlay_status=overlay_ready`.
4. Compare changed upstream files against every entry in this ledger.
5. Re-run `scripts/verify-token-cost-savers.ps1` after proxy or provider transform conflicts are resolved.
6. Re-run the relevant Caveman smoke/gate only when prompt UI, prompt service, Web runtime, or packaging paths changed.
7. Probe OpenClaw priority patch with `apply_openclaw_fast_priority_patch.sh --check` on the target OpenClaw version before declaring the last-hop route healthy.

## Current Decision

Do not directly merge official `farion1231/cc-switch` 3.16 into this fork. Wait for the `ccs-web` fork line to sync or adapt 3.16, then compare against this overlay ledger.
