# 2026-06-11 - Usage probe date template and local WSL publish

## Key Information

- Scope: `<repo-root>`, local WSL Docker target only. Desktop CC Switch installation was not touched.
- Implemented `usage_probe` template variables for multi-probe usage scripts:
  - `{{todayStart}}` -> local-day midnight encoded as `YYYY-MM-DDT00%3A00%3A00`
  - `{{tomorrowStart}}` -> next local-day midnight encoded as `YYYY-MM-DDT00%3A00%3A00`
- Intended RightCode usage probe URL:
  - `{{baseUrl}}/use-log/stats?start_date={{todayStart}}&end_date={{tomorrowStart}}`
- The date variables are computed once per probe request build and shared across URL, headers, and body, preventing cross-midnight inconsistency inside one request.
- The implementation stays inside `src-tauri/src/usage_probe.rs`; legacy single-script `usage_script` execution is unaffected.

## Important Information

- RightCode `/use-log/stats` response shape confirmed by user:
  - `total_cost` is a top-level number.
  - Example fields: `start_date`, `end_date`, `total_cost`, `total_requests`, `total_tokens`.
- RightCode daily extractor should read `Number(response?.total_cost ?? 0)` and return `extra: "今日: ￥..."`.
- Earlier dynamic `request.url: (function () { ... })()` failed because the probe runner treats `request.url` as a string template and does not evaluate JS for URL construction.
- For zxai / New API investigation:
  - `/api/usage/token/` works with `Authorization: Bearer sk-...` and no Cookie.
  - `/api/user/self` still requires user login/session and rejected Bearer key for zxai.
  - `/api/usage/token/` is token-level usage, not necessarily user-account-level quota.

## Code And Review

- Primary changed file: `src-tauri/src/usage_probe.rs`.
- Added tests covering:
  - date placeholders are replaced;
  - generated `end_date` is exactly one day after `start_date`;
  - actual `execute_usage_probes` request URL contains replaced date values;
  - body replacement also handles `{{todayStart}}` / `{{tomorrowStart}}`.
- Cross-angle review was run with three independent subagents:
  - security boundary: no blocker; no new JS/URL attack surface or secret leak path found;
  - compatibility/runtime: no blocker; flagged per-field cross-midnight recompute risk, fixed by computing boundaries once per request;
  - testing/acceptance: no blocker; suggested stronger date and body coverage, implemented.

## Verification

- TDD red check:
  - `cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe::tests::replaces_daily_boundary_template_variables -- --nocapture`
  - failed before implementation because `{{todayStart}}` / `{{tomorrowStart}}` were not replaced.
- Final targeted verification:
  - `cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe::tests:: -- --nocapture`
  - result: `22 passed; 0 failed`.
- A full non-`--lib` cargo test attempt previously hit local target/dependency artifact issues (`zeroize_derive` staticlib/rlib mismatch), not a usage-probe assertion failure.

## Local Publish

- First publish attempt used the default WSL distro name and failed preflight with `WSL_E_DISTRO_NOT_FOUND`; no build or container recreate happened.
- The successful run used the operator's configured `<wsl-distro>`.
- Successful publish command:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro '<wsl-distro>'`
- Published local image:
  - `ccs-gateway-web:local`
  - image ID intentionally omitted from this public summary.
- Container:
  - `ccs-gateway-web`
  - state: `Up`
  - ports: `127.0.0.1:17666->17666`, `127.0.0.1:15721->15721`
- Health checks passed:
  - Web UI: `200`
  - API health: `200 {"result":{"enabled":true}}`
  - Proxy TCP: `127.0.0.1:15721 reachable=True`
  - served build asset matched local `dist`: `assets/index-BPLTNd7t.js`
- Publish log:
  - `.run/local-wsl-publish/<timestamped-log>.log`

## Risks And Boundaries

- The local publish built from the current dirty workspace, so it included pre-existing uncommitted changes outside `usage_probe.rs`.
- The date variables use the runtime machine's local timezone. If a provider interprets date ranges using a different account/server timezone, usage totals may have a reporting-window mismatch.
- The date template values are URL-query oriented because colons are pre-encoded. Future body/header uses may need raw ISO variants if a provider expects unencoded JSON body values.

## Dropped Noise

- Raw SQL export contents, API keys, Cookies, sessions, and provider secrets were intentionally not preserved.
- Long Docker build logs and repeated WSL mojibake warnings were not copied; only outcome, image/container IDs, health results, and log path were retained.
