# 2026-06-11 - Usage Probes, Local WSL Publish, Provider Actions

## Key Information

- Custom usage probing now supports a `probes` / multi-probe structure for combining multiple API responses into one usage result. Multiple enabled `usage` probes are allowed.
- Usage merge behavior was tightened so two single-record usage results with different `planName` values remain separate instead of overwriting each other. Same-name records or records without conflicting names may still merge.
- Provider row action buttons should stay close to upstream behavior: hidden by default, visible on hover/focus, and visible for active/configured highlighted rows. Avoid changing the action set or layout unless explicitly requested.
- Review findings should be fixed as part of the same delivery when the fix is low-risk and does not need user confirmation.

## Project Changes

- `src-tauri/src/usage_probe.rs`
  - Allows multiple enabled `usage` probes.
  - Keeps distinct named single-plan records instead of merging them into one overwritten result.
  - Added/updated coverage for distinct named usage records.
- `src/components/providers/ProviderCard.tsx`
  - Replaced brittle `group-hover`-only action visibility with component state for hover/focus.
  - Keeps actions visible for current/active/configured rows.
- `tests/components/ProviderCard.test.tsx`
  - Covers initial hidden state, hover reveal, active provider visibility, and additive-mode configured-row visibility.
- `scripts/publish-local-wsl-ccs-web.ps1`
  - Standard one-click local WSL container publish script.
  - Performs Web UI, API health, proxy port, and served-build consistency checks.
- `Dockerfile.web`
  - Uses `pnpm-lock.yaml` and `pnpm-workspace.yaml` with `pnpm install --frozen-lockfile` so container builds match the project lockfile.
- `AGENTS.md`
  - Records public-project safety rules: do not commit local paths, local distro names, private hosts, tokens, personal repository owners, or raw local evidence.
  - Records that local WSL container publishing should go through the one-click publish script.
  - Records that GitHub-facing docs must use placeholders rather than local machine details.

## Verification

- `pnpm vitest run tests/components/ProviderCard.test.tsx tests/components/ProviderList.test.tsx` passed.
- `pnpm typecheck` passed.
- `pnpm build:web` passed.
- `cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe` passed earlier in this session.
- `scripts/verify-official-upstream-alignment.ps1` passed earlier in this session.
- One-click local WSL publish completed successfully with:
  - Web UI health: 200
  - API health: `{"result":{"enabled":true}}`
  - Proxy port reachable
  - Served build check: local and served Vite entry assets matched.

## Decisions

- Do not change the real desktop updater endpoint in `src-tauri/tauri.conf.json` without explicit user confirmation, because replacing it with a placeholder would affect the desktop update path.
- Public docs should not preserve local machine names, local filesystem paths, WSL distro names, personal GitHub fork owners, private IPs, tokens, or raw local logs. Use examples such as `<wsl-distro>`, `<repo-path>`, `<fork-owner>`, and `<host>`.
- For local publishing, health checks alone are insufficient; the publish script should also prove the served frontend is the freshly built one.

## Dropped Noise

- Long Docker build logs, WSL warning noise, and repeated status updates were intentionally not preserved.
- Local machine-specific values were omitted from this public repo summary.
