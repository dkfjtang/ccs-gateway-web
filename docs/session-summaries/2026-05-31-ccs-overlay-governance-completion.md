# 2026-05-31 - CCS overlay governance completion

## Key Information

- Repo: `<repo-root>`.
- Baseline decision remains: treat local repo as `cp-yu/cc-switch-web` v3.15 fork plus local overlays; wait for `ccs-web` fork to catch up with 3.16 before following 3.16.
- Completed five ordered governance items:
  1. Dirty worktree grouping: `docs/ccs-local-change-groups.md`.
  2. Release gate wording: `scripts/verify-local-overlays.ps1` is required in `docs/ccs-release-observability-plan.md` and must output `overlay_status=overlay_ready`.
  3. OpenClaw priority patch read-only health check: `skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --check`.
  4. Token Saver usage report: `scripts/report-token-saver-usage.ps1`.
  5. Fork version metadata: `3.15.0-ccs-gateway.1` in `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, and `src-tauri/tauri.conf.json`.

## Important Information

- `--check` is explicitly read-only and documents status/exit-code mapping:
  - `check_status=ok`, exit `0`
  - `check_status=needs_patch`, exit `1`
  - `check_status=unsupported_shape`, exit `2`
- `docs/ccs-local-change-groups.md` distinguishes current dirty files from related regression-watch entry points after cross-review feedback.
- `scripts/report-token-saver-usage.ps1` aggregates only `[TokenSaver] request_summary ...` numeric fields and does not print raw prompts, bodies, headers, credentials, or provider responses.

## Verification

- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1` passed and printed `overlay_status=overlay_ready`.
- Synthetic Token Saver usage log test passed with `requests=2`, `candidate_fields=4`, and `saved_ratio=50.00%`.
- OpenClaw script syntax check passed. In current WSL, `--check` returned `check_status=unsupported_shape` and exit `2` because Node/OpenClaw install paths were not present; this verified unsupported-shape handling but not the real `ok` path.
- One independent cross-review pass was completed. It found no blockers; its actionable minor feedback on `--check` exit codes and dirty-file grouping was fixed.

## Follow-ups

- Before production or OpenClaw upgrade sign-off, run `apply_openclaw_fast_priority_patch.sh --check` on the real OpenClaw host where Node and OpenClaw are installed, and require `check_status=ok`.
- Before committing, stage by groups from `docs/ccs-local-change-groups.md`; avoid mixing production runtime edits, Token Saver, Caveman, and version metadata in one commit.
- `package-lock.json` already contains broad dependency/lockfile drift in the dirty worktree; do not describe it as a pure version-only change unless that drift is separately reviewed.

## Dropped Noise

- Repeated progress updates, long Rust warning output, WSL localhost warnings, and failed quoting attempts were not preserved because they do not change the durable project decisions.
