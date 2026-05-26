# CCS Responses Provider Stickiness Design

## Status

Draft for design review. Do not treat this document as implementation approval.

## Background

We observed a difference between two paths:

- Original CCS 3.15 + Codex desktop + CongmingAI: long Responses sessions complete successfully.
- OpenClaw + ccs-gateway-web + failover queue: a long Codex Responses session can fail with `invalid_encrypted_content` when it crosses providers.

The failure is not the earlier `max_output_tokens` compatibility issue. CongmingAI succeeds for fresh direct requests and for an isolated CCS proxy with only CongmingAI enabled. The failing case is a continuation of a long OpenClaw session that has provider-bound encrypted Responses state.

## Reference Source Priority

For this fix, apply TT's reference priority:

1. Source code that can be copied.
2. Source code that can be referenced but not copied directly.
3. Feature behavior that can be used as a reference.
4. Feature behavior that can be studied, but implementation must be designed locally.
5. Own experience and investigation.
6. Experimental development without prior experience.

For this specific issue, original CCS 3.15 provides behavior evidence, not a directly copyable code block. The intended alignment is behavioral: provider-bound Responses continuations must not cross providers.

## Problem

OpenAI Responses continuation state can include provider-bound encrypted content:

- `previous_response_id`
- `input[]` items with `type: "reasoning"`
- fields such as `encrypted_content`

If provider A produced or accepted that encrypted state, provider B may reject it with `invalid_encrypted_content`.

A naive `session_id -> provider_id` map is not sufficient because Codex continuation requests can derive session identity from `previous_response_id` when no stable `session_id` header/metadata is present. Fresh requests may be recorded under a generated UUID, while continuations may look up `codex_<previous_response_id>`, missing the pin.

## Goals

- Preserve normal failover for fresh Responses requests.
- Prevent provider failover for provider-bound Responses continuation state.
- Support continuation requests keyed only by `previous_response_id`.
- Keep behavior process-local and conservative for the first version.
- Avoid deleting `encrypted_content` or rewriting reasoning state.

## Non-Goals

- Do not implement a full persistent session database in v0.
- Do not remove encrypted reasoning content.
- Do not change non-Codex provider routing.
- Do not disable failover for all Codex requests.

## Proposed Design

### State

Add process-local state to `ProxyState`:

- `responses_session_providers: session_id -> provider_id`
- `responses_response_providers: response_id -> provider_id`

Optional future metadata:

- timestamps for TTL
- counters for recorded/applied/missed/blocked

### Lookup Rules

Before the provider retry loop, classify the request:

- Applies only to `app_type == "codex"`.
- Applies only to `/responses` and `/responses/compact` endpoint shapes.
- Sticky continuation if any of the following is true:
  - request body has non-empty `previous_response_id`
  - request input contains a reasoning item
  - request body recursively contains `encrypted_content`

Resolution order:

1. If request has `previous_response_id`, look up `responses_response_providers[previous_response_id]`.
2. If not found, look up `responses_session_providers[session_id]`.
3. If a provider is found and present in the post-selection available provider list (after normal failover queue, health, and circuit filtering), restrict candidates to that provider.
4. If a provider is found but unavailable, fail closed with a specific error message.
5. If no provider is found, allow normal failover.

### Recording Rules

After a successful Responses request:

1. Record `responses_session_providers[session_id] = provider_id` only after the upstream response is accepted enough to prove this provider handled the request (response headers/status accepted, not pre-send or transport failure).
2. Extract response id and record `responses_response_providers[response_id] = provider_id`.
3. For streaming SSE, record `response_id -> provider_id` as soon as `response.created.response.id` is observed, and keep/confirm it on `response.completed.response.id`. Immediate recording helps interrupted streams continue safely; failed streams are still safer pinned than failed over with encrypted state.

Response id extraction:

- Non-streaming JSON:
  - top-level `id`
  - `response.id`
- Streaming SSE:
  - `response.created.response.id`
  - `response.completed.response.id`

This requires collecting response id from response processing without breaking passthrough.

### Error Behavior

If a continuation is pinned to a provider but that provider is unavailable, return a clear message such as:

`Responses session is pinned to provider <name/id>; failover is blocked because encrypted Responses state may be provider-bound. Start a new session or restore the pinned provider.`

This is preferable to silently failing over and triggering `invalid_encrypted_content`.

### Retention

v0 uses process-lifetime maps with bounded coordinated retention. Requirements:

- Cap each map, e.g. 4096 entries.
- Eviction must be deterministic and must not panic.
- Prefer insertion-ordered or LRU eviction.
- Do not clear only one side in a way that creates surprising asymmetric state; if a `session_id` and `response_id` are known to be related, evict them consistently when practical.
- Emit structured logs/counters when entries are evicted.
- A full persistent database is not required for v0.

A TTL/LRU implementation can be refined later, but unbounded growth is not allowed.

### Observability

v0 should emit structured logs or counters for:

- `sticky_recorded_session`
- `sticky_recorded_response`
- `sticky_applied`
- `sticky_missed`
- `sticky_blocked_unavailable`
- `sticky_evicted`

Logs must not include API keys or raw encrypted content.

### Tests

Required before runtime merge:

- Fresh `/v1/responses` is not sticky before success.
- Successful response records `session_id -> provider`.
- Successful response records `response_id -> provider` from non-streaming body.
- Streaming `response.completed` records `response_id -> provider`.
- Continuation with `previous_response_id` restricts providers to the recorded provider.
- Pinned provider missing returns the dedicated safe-block error and emits a `sticky_blocked_unavailable` log/counter.
- Non-Codex and non-Responses paths are not sticky.
- `/responses/compact` sticky and non-sticky behavior is covered.
- Recursive detection catches nested `encrypted_content`, not only top-level `input[]`.
- Response-id lookup works when fresh request and continuation derive different session ids.

## Review Questions

1. Is behavior-level alignment with original CCS 3.15 sufficient, given there is no directly copyable stickiness code?
2. Is response-id based stickiness the right minimal fix for OpenClaw continuation requests?
3. Should v0 fail closed when the pinned provider is unavailable?
4. Is process-local state acceptable for v0, or is persistence required?
5. Is a cap enough for v0, or must TTL/LRU be implemented immediately?
