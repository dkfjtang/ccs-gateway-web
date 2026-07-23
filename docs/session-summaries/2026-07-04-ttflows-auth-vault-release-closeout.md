# 2026-07-04 - TTFlows Auth Vault Release Closeout

## Key Information

- Release commit: `6c21c2905bcc020421002e797df10cd969a8666f` (`fix: keep auth vault receive window open`).
- Product behavior accepted for this release: Auth Vault receive window stays open after one successful receive; operator can close it manually, otherwise it expires automatically after five minutes.
- User explicitly approved skipping the Auth Vault special smoke test. Record this as a release caveat, not as a blocker.
- TTFlows CCS image activated: `ccs-gateway-web:slim-6c21c290-authvault-20260704-174539-ttflows`.
- Rollback container was retained; do not clean old rollback artifacts unless explicitly asked.
- Preserve image-only release boundary for this release family: no NGINX, env, compose, data, or OpenClaw mutation beyond replacing the `ccs-web` container image.

## Important Information

- Final read-only remote verification passed from `<repo-root>/.run/ttflows-ccs-final-readonly-check-6c21c290-20260704-200517.log`.
- Final verification evidence:
  - active container image matched the release image
  - rollback container existed
  - web health returned HTTP `200`
  - `build-info` profile was `slim`
  - Web auth was enabled
  - unauthenticated `get_settings` returned `401`
  - proxy `/status` returned `200`
  - `/v1/responses` smoke with production runbook model `gpt-5.5` returned HTTP `200` and matched the sentinel on attempt 1
- A failed read-only smoke using `gpt-4.1-mini` was diagnosed as using the wrong production smoke model. Future TTFlows CCS release smokes should follow the runbook model path (`gpt-5.5`) unless the production contract changes.
- `main` was pushed to `origin/main`; post-push `origin/main...HEAD` was `0 0`.
- Branch/worktree cleanup state after push: only `main` branch remained; `git worktree list` showed only the primary repo worktree; `git worktree prune` was run.

## Verification Commands

- `git diff --check origin/main...HEAD`
- `cargo fmt --manifest-path crates/core/Cargo.toml -- --check`
- `cargo fmt --manifest-path crates/server/Cargo.toml -- --check`
- `pnpm run check:locales`
- `pnpm vitest run tests/tools/edgeTokenCapturePolicy.test.ts`
- `cargo test --manifest-path crates/server/Cargo.toml --lib auth_vault`
- `cargo test --manifest-path crates/server/Cargo.toml --test slim_routes`
- `bash scripts/ccs-secret-preflight.sh`
- `git merge --ff-only origin/main`
- `git push origin main`

## Known Caveats

- `cargo test --manifest-path crates/server/Cargo.toml auth_vault` compiles unrelated server integration test targets and hit existing crate import/rlib resolution issues. Use the narrower `--lib auth_vault` and `--test slim_routes` checks for this release slice unless the broader integration-test setup is fixed.
- Auth Vault special smoke was skipped by user approval, so this remains a declared test gap for the release.

## Follow-ups

- If revisiting Auth Vault remote-extension behavior, run the skipped special smoke against the real browser-extension path.
- Consider fixing the broader server integration-test target import setup separately; do not conflate that cleanup with this release.

## Dropped Noise

- Raw SSH output, local absolute paths, remote host details, private network bindings, credentials, cookies, and full runtime logs were intentionally not preserved in this tracked summary.
