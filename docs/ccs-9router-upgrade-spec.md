# CCS 9Router-Inspired Upgrade Spec

## Scope

This track borrows selected 9Router strengths into CCS Gateway Web without replacing the existing CCS request rectifier, provider transforms, Responses compatibility, or prompt-cache wiring.

Current implementation covers `ccs-9router-2+3` plus a v0 RTK-style `TokenFilterEngine`:

- Define the configuration and UI surface for RTK/Caveman-inspired compression.
- Implement request-side Token Saver and route safe text through command-aware built-in filters.
- Cover Cargo, TypeScript compiler, JavaScript test/build output, search results, git status/log, plain logs, and conservative fallback.
- Keep the feature disabled by default.

## Borrowed capabilities

### RTK Token Saver

Goal: reduce repeated large request payloads before they reach the upstream provider.

The first CCS implementation only compresses large textual payload fields:

- Anthropic-style string `tool_result.content`.
- OpenAI Responses-style string `function_call_output.output`.
- OpenAI Chat `role=tool.content`.
- Large generic text blocks when their block type is explicitly safe (`text` / `output_text`).

JSON-looking strings and structured object outputs are skipped by default because tool outputs are often machine-readable and should not be truncated blindly.

The first implementation intentionally does not summarize semantically with an LLM. It performs deterministic head/tail compaction with an explicit omission marker.

### Caveman output compression

Caveman-style output compression is documented as a reserved future capability. Output rewriting is not active and the UI intentionally does not expose an enable switch yet. This is deliberate: response compression needs separate streaming/non-streaming rules and must not corrupt SSE or Responses item ordering.

## Configuration

The settings-backed `OptimizerConfig` now includes:

- `tokenSaver: boolean` — default `false`.
- `tokenSaverMinChars: number` — default `4000`.
- `tokenSaverKeepChars: number` — default `800`.
- `cavemanOutputCompression: boolean` — default `false`, reserved for future schema compatibility; no runtime path reads it yet.

Validation rules:

- `tokenSaverMinChars` must be at least `160`.
- `tokenSaverKeepChars` must be at least `80`.
- `tokenSaverKeepChars` must be smaller than `tokenSaverMinChars`.

These fields live with the existing optimizer settings because this is a request/response optimization layer, not a rectifier retry policy.

## Safety boundaries

Token Saver must preserve these fields exactly:

- `id`
- `call_id`
- `tool_call_id`
- `tool_use_id`
- `previous_response_id`
- `response_id`
- `cache_control`
- `signature`
- `name`
- `role`
- `type`
- `model`

Token Saver must not rewrite payload inside these block types:

- `reasoning`
- `thinking`
- `redacted_thinking`
- `tool_call`
- `function_call`
- `tool_use`

This preserves OpenAI Responses item identity, Anthropic thinking signatures, tool-call linkage, and prompt-cache control fields.

## Request pipeline placement

The first implementation runs after:

1. model mapping,
2. provider format transformation,
3. provider-specific outbound sanitizer,

and before:

1. private `_` field filtering,
2. prompt-cache trace logging,
3. upstream request dispatch.

This placement lets Token Saver see the final upstream protocol shape while still keeping CCS-only private fields out of upstream traffic.

## UI

The Advanced / Rectifier & Optimizer panel exposes:

- Token Saver switch.
- Trigger threshold.
- Retained character count.
- Caveman output compression is shown as a reserved capability note, without an enable switch.

The optimizer master switch still gates these controls.

## Verification requirements

Minimum checks before claiming this feature safe:

- Long string `tool_result.content` is compacted when Token Saver is enabled.
- JSON-looking and object-shaped tool outputs remain intact unless they contain nested explicitly typed text blocks.
- `previous_response_id`, `tool_use_id`, and `cache_control` remain unchanged.
- Reasoning text and `signature` remain unchanged.
- Function/tool-call `arguments` remain unchanged.
- Existing optimizer configs deserialize with defaults for new fields.

## Deferred work

- Provider-pool / quota-aware fallback inspired by 9Router combo routing.
- LLM-based or structured Caveman output compression.
- Token-saving telemetry in usage logs.
- UI help text showing estimated saved characters per request.

## Source-backed audit update

Follow-up source audit corrected the terminology:

- RTK source means <https://github.com/rtk-ai/rtk>, not a 9Router-internal module.
- Caveman source means <https://github.com/JuliusBrussee/caveman>.

Audit docs:

- [CCS RTK Source Audit](ccs-rtk-source-audit.md)
- [CCS Caveman Source Audit](ccs-caveman-source-audit.md)

Current Token Saver + TokenFilterEngine remains an experimental, default-off safety baseline. It should not be described as full RTK parity.

Next implementation direction:

1. Expand built-in command-aware filters only where fixtures prove safety, with JS/Vitest/Jest now included in v0.1.
2. Defer user/project TOML filters until trust gates exist.
3. Treat Caveman as an agent style profile or prose-file compressor, not as a proxy response transformer.
4. Keep Caveman runtime output rewriting disabled until a source-backed design exists.
