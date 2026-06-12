# CCS Official Upstream Migration

## Decision

Use official `farion1231/cc-switch` as the primary upstream from now on.

`ccs-web` is retained only as an auxiliary reference for:

- historical fork behavior;
- comparing older v3.15 fork changes;
- recovering context for local overlays that originally came from the fork line.

## Local Remotes

Expected local remote layout:

```text
origin             https://github.com/<fork-owner>/ccs-gateway-web.git
upstream           https://github.com/farion1231/cc-switch.git
ccs-web-reference  https://github.com/cp-yu/cc-switch-web.git
```

`upstream` and `ccs-web-reference` should have disabled push URLs.

## Upgrade Flow

1. Fetch official upstream tags and branches.
2. Create a dedicated upgrade branch from the local main branch.
3. Compare official upstream against the current local fork first.
4. Reapply or reconcile local overlays listed in `docs/ccs-fork-overlay-ledger.md`.
5. Consult `ccs-web-reference` only when historical fork behavior explains a conflict.
6. Run grouped validation from `docs/ccs-local-change-groups.md`.

## Current Target

Official GitHub Releases currently show `v3.16.2` as the latest release dated 2026-06-08.

## Current Fetch Status

Local `git fetch upstream --tags` failed with:

```text
fatal: unable to access 'https://github.com/farion1231/cc-switch.git/': Recv failure: Connection was reset
```

This happened both with command environment proxy variables and with git command-level proxy flags for `<proxy-host>:<proxy-port>`.

Proxy checks on 2026-06-09 showed:

- TCP proxy `<proxy-host>:<proxy-port>` is reachable.
- GitHub release pages and the `v3.16.2` source archive are reachable through the proxy.
- Git smart HTTP access still resets for `git ls-remote` / `git fetch`.

Proxy retry on 2026-06-09 with command-level proxy variables and explicit Git proxy flags still failed for Git smart HTTP:

```powershell
$env:HTTP_PROXY='http://<proxy-host>:<proxy-port>'
$env:HTTPS_PROXY='http://<proxy-host>:<proxy-port>'
$env:ALL_PROXY='socks5://<proxy-host>:<proxy-port>'
rtk git ls-remote --tags upstream "v3.16.2"
rtk git -c http.proxy=http://<proxy-host>:<proxy-port> -c https.proxy=http://<proxy-host>:<proxy-port> ls-remote --tags upstream "v3.16.2"
```

Both Git attempts ended with:

```text
Recv failure: Connection was reset
```

Archive download through the same command-level proxy path remained usable, so the official `v3.16.2` source archive is the current local source of truth until `git fetch upstream` becomes stable again.

As a fallback, the official `v3.16.2` source archive was downloaded and extracted to:

```text
.upstream/cc-switch-v3.16.2
```

The local archive zip currently used for fallback comparison is:

```text
.upstream/cc-switch-v3.16.2.zip
SHA256: 9589AD28CE3F9D44F1A6C57A45AB6212CE17FB5E6B0A61CEAE9DA00D6A897431
```

`scripts/verify-official-upstream-alignment.ps1` verifies this zip hash and asserts that the extracted official `package.json` and `src-tauri/tauri.conf.json` both report version `3.16.2`.

`.upstream/` is a local comparison cache only. It must stay ignored by git, excluded from Vitest discovery, and absent from source-controlled or release-packaged inputs.

`.upstream/extract-v315` is a local historical comparison cache from the old 3.15 line; it is not a tracking source and must remain ignored with the rest of `.upstream/`.

## Desktop Updater Policy

Desktop updater endpoints must point at the fork release channel, not the official upstream release channel. The fork carries local overlay behavior, so a fork build must not auto-update users into official `farion1231/cc-switch` desktop artifacts.

Current fork endpoint:

```text
https://github.com/<fork-owner>/ccs-gateway-web/releases/latest/download/latest.json
```

Before publishing desktop updater artifacts, verify that the fork release channel publishes `latest.json` and updater artifacts signed by the configured updater key, or rotate the configured updater key and release signing key together.

Retry when GitHub connectivity is stable:

```powershell
rtk git fetch upstream --tags
rtk git ls-remote --tags upstream "v3.16*"
```

Latest proxy retry on 2026-06-09:

```powershell
$env:HTTP_PROXY='http://<proxy-host>:<proxy-port>'
$env:HTTPS_PROXY='http://<proxy-host>:<proxy-port>'
$env:ALL_PROXY='socks5://<proxy-host>:<proxy-port>'
rtk git fetch upstream --tags --prune --verbose
```

Result:

```text
fatal: unable to access 'https://github.com/farion1231/cc-switch.git/': Recv failure: Connection was reset
```

Additional proxy retry on 2026-06-10:

