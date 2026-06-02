# 2026-05-31 - CCS Web Overlay Summary

## Key Information

- Local fork baseline is the `cp-yu/cc-switch-web` v3.15 line, not a fresh direct fork from official CC Switch 3.16.
- Evidence commits for the local baseline include:
  - `2baf9a96 Initialize ccs-gateway-web from cp-yu cc-switch-web`
  - `f446c936 Sync v3.15 JSON canonical helpers`
  - `bbb1a877 Sync v3.15 proxy lifecycle and retry behavior`
  - `79bc28ac Sync v3.15 usage summary metrics`
  - `eadc6c73 Sync v3.15 transform cache identity handling`
- Official `farion1231/cc-switch` has `v3.16.0` at commit `47232cb05dc0527f56bc4dc1d61b075ad83eeefe`, but direct upgrade was intentionally deferred until the `ccs-web` fork line catches up.
- The current work focused on three local overlay upgrades:
  - a fork overlay ledger,
  - a unified overlay verifier,
  - Token Saver and Responses stickiness observability.

## Important Information

- The local `package.json` and `src-tauri/Cargo.toml` version fields still read `3.14.1`; treat that as stale metadata, not as the behavioral baseline.
- Token Saver now returns a request-level summary and the forwarder logs an aggregate-only `request_summary` line with counts and character totals, without logging request bodies.
- Responses stickiness already had state-transition logs; the new overlay verifier now checks for the existing `sticky_recorded_session`, `sticky_recorded_response`, `sticky_applied`, `sticky_missed`, `sticky_blocked_unavailable`, and `sticky_evicted` diagnostics.
- Caveman remains prompt-level only; the overlay verifier explicitly checks that Caveman is not wired into proxy/runtime response rewriting.
- The new overlay ledger documents the protected local overlays:
  - Token Saver / TokenFilterEngine
  - Caveman prompt/style presets
  - Responses provider stickiness
  - service tier controls
  - OpenClaw priority patch
  - Docker Web / production runtime contract

## Project Information

- New files added during the session:
  - `docs/ccs-fork-overlay-ledger.md`
  - `scripts/verify-local-overlays.ps1`
  - `docs/ccs-token-cost-saver-patch.md` was updated with the new observability contract
  - `src-tauri/src/proxy/token_saver.rs` and `src-tauri/src/proxy/forwarder.rs` were updated for request-level token saver summaries
- Verification passed:
  - `cargo test --manifest-path src-tauri/Cargo.toml token_saver --lib`
  - `cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib`
  - `powershell -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1`
  - final overlay verifier output: `overlay_status=overlay_ready`

## Follow-ups

- Wait for the `ccs-web` fork line to synchronize or adapt official 3.16 before attempting the next upstream comparison.
- Keep the overlay ledger current before any future merge.
- Preserve the single Token Saver hook and the aggregate-only logging contract during future proxy changes.
- Re-run `scripts/verify-local-overlays.ps1` after any change that touches proxy transforms, Caveman prompt flow, Responses routing, or service tier handling.

## Dropped Noise

- Repeated Cargo lock waits, compiler warnings, and failed intermediate test attempts were not preserved.
- No secrets, tokens, or raw request bodies were written into the archive.
