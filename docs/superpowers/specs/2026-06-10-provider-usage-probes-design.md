# Provider Usage Probes Design

## Summary

Add a lightweight multi-probe extension to each provider's usage configuration. The feature lets one provider collect usage, billing rate, model list, and account status from separate service-provider endpoints, then merges those probe results into the existing provider usage display.

The first release only collects and displays structured probe metrics. It does not implement automatic provider switching, dynamic routing, pricing history, or model configuration sync.

## Goals

- Keep existing single-script usage configurations working without migration.
- Allow a provider to define multiple enabled probe items under one usage configuration.
- Support separate endpoints for usage, billing rate, model list, and account status.
- Display the provider-returned billing rate near the existing "used" usage value.
- Preserve structured fields for a later provider auto-switching feature.
- Keep the patch small and easy to replay onto later CCS upgrades.

## Non-Goals

- Do not implement automatic provider switching.
- Do not update provider model configuration from probed models.
- Do not add rate history, trend charts, or price-table management.
- Do not change production overlay, release, routing, or failover behavior.
- Do not replace the existing `usage_script.code` path.

## Current Code Context

The current implementation has a single usage-script contract:

- `src/types.ts` defines `UsageScript`, `UsageData`, and `UsageResult`.
- `src-tauri/src/provider.rs` defines the Rust serde equivalents.
- `src-tauri/src/usage_script.rs` executes the JavaScript request/extractor script and validates old result fields.
- `src-tauri/src/services/provider/usage.rs` dispatches saved usage queries and test queries.
- `src/components/UsageScriptModal.tsx` configures and tests usage scripts.
- `src/components/UsageFooter.tsx` renders usage values on provider cards.
- `src/components/providers/ProviderCard.tsx` hosts `UsageFooter` and multi-plan expansion.

## Data Contract

### UsageScript

Add an optional `probes` field. Existing configurations that omit `probes` or set it to an empty array must behave exactly like today.

```ts
export interface UsageScript {
  enabled: boolean;
  language: "javascript";
  code: string;
  timeout?: number;
  templateType?: TemplateType;
  apiKey?: string;
  baseUrl?: string;
  accessToken?: string;
  userId?: string;
  codingPlanProvider?: string;
  autoQueryInterval?: number;
  autoIntervalMinutes?: number;
  request?: {
    url?: string;
    method?: string;
    headers?: Record<string, string>;
    body?: any;
  };
  probes?: UsageProbe[];
}
```

### UsageProbe

```ts
export type UsageProbeType = "usage" | "rate" | "models" | "account";

export interface UsageProbe {
  id: string;
  type: UsageProbeType;
  enabled: boolean;
  request: {
    url: string;
    method: string;
    headers?: Record<string, string>;
    body?: string;
  };
  extractor: string;
  timeout?: number;
}
```

Validation rules:

- `id` is required, stable, and limited to safe identifier characters such as letters, numbers, `_`, and `-`.
- `type` must be one of `usage`, `rate`, `models`, or `account`.
- At most one enabled `usage` probe is allowed in the first release.
- Unknown probe types fail validation with a clear error.
- `probes: undefined` and `probes: []` are equivalent to legacy single-script mode.

### UsageData

Keep `UsageData` as the per-plan/per-tier usage shape. Add only plan-level fields here.

```ts
export interface UsageData {
  planName?: string;
  extra?: string;
  isValid?: boolean;
  invalidMessage?: string;
  total?: number;
  used?: number;
  remaining?: number;
  unit?: string;
  resetsAt?: string;
}
```

### UsageResult

Put query-level probe metrics at the result top level instead of hiding them in the first `UsageData` row.

```ts
export interface UsageResult {
  success: boolean;
  data?: UsageData[];
  error?: string;
  rate?: number;
  rateLabel?: string;
  models?: string[];
  probeErrors?: Record<string, string>;
}
```

This avoids an implicit "first plan owns global state" contract and keeps multi-plan rendering clear.

