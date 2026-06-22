# 2026-06-22 - Usage UI Local Publish Review

## Key Information
- Scope: fixed and reviewed the web usage statistics toolbar refresh interval and filter display regression.
- The usage dashboard default refresh interval is now 5 seconds, not 30 seconds.
- The refresh interval menu includes a top-level off option before timed intervals.
- Usage toolbar i18n keys are present for source/model filters, all-source/all-model labels, refresh interval label, and refresh-off label.
- The local container publish path remains the project-provided local WSL publish script; do not bypass it with ad-hoc release scripts.

## Important Information
- Targeted verification passed for the usage dashboard and i18n coverage: 2 test files, 6 tests.
- TypeScript verification passed with `pnpm tsc --noEmit --pretty false`.
- Web build verification passed before local publish.
- `git diff --check` passed.
- A full Vitest run still had an unrelated integration timeout outside the usage UI scope.
- During later re-verification, Vitest initially failed before collecting tests because the host could not spawn workers; rerunning the target tests with a single worker passed.

## Project Information
- Static web runtime was smoke-tested through the local web endpoint and returned HTTP 200.
- The loaded HTML referenced the expected freshly built asset bundle names.
- The deployed build was from the current dirty worktree, not an isolated usage-only diff. Future reviews should separate usage UI changes from proxy/image-fallback/release-script changes before staging or publishing.
- Browser verification of the post-login usage page was blocked by local web authentication. The unauthenticated check confirmed auth is enabled and the current browser session was not valid.

## Follow-ups
- If visual confirmation is needed, log into the local web UI and re-check the usage statistics page: no raw `usage.*` keys, source/model labels are localized, default refresh is `5s`, and the refresh menu contains `关闭`.
- Consider adding a low-concurrency verification profile for resource-constrained local release checks to reduce worker-spawn failures.
- Keep BuildKit cache pruning separate from runtime container deployment; pruning can save disk but may slow future rebuilds.

## Dropped Noise
- Raw container IDs, local hostnames, WSL distro names, private proxy addresses, command transcripts, and authentication-sensitive details were intentionally not preserved in this GitHub-facing summary.