```powershell
$env:HTTP_PROXY='http://<proxy-host>:<proxy-port>'
$env:HTTPS_PROXY='http://<proxy-host>:<proxy-port>'
$env:ALL_PROXY='socks5://<proxy-host>:<proxy-port>'
rtk git fetch upstream --tags --prune
rtk cargo test --manifest-path crates/core/Cargo.toml
```

Result:

- Git smart HTTP still failed with `Recv failure: Connection was reset`.
- The online `crates/core` test path passed with `6 passed`, so Cargo dependency access is no longer blocked for that crate. Keep `-OfflineCargo` only as an explicit fallback for future GitHub or crates.io reset events.

## Current Integration Status

| Area | Local status | Evidence / remaining condition |
|------|--------------|--------------------------------|
| Official upstream source | Locally validated from official `v3.16.2` archive | `scripts/verify-official-upstream-alignment.ps1` verifies archive SHA256 and extracted official versions. Git smart HTTP fetch still resets and must be retried when connectivity is stable. |
| Core/Web integration | Local gate covered | TypeScript, Vitest, Rust core/server/src-tauri targeted tests, Web build, and grouped release gate have passed in local validation runs. |
| Secret scan | Local regex preflight covered | `scripts/ccs-secret-preflight.sh` checks tracked plus untracked files when `CCS_PREFLIGHT_SCOPE=all`; `gitleaks` is not installed in the current environment. |
| Docker runtime | Local runtime gate covered | Included in `scripts/verify-ccs-3-16-2-release-gate.ps1`; production host deployment remains a separate operation. |
| S3 live sync | External condition | Ignored live tests require real `S3_TEST_*` credentials and endpoint before release evidence can be claimed. |
| OpenClaw target host | External condition | Local presets and proxy paths are tested; target-host smoke with the real OpenClaw environment is still required. |
| Desktop installer/update signing | External condition | Local no-bundle desktop checks are not a substitute for signed updater artifacts and installed desktop smoke. |

Implemented from official `v3.16.2` archive:

- Codex Responses -> Chat Completions request conversion in the forwarder.
- Codex Chat -> Responses response conversion for `/responses` and `/responses/compact`.
- Codex Chat history replay/recording for function-call continuity.
- Codex Chat reasoning config metadata on providers.
- S3 sync settings and key normalization.
- Usage event bridge refresh after backend usage log writes.
- `zh-TW` settings language support.
- Local `service_tier` passthrough and Responses provider stickiness remain covered by tests.

Validation run on 2026-06-09:

```powershell
rtk powershell -NoProfile -Command "& .\node_modules\.bin\tsc.cmd --noEmit"
rtk cargo check --manifest-path src-tauri/Cargo.toml --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml codex_chat --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml codex_provider --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml responses_session --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml service_tier --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml codex_proxy_error --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml s3 --lib
rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run tests/hooks/useSettingsForm.test.tsx tests/hooks/useUsageEventBridge.test.tsx tests/hooks/useSettings.test.tsx tests/components/WebdavSyncSection.test.tsx tests/integration/App.test.tsx tests/components/ProviderForm.codexMeta.test.tsx tests/config/codexTemplates.test.ts tests/config/codexChatProviderPresets.test.ts tests/config/therouterProviderPresets.test.ts tests/config/therouterOpenCodeOpenClawPresets.test.ts tests/utils/deepClone.test.ts tests/utils/usageDisplay.test.ts src/lib/version.test.ts"
rtk powershell -NoProfile -Command "& .\node_modules\.bin\vitest.cmd run"
rtk powershell -NoProfile -Command "& .\node_modules\.bin\vite.cmd build --mode web"
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1
```

Result: all commands passed. Cargo still reports pre-existing unused-code warnings.

Vitest excludes `.upstream/**` globally so the extracted official source archive cannot pollute local test results.

Full frontend validation now reports 46 passed test files / 245 passed tests. Web build completed successfully.

Official upstream alignment gate reports `official_upstream_alignment=ready`.

Additional full Rust library sweep attempted on 2026-06-09:

```powershell
rtk cargo test --manifest-path src-tauri/Cargo.toml --lib -- --test-threads=1
```

Initial result: 1385 passed, 1 failed, 2 ignored. The failure was a test isolation issue in `services::provider::tests::update_current_claude_provider_syncs_live_when_proxy_takeover_detected_without_backup`, where the test tried to start the proxy on a port already in use:

```text
启动代理服务器失败: 地址绑定失败: 通常每个套接字地址(协议/网络地址/端口)只允许使用一次。 (os error 10048)
```

The test now uses an unused loopback port for the proxy takeover fixture. Follow-up validation:

```powershell
rtk cargo test --manifest-path src-tauri/Cargo.toml update_current_claude_provider_syncs_live_when_proxy_takeover_detected_without_backup --lib
rtk cargo test --manifest-path src-tauri/Cargo.toml --lib -- --test-threads=1
```

Result: both commands passed. Full Rust library sweep now reports 1390 passed, 2 ignored.