## Merge Rules

Probe results merge by ownership:

- `usage` owns `data`, including `used`, `remaining`, `total`, `unit`, `planName`, `resetsAt`, and plan-level validity fields.
- `rate` owns `rate` and `rateLabel`.
- `models` owns `models`.
- `account` owns account-level `isValid` and safe error summaries when they do not conflict with plan-level usage results.

If a probe returns fields outside its ownership, those fields are ignored in the merged output and may be reported in debug logs during development. This keeps display behavior deterministic.

Failure semantics:

- If legacy single-script mode is active, behavior stays unchanged.
- If multi-probe mode is active and the `usage` probe fails, return `success=false`.
- If `rate`, `models`, or `account` fails while `usage` succeeds, return `success=true`, preserve usage data, and write a sanitized error summary into `probeErrors[probe.id]`.
- Failed non-core probes must not overwrite successful usage fields.
- Overall test failure must not pollute the existing React Query cache with mixed old/new data.

## Security Rules

Multi-probe execution must not inherit the legacy custom-template relaxed cross-origin behavior.

- Probe requests use the existing global HTTP client and timeout clamp.
- Probe requests default to HTTPS-only, with localhost loopback allowed for development.
- Cross-origin access is not implicitly allowed just because the old `templateType` is `custom`.
- Any future cross-origin escape hatch must be explicit per probe and should be hidden from normal presets.
- Error messages stored in `probeErrors` must not include API keys, access tokens, authorization headers, or request bodies.
- Probe extractor validation must be independent from the old `usage_script.validate_result` behavior so new fields can be type-checked without risking legacy regressions.

## Execution Flow

1. Load provider and saved `usage_script`.
2. If usage is disabled, keep the existing disabled behavior.
3. If `usage_script.probes` has no enabled items, execute the legacy single-script path.
4. If enabled probes exist, validate the probe list.
5. Execute enabled probes one by one for the first release. This is simpler to reason about and keeps failure ordering deterministic.
6. Validate each probe result against its probe type schema.
7. Merge probe results using the ownership rules above.
8. Return one `UsageResult` for the existing frontend query path.

The first implementation should add an isolated module such as `src-tauri/src/usage_probe.rs` for probe execution, validation, and merge helpers. `src-tauri/src/services/provider/usage.rs` should only choose between the legacy and multi-probe paths.

## UI Design

### UsageScriptModal

The modal keeps the existing script editor and templates. Add a clearly labeled "multi-metric probe" section for the new mode.

Rules:

- If at least one probe is enabled, the modal shows that multi-probe mode is the active mode.
- The legacy script editor remains available for compatibility and migration, but the active test/save behavior is clear.
- The test button runs the active mode.
- Multi-probe test results show per-probe success/failure, including sanitized `probeErrors`.
- Probe configuration uses the existing provider credentials variables where practical, such as `{{apiKey}}`, `{{baseUrl}}`, `{{accessToken}}`, and `{{userId}}`.

### UsageFooter

Render billing rate only in `UsageFooter`, not in `ProviderCard`.

- Inline card view: show `计费倍率 x1.5` near the existing `已用` value when `usage.rate` or `usage.rateLabel` exists.
- If `rateLabel` exists, prefer it over formatting `rate`.
- If no rate exists, render no placeholder.
- If `success=false`, do not show stale or cached rate text from a prior result.
- Expanded multi-plan view: show the same query-level billing rate in the header or next to each plan only if it does not imply a per-plan rate.
- Model list is not expanded on the provider card. The first release may show a compact count in test results or details only, such as `模型 12 个`.

## Compatibility

- Existing single-script configurations must not require migration.
- `probes: undefined` and `probes: []` must run the old path.
- Existing template types such as `github_copilot`, `token_plan`, and `balance` keep their special handling and are not hijacked by probes unless a later explicit migration is designed.
- Existing `UsageData.extra` remains supported for old scripts.
- The frontend still calls `queryProviderUsage` and `testUsageScript`. To test probes, `testUsageScript` can accept an optional full `UsageScript` payload while preserving the current flat arguments.

