# 2026-07-22 - Local Release Gate Speedups

## Key Information
- Scope: optimized the existing local release gate flow without replacing the publish path or weakening the full release gate.
- The existing full release gate remains `scripts/verify-ccs-3-16-2-release-gate.ps1`.
- Added three package entry points:
  - `pnpm gate:quick` for changed-scope developer feedback only.
  - `pnpm gate:standard` for changed-scope validation only.
  - `pnpm gate:release` as the publish gate wrapper over the full release gate.
- `gate:quick` and `gate:standard` are explicitly marked as not release evidence through `release_gate_evidence=false` and `not_release_evidence=true`.
- `gate:release` is marked as release evidence and rejects skip flags such as `-SkipDocker` and `-SkipDesktopPreflight`.

## Important Information
- Main implementation commit: `be764ddf` (`feat: speed up local release gates`), pushed to `origin/main`.
- Added `scripts/release-gate-profiles.mjs` and targeted coverage in `tests/scripts/releaseGateProfiles.test.ts`.
- Added elapsed timing output to the existing PowerShell gate wrappers:
  - `scripts/verify-ccs-3-16-2-release-gate.ps1`
  - `scripts/verify-local-overlays.ps1`
  - `scripts/verify-token-cost-savers.ps1`
- Updated `scripts/ccs-secret-preflight.sh` so changed-scope checks work from linked worktrees by passing normalized Git worktree/common-dir context into WSL.
- Updated `vitest.config.ts` so tests may run inside repo-local `.worktrees` checkouts while the main checkout still excludes `.worktrees` from normal test discovery.

## Verification
- `pnpm exec vitest run tests/scripts/releaseGateProfiles.test.ts --reporter verbose --no-color` passed: 1 file, 7 tests.
- `git diff --check` passed after the final test compatibility fix.
- `pnpm gate:quick` passed. It ran whitespace checks and changed-scope secret preflight.
- `pnpm gate:standard` passed. With only the final test-file delta present, it ran the same changed-scope baseline checks.
- `pnpm gate:release -- --print` passed and printed the full release gate command.
- `pnpm gate:release -- --print -SkipDocker` failed as expected with `Release gate profiles do not accept skip flag: -SkipDocker`.

## Follow-ups
- A stale repo-local worktree for the earlier feature branch still existed at closeout and pointed to the pre-amend feature commit. It was not removed because worktree deletion requires explicit confirmation.
- A pre-existing untracked session-summary file from 2026-07-04 remained untouched.
- If future work needs a fully clean tree, decide whether to track or discard existing untracked session summaries, then remove only confirmed stale worktrees.

## Dropped Noise
- Raw local command transcripts, machine-specific paths, private runtime details, WSL distro names, and transient shell quoting mistakes were intentionally not preserved in this GitHub-facing summary.
