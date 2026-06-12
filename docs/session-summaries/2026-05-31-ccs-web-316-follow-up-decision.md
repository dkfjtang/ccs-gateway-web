# 2026-05-31 - CCS Web 3.16 Follow-Up Decision

## Key Information

- Local `<repo-root>` is based on the `cp-yu/cc-switch-web` fork line, not a direct fresh fork from official CC Switch 3.16.
- Local git evidence:
  - Initial local baseline commit: `2baf9a96 Initialize ccs-gateway-web from cp-yu cc-switch-web`.
  - Follow-up baseline sync commits include `f446c936 Sync v3.15 JSON canonical helpers`, `bbb1a877 Sync v3.15 proxy lifecycle and retry behavior`, `79bc28ac Sync v3.15 usage summary metrics`, and `eadc6c73 Sync v3.15 transform cache identity handling`.
  - Branch evidence includes `codex/upgrade-cp-yu-v315`.
- The local version fields still show `3.14.1` in `package.json` and `src-tauri/Cargo.toml`; treat this as stale version metadata, not proof that the code baseline is pre-3.15.
- Decision: pause direct official `farion1231/cc-switch` 3.16 follow-up for now. Wait until the `ccs-web` fork line tracks or adapts 3.16, then evaluate our fork against that updated fork baseline.

## Important Information

- Official `farion1231/cc-switch` has tag `v3.16.0` at commit `47232cb05dc0527f56bc4dc1d61b075ad83eeefe`.
- Official 3.16 release notes describe the major delta as:
  - Codex Chat Completions to Responses routing.
  - Codex third-party provider identity/history migration to stable `custom`.
  - Managed CLI tool lifecycle panel.
  - Partner/provider preset expansion.
  - Default model and pricing refresh, including GPT-5.5 and Claude Opus 4.8.
  - Proxy and format-conversion hardening.
- Earlier recommendation is refined: do not merge official 3.16 directly into this fork as the immediate next step. Treat this repository as `ccs-web v3.15 fork + local overlays`.

## Project Information

- Local overlays that should remain protected during any future upgrade:
  - Token Saver / TokenFilterEngine.
  - Caveman prompt/style preset control, with proxy response rewriting still disabled.
  - Docker Web runtime contract and production probe scripts.
  - OpenClaw priority patch skill/scripts.
  - Responses provider stickiness and service tier controls.
- Future upgrade comparison should use the updated `ccs-web` fork baseline first, then assess deltas against local overlays.

## Follow-Ups

- Monitor whether `cp-yu/cc-switch-web` or the relevant `ccs-web` fork line synchronizes official 3.16.
- When it does, create a dedicated upgrade branch and compare:
  - updated `ccs-web` fork baseline vs current local fork;
  - updated `ccs-web` fork baseline vs official 3.16;
  - local overlays vs any overlapping upstream/fork changes.
- Before any merge, snapshot or commit current dirty worktree changes into logically separated commits.

## Dropped Noise

- Repeated shell status output and failed `rtk Get-Content` attempts were not preserved. The relevant reusable lesson is already covered by the repo AGENTS PowerShell rule: pass PowerShell built-ins through `rtk powershell -NoProfile -Command`.