## Upgrade Patch Boundaries

Keep the replayable patch small:

- `src/types.ts`: type extension only.
- `src-tauri/src/provider.rs`: serde type extension and compatibility tests.
- `src-tauri/src/usage_probe.rs`: new probe execution, validation, and merge module.
- `src-tauri/src/lib.rs`: register the new module.
- `src-tauri/src/services/provider/usage.rs`: legacy/probe dispatch.
- `src-tauri/src/commands/provider.rs`: minimal `testUsageScript` input extension.
- `src/lib/api/usage.ts`: optional full-script test payload.
- `src/components/UsageScriptModal.tsx`: probe configuration and active-mode test behavior.
- `src/components/UsageFooter.tsx`: billing-rate display.
- Tests for formatting, save flow, merge semantics, and compatibility.

Avoid changing routing, failover, proxy selection, overlay scripts, production release scripts, or provider switching logic.

## Acceptance Criteria

- Legacy providers with no `probes` field query and display exactly as before.
- `probes: []` behaves the same as no `probes`.
- Multi-probe mode activates only when at least one probe is enabled.
- One enabled `usage` probe plus successful `rate`, `models`, and `account` probes returns `success=true` with usage data and top-level `rate`, `models`, and account status fields.
- `rate`, `models`, or `account` failure does not block successful usage display.
- `usage` probe failure returns `success=false` and a safe error message.
- Billing rate appears near `used` in provider cards when present.
- No `undefined`, empty placeholder, or stale rate appears when rate is absent or the current query failed.
- Probe errors visible in the configuration/test result area do not leak credentials.
- Probed model lists are display-only snapshots and do not update provider model configuration.
- New i18n strings cover at least Chinese and English for probe type names, billing rate, partial probe failure, model count, and account status.

## Test Plan

Required Rust tests:

- `UsageScript` serde compatibility for old configs without `probes`.
- `probes: []` is equivalent to old mode.
- `UsageProbe` validation rejects unknown types, empty IDs, unsafe IDs, and multiple enabled `usage` probes.
- Probe result validation rejects non-number `rate`, invalid model arrays, and malformed `probeErrors`.
- Merge tests cover all probes success, non-core probe failure, and core usage failure.
- Legacy `usage_script` single-object and array returns still pass existing behavior.

Required frontend tests:

- `UsageFooter` displays `rateLabel` first, then formatted `rate`, and no placeholder when absent.
- `UsageFooter` does not display stale rate when `success=false`.
- `usageDisplay` summary ignores probe-only fields unless explicitly designed to include them.
- `saveUsageScript` preserves `probes` without dropping request/extractor/timeout.
- `UsageScriptModal` test action passes the full script in multi-probe mode and updates the `["usage", provider.id, appId]` cache only on successful results.
- App/provider flow smoke test confirms new `probes` metadata can be saved without breaking old provider actions.

Suggested validation commands:

```powershell
pnpm typecheck
pnpm vitest run tests/utils/usageDisplay.test.ts tests/hooks/useProviderActions.test.tsx tests/integration/App.test.tsx
pnpm vitest run tests/components/UsageScriptModal.test.tsx tests/components/UsageFooter.test.tsx
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_script
cargo test --manifest-path src-tauri/Cargo.toml --lib provider::tests
cargo test --manifest-path src-tauri/Cargo.toml
```

For release readiness in this repository, keep the existing overlay gate separate:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1
```

## Open Decisions

- Whether to show a successful `rate` when the `usage` probe failed. The first implementation will not show it in `UsageFooter` because `success=false` means the usage area is in failure state. The result may still include safe probe metadata for debugging if the backend can return it without confusing the UI.
- Whether account-level validity should become a top-level `UsageResult.account` object later. The first release keeps account status minimal to avoid widening the UI.
