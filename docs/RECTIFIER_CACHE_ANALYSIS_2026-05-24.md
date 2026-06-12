# CCS Gateway Web Rectifier / Cache Analysis - 2026-05-24

## Why This Matters

TT explicitly emphasized that official CCS has strong rectifier, request correction, and cache mechanisms. These are not secondary UI features. For `ccs-gateway-web`, they are core gateway quality requirements alongside routing, failover, circuit breaker, cost, and balance visibility.

This document records the current analysis and turns rectifier/cache behavior into an explicit implementation and verification lane.

## Scope

Target repo:

- `<repo-root-on-host>`

Upstream reference:

- `<official-source-root>`
- Official snapshot: `farion1231/cc-switch v3.15.0`, commit `9e3f168`

## Current Parity Snapshot

| Module | Current parity with official v3.15 | Notes |
|---|---|---|
| `src-tauri/src/proxy/thinking_rectifier.rs` | same | Thinking signature / malformed thinking repair logic already matches official. |
| `src-tauri/src/proxy/thinking_budget_rectifier.rs` | same | Budget rectifier already matches official. |
| `src-tauri/src/proxy/thinking_optimizer.rs` | same | Thinking optimizer already matches official. |
| `src-tauri/src/proxy/cache_injector.rs` | same | Cache injection helper already matches official. |
| `src-tauri/src/proxy/copilot_optimizer.rs` | same | Copilot optimizer / deterministic request id helper already matches official. |
| `src-tauri/src/proxy/json_canonical.rs` | same | Added in PR #1; cache-stable canonical JSON helper now matches official. |
| `src-tauri/src/proxy/response_processor.rs` | same | Usage parsing/logging path now matches official after PR #1 sync. |
| `src-tauri/src/proxy/forwarder.rs` | near, intentionally different | Official behavior mostly ported, but headless gating and gateway-specific error policy differ. |
| `src-tauri/src/proxy/providers/transform.rs` | differs | Official has additional canonicalization / prompt cache behavior not fully analyzed yet. |
| `src-tauri/src/proxy/providers/transform_responses.rs` | differs | Official has additional canonicalization / prompt cache behavior not fully analyzed yet. |
| `src-tauri/src/proxy/providers/claude.rs` | differs | Official has additional provider-format / cache-routing behavior not fully analyzed yet. |

## Already Covered In PR #1

### Rectifier / Correction

PR #1 already carries important v3.15 behavior via the synced `forwarder.rs` path:

- `thinking_rectifier.rs` and `thinking_budget_rectifier.rs` are present and parity-matched.
- Rectifier retry failure is handled separately from generic provider failover.
- Provider-side rectifier retry failures can still fail over.
- Client-side rectifier failures release half-open permits neutrally instead of polluting provider health.
- Rectifier retry markers are scoped per provider, avoiding a first provider's rectifier state from incorrectly short-circuiting later providers.

### Cache / Prompt Identity

PR #1 already adds or preserves:

- Official `json_canonical.rs`
- `canonicalize_value`
- `canonical_json_string`
- `short_value_hash`
- `session_client_provided` threading in request context and forwarder
- `prompt_cache_key` related tracing in `forwarder.rs`
- Usage dashboard cache metrics:
  - `realTotalTokens`
  - `cacheHitRate`
  - fresh-input normalization for Codex/Gemini cache-inclusive semantics

## Important Remaining Analysis Lane

The next non-UI priority should be `ccs-web-rectifier-cache-1`:

1. Compare official and target for:
   - `src-tauri/src/proxy/providers/transform.rs`
   - `src-tauri/src/proxy/providers/transform_responses.rs`
   - `src-tauri/src/proxy/providers/claude.rs`
   - cache-related parts of `src-tauri/src/proxy/forwarder.rs`
2. Identify exact upstream changes related to:
   - prompt cache identity
   - canonical JSON body ordering
   - `tool_call` / `tool_result` canonicalization
   - `prompt_cache_key` injection conditions
   - client-provided session identity vs generated UUID identity
   - Codex OAuth cache routing
   - OpenAI Responses cache hit-rate behavior
   - DeepSeek / Responses usage robustness if it touches cache accounting
3. Port only the cache/rectifier relevant hunks first, not broad unrelated Claude Desktop UI changes.

## Required Verification Cases

These should become mock or integration tests before claiming cache/rectifier parity.

### Rectifier

- `thinking` signature error from one provider is rectified once and retried on the same provider.
- Rectifier retry returns 5xx/timeout: record provider failure, then try next provider.
- Rectifier retry returns 400/422 client error: do not fail over, do not pollute circuit breaker.
- Budget rectifier triggers independently from signature rectifier.
- Rectifier state is per provider, not shared across the whole failover chain.

### Cache Identity

- If the client provides a stable session ID, the upstream request uses stable cache identity.
- If the session ID is generated locally, do not emit it as upstream cache identity.
- Explicit provider/user `prompt_cache_key` is preserved.
- Reordered JSON request bodies produce the same canonical cache hash.
- Reordered `tool_call` arguments produce the same canonical cache hash.
- Reordered `tool_result` content produces the same canonical cache hash.
- No generated UUID cache churn across requests in the same real client session.

### Usage / Cache Metrics

- Codex/OpenAI Responses rows subtract cache reads from input for fresh-input summary.
- Gemini rows subtract cache reads from input for fresh-input summary.
- Claude rows do not subtract cache reads from input because Anthropic input already excludes cache.
- `realTotalTokens = freshInput + output + cacheCreation + cacheRead`.
- `cacheHitRate = cacheRead / (freshInput + cacheCreation + cacheRead)`.

## Implementation Priority

Recommended order after current PR #1:

1. `ccs-web-rectifier-cache-1`: source diff and focused cache/transform merge plan.
2. `ccs-web-rectifier-cache-2`: port transform/cache identity hunks.
3. `ccs-web-rectifier-cache-3`: add mock tests for rectifier/failover/cache identity behavior.
4. `ccs-web-ci-1`: add CI to run Rust headless check and frontend typecheck/build.

## Current Risk

The helper modules are mostly parity-matched, but parity of helper modules is not enough. The important risk is in wiring:

- when canonicalization is applied,
- whether generated session IDs leak into upstream cache keys,
- whether `prompt_cache_key` is injected too often or too little,
- whether request transforms preserve stable cache identity across Anthropic ↔ OpenAI Responses conversions.

Do not claim official CCS cache/rectifier parity until the transform/provider wiring has been diffed and tested.
