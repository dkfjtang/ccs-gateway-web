# CCS Token Cost Saver Patch

## Purpose

This patch keeps Token Saver and Caveman cost controls upgrade-friendly. The implementation should remain a small overlay on top of upstream CCS Web instead of a broad fork.

The patch has two runtime principles:

- Token Saver may reduce request cost only on explicit tool-output text fields.
- Caveman may reduce response verbosity only through opt-in prompt profiles, not by rewriting proxy responses.

## Patch Boundary

Keep the patch concentrated in these files:

- `src-tauri/src/proxy/token_saver.rs`
- `src-tauri/src/proxy/token_filter_engine.rs`
- `src-tauri/src/prompt.rs` for Caveman prompt-profile text if needed
- `src-tauri/src/services/prompt.rs` and `src-tauri/src/commands/prompt.rs` only for Caveman preset creation if upstream changes that API

The normal gateway hot path should have only one Token Saver hook:

```text
forwarder -> token_saver::optimize(&mut request_body, &optimizer_config)
```

Avoid scattering compression decisions across providers, streaming code, usage parsing, or response conversion.

## Current Safe Behavior

Token Saver:

- default off
- compresses only explicit tool outputs
- preserves user text and assistant response text
- skips tool errors
- skips structured object outputs
- skips JSON-looking string outputs
- passes through git diff
- falls back to original text if the filtered output is empty or not smaller
- logs only compression metadata, never body content

Caveman:

- implemented as prompt presets
- opt-in per app/profile through Prompt panel mode selection
- no proxy response-body transformation
- no SSE mutation
- no OpenAI Responses item mutation
- no usage parser changes

## Upgrade Replay Procedure

After an upstream CCS Web upgrade:

1. Reapply `token_saver.rs` and `token_filter_engine.rs` changes.
2. Confirm `forwarder.rs` still calls `token_saver::optimize` once on the final upstream request body.
3. Confirm Caveman remains prompt-profile only.
4. Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-token-cost-savers.ps1
```

If the script fails, do not enable Token Saver in production until the failing invariant is fixed.

## Fixtures

Request-shape fixtures live under:

```text
src-tauri/fixtures/token-cost-savers/
```

Each fixture contains:

- `body`: the request payload before Token Saver runs
- `assertions.unchanged`: JSON Pointer paths that must remain byte-for-byte equal after optimization
- `assertions.shorter`: JSON Pointer paths that must remain non-empty and become shorter after optimization

Current fixture:

- `mixed-request-safety.json`: mixed user text, assistant text, tool output, git diff, tool error, structured tool output and function-call output.

Add a fixture before widening compression scope to a new provider shape or message field.

## Required Invariants

Token Saver must not compress:

- user `type: "text"` content
- assistant `output_text` content
- reasoning or thinking blocks
- tool call arguments
- encrypted content or signatures
- `cache_control`
- tool error outputs
- structured object tool outputs
- git diff

Token Saver may compress:

- `tool_result.content` when it is a string
- `function_call_output.output` when it is a string
- `role: "tool"` message content when it is a string or explicit text part

Caveman must not:

- mutate streamed response chunks
- rewrite final response JSON
- modify usage parsing
- silently enable itself for every request

## Observability

Token Saver logs debug metadata only:

- action
- field kind
- category
- profile
- original char count
- output char count
- omitted char count
- fallback flag
- request-level summary fields when the forwarder hook runs:
  - candidate field count
  - compressed field count
  - skip counts by reason
  - original / output / saved / omitted character totals

Do not log request text, tool output text, prompts, or model responses.

Aggregate usage from logs with:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\report-token-saver-usage.ps1 -LogPath .\logs\ccs-gateway-web.log
```

The report only sums `[TokenSaver] request_summary ...` numeric fields. It does not parse or print request bodies, prompts, headers, credentials, or provider responses.

## Validation Gates

Minimum gates before release:

```powershell
rtk cargo test --manifest-path src-tauri/Cargo.toml token_saver --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml token_filter_engine --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml caveman --lib
```

The helper script runs these gates and static checks for Caveman runtime rewriting.
It also validates that token cost saver fixtures are present and wired into the `token_saver` test target.

## Rollback

Fast rollback is safe because the patch is default-off:

1. Disable Token Saver in optimizer settings.
2. Disable any Caveman prompt preset for the affected app.
3. If needed, remove the single `token_saver::optimize` call from the forwarder hook.

No database migration should be required for rollback.
