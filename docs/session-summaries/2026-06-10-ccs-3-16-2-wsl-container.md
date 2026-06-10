## 2026-06-10 - CCS 3.16.2 upstream alignment and WSL container publish

### Key Information
- Repo: `F:\development\ccs-gateway-web`.
- Branch used during the work: `codex/ccs-3.16.2-align`.
- Official upstream decision: track `https://github.com/farion1231/cc-switch.git` as the primary upstream; keep `https://github.com/cp-yu/cc-switch-web.git` only as historical/reference material.
- Target version: `3.16.2-ccs-gateway.1`.
- Official Git smart HTTP fetch to GitHub still reset during this work. Local source of truth for upstream comparison is `.upstream/cc-switch-v3.16.2.zip`, validated by SHA256 `9589AD28CE3F9D44F1A6C57A45AB6212CE17FB5E6B0A61CEAE9DA00D6A897431` and extracted official versions.
- Container publish target is local WSL Docker test environment. The user explicitly required not changing container configuration.

### Implemented / Preserved Changes
- `README.md` now states official `farion1231/cc-switch` is the primary tracked upstream and `cp-yu/cc-switch-web` is reference only.
- `docs/user-manual/README.md`, `docs/user-manual/en/README.md`, `docs/user-manual/zh/README.md`, and `docs/user-manual/ja/README.md` now report `v3.16.2-ccs-gateway.1`.
- `docs/ccs-official-upstream-migration.md` now contains a local-vs-external release status table.
- `crates/server/src/api/ws.rs` was fixed so WebSocket `event.subscribe` / `event.unsubscribe` update the shared subscription set used by the event forwarding task.
- `crates/server/tests/ws_event_subscription.rs` was added to verify a subscribed WebSocket receives matching event notifications.
- `scripts/ccs-secret-preflight.sh` was hardened so `CCS_PREFLIGHT_SCOPE=all` scans tracked plus untracked files and includes stronger AWS/S3 secret patterns.

### Multi-Agent / Multi-Angle Review Rounds
- Product review found upstream identity and user manual version drift; both were corrected.
- Project/change grouping review found `docs/ccs-local-change-groups.md` did not cover the dirty worktree breadth; the document was expanded with grouped staging guidance.
- Test review found no local P0/P1 blockers, but retained external conditions for S3 live tests, OpenClaw target-host smoke, and desktop signing/installed smoke.
- Security/code review found the WebSocket event subscription bug and weaker secret preflight coverage; both were fixed.
- Ops review found `CCS_PREFLIGHT_SCOPE=all` skipped untracked files; this was fixed.

### Validation Evidence
- `rtk cargo fmt --manifest-path crates/server/Cargo.toml --check`: passed.
- `rtk cargo test --manifest-path crates/server/Cargo.toml`: passed, 14 tests.
- `rtk cargo test --manifest-path crates/core/Cargo.toml`: passed, 6 tests.
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1`: passed with `official_upstream_alignment=ready`.
- `rtk wsl.exe -d Ubuntu-24.04 -- bash -lc 'cd /mnt/f/development/ccs-gateway-web && CCS_PREFLIGHT_SCOPE=all ./scripts/ccs-secret-preflight.sh'`: passed. `gitleaks` was not installed, so only local regex preflight ran.
- `rtk git diff --check`: passed.
- `rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-ccs-3-16-2-release-gate.ps1`: first run timed out at 10 minutes; re-run with a 20-minute command timeout passed in about 470 seconds.

### WSL Container Publish
- Built existing compose image without changing container config: `docker compose -f docker-compose.ccs-web.yml build`.
- Started existing compose service: `docker compose -f docker-compose.ccs-web.yml up -d`.
- Published image: `ccs-gateway-web:local`, image ID observed as `6e06d3f5d516`.
- Container: `ccs-gateway-web`.
- Ports from existing compose config: `127.0.0.1:17666->17666` and `127.0.0.1:15721->15721`.
- Final Windows-side check: `curl.exe -I --max-time 5 http://127.0.0.1:17666/health` returned `HTTP/1.1 200 OK`.
- Final WSL-side check: `curl -I --max-time 5 http://127.0.0.1:17666/health` returned `HTTP/1.1 200 OK`.
- Final publish probe passed: `CCS_TARGET_NAME=local-wsl-test CCS_CONTAINER_NAME=ccs-gateway-web ./scripts/ccs-prod-probe.sh`.
- Probe showed `auth.status` as `{"result":{"enabled":false}}`; this was left unchanged because the user requested not changing container config and this is a test environment.
- `git status --short -- docker-compose.ccs-web.yml Dockerfile.web .dockerignore` produced no output after publish checks, confirming those container config files were not modified.

### Observations / Risks
- During initial post-publish access, `http://127.0.0.1:17666/health` intermittently failed while the container was in a short startup/restart window. Later checks showed the container was up for 8 minutes and both Windows/WSL health probes passed.
- WSL printed a localhost/NAT warning with garbled encoding in some commands. This did not block final Windows localhost access, but it is worth remembering if localhost forwarding becomes intermittent.
- Docker logs showed repeated startup banners from earlier short lifecycle attempts, but final probe succeeded and the service was reachable.

### External Conditions Not Locally Proven
- S3 live roundtrip requires real `S3_TEST_*` values.
- OpenClaw target-host smoke still needs the real target environment.
- Desktop signing, updater artifact, and installed desktop smoke are still separate release-host validations.
- Upstream Git fetch should be retried when GitHub smart HTTP connectivity is stable.

### Dropped Noise
- Raw long command logs, PowerShell quoting mistakes, transient curl failures during container startup, and garbled WSL warning bytes were not preserved beyond their durable conclusions above.
