# CCS Caveman Release Readiness

## Decision

Caveman prompt-level mode control is ready to proceed to formal release approval.
It must not be shipped as proxy response rewriting.

## User-Facing Capability

- Users can choose a Caveman mode in the Prompt panel:
  - Lite
  - Full
  - Ultra
- Choosing a mode creates the matching prompt preset if needed, then enables it for the current app.
- Choosing another mode switches the enabled prompt to that mode through the existing prompt enable path.
- Turning Caveman off is a real disable action: it disables the active Caveman prompt preset without deleting it, and leaves the user in a non-Caveman live prompt state.
- Caveman presets remain normal prompt records and can still be inspected or edited by the user.

## Non-Negotiable Boundaries

- No streamed response chunk mutation.
- No final response JSON mutation.
- No OpenAI Responses item mutation.
- No usage parser changes.
- No silent production default.
- No proxy runtime dependency on `caveman_output_compression`.

## Acceptance Criteria

1. Caveman has visible user controls for mode selection and off state.
2. Mode selection works when the preset already exists.
3. Mode selection works when the preset does not exist.
4. Off state disables the active Caveman preset without deleting it.
5. Caveman prompt presets are disabled at creation time until explicitly enabled by the UI flow.
6. Proxy runtime contains no Caveman response rewriting path.
7. Token Saver gates still pass because Caveman shares the release surface with token-cost controls.
8. Frontend typecheck passes.
9. Two rounds of independent review/test cross-checks are completed before release recommendation.
10. The Prompt panel flow is covered through the real prompt hook and transport boundary, not only by a mocked component API call test.
11. The Web Server/API path can create, enable, switch, and turn off Caveman against an isolated real config directory.
12. The Web UI path can open the OpenClaw Prompt panel, select Lite/Full/Ultra, and turn Caveman off against the real Web Server/API state.
13. The desktop packaging path gets past Tauri JS/Rust version matching, frontend production build, Rust release compilation, and installer generation for the Caveman UI bundle.

## Evidence Map

| Acceptance criterion | Evidence |
| --- | --- |
| 1, 2, 3, 4 | `tests/components/PromptPanel.test.tsx`; `tests/components/PromptPanel.integration.test.tsx`; `src-tauri/src/services/prompt.rs` caveman service tests |
| 5 | `src-tauri/src/prompt.rs` caveman tests |
| 6 | `scripts/verify-token-cost-savers.ps1` static proxy and provider runtime searches |
| 7 | `scripts/verify-token-cost-savers.ps1` token saver and filter tests |
| 8 | `scripts/verify-token-cost-savers.ps1` frontend typecheck step; `vite build --mode web` |
| 9 | Round 1, Round 2, incremental, and final independent review/test notes below |
| 10 | `tests/components/PromptPanel.integration.test.tsx` uses the real `usePromptActions` hook and a Tauri-mode test transport to verify visible controls, create/enable, mode switch, off-without-delete, and live prompt clearing |
| 11 | `scripts/verify-caveman-api-smoke.ps1` starts the Web Server with isolated `CC_SWITCH_TEST_HOME` and exercises `get_prompts`, `create_caveman_style_profile`, `enable_prompt`, `upsert_prompt`, and `get_current_prompt_file_content` through `/api/invoke`. The smoke script now checks that the target local port is free before starting, and uses a configurable startup timeout, defaulting to 180 seconds, so cold Rust builds do not get misclassified as API failures. |
| 12 | `scripts/verify-caveman-ui-smoke.ps1` starts the Web Server with isolated `CC_SWITCH_TEST_HOME`, builds web assets, opens the real Web UI in system Edge, enters OpenClaw Prompts, clicks Full -> Lite -> Ultra -> Turn off, and verifies backend prompt/live-file state after each click |
| 13 | `scripts/verify-caveman-desktop-preflight.ps1` checks the aligned Tauri JS package versions, writes a reproducible npm-based Tauri build config, and runs `tauri build --no-bundle` with an isolated `CARGO_TARGET_DIR`. Latest local run passed with `desktop_preflight=artifact_build_no_bundle_passed`. A full `npm exec -- tauri build --config .run\caveman-desktop-preflight\tauri-npm-build-config.json` then built `src-tauri\target\release\cc-switch.exe` and produced MSI/NSIS installers before failing only at updater signing because `TAURI_SIGNING_PRIVATE_KEY` is not present in this local environment. |

## Release Risk

- Main product risk: users may assume the reserved advanced optimizer field is the Caveman switch.
  Mitigation: UI copy says mode selection is in the Prompt panel and proxy responses are not rewritten.
- Main engineering risk: future refactors accidentally wire Caveman into proxy/provider runtime.
  Mitigation: release verifier fails if Caveman appears in `src-tauri/src/proxy` outside `types.rs`, `src-tauri/src/provider.rs`, or `src-tauri/src/session_manager/providers`.
- Main behavior risk: mode switching could overwrite an existing prompt file.
  Mitigation: implementation uses the existing prompt enable path, which already backs up live prompt content before switching.
- Shell-packaging risk: automated UI evidence now covers the Web UI through the Web Server/API path, and the desktop release build now produces local MSI/NSIS installer artifacts, but updater signing still requires the release private key.
  Mitigation: Tauri JS package versions were aligned to the Rust-side 2.10/2.6 minor line, and `scripts/verify-caveman-desktop-preflight.ps1` now makes the desktop preflight reproducible. Latest local run passed through `tauri build --no-bundle` with `desktop_preflight=artifact_build_no_bundle_passed`. A full local `tauri build` produced the MSI and NSIS installers and failed only after that point because `TAURI_SIGNING_PRIVATE_KEY` is intentionally absent locally. The release build host must provide that secret to sign updater artifacts.
- Release-scope risk: this working branch also contains token-cost/request optimizer changes in proxy/provider-adjacent files.
  Mitigation: keep the Caveman release conclusion scoped to prompt/style-profile control only. If token saver or proxy request mutation changes ship in the same batch, review them under their own optimizer release gate.
- Token-saver side-effect risk: JSON Schema underscore preservation now targets recognized direct `properties` paths, while deeper composed schemas may still need future coverage.
  Mitigation: keep this as non-blocking for Caveman because Caveman no longer depends on proxy response rewriting; track it as token-saver hardening under the optimizer release scope.
- Cost-saving regression risk: unknown or object-shaped output is intentionally compressed more conservatively.
  Mitigation: accept lower savings for safer structured output behavior; measure savings separately from Caveman release readiness under the optimizer release scope.

## Rollback

1. Disable the active Caveman prompt preset in the Prompt panel.
2. If needed, delete Caveman prompt presets after they are disabled.
3. No database migration is required.
4. No proxy restart is required for Caveman itself because it does not mutate proxy runtime responses.

## Cross-Review Evidence

### Round 1

- `review-assistant`: no blocking issues. Conclusion: conditional release. Follow-up requests were mode-switch coverage, normal prompt interaction coverage, and avoiding broad `caveman-*` id matching.
- `test-assistant`: AC 1-8 passed from automated evidence. AC 9 remained pending until a second independent review/test round. It requested real UI/Tauri state-chain validation and another proxy rewriting scan.

Follow-up actions completed after round 1:

- Added component coverage for switching from one active Caveman mode to another existing mode.
- Hardened Caveman detection to the fixed system ids: `caveman-lite`, `caveman-full`, `caveman-ultra`.
- Added service-layer coverage for `create_caveman_style_profile -> enable_prompt -> prompt file -> enabled state`.
- Added service-layer coverage for turning Caveman off without deleting the preset and clearing the live prompt file when no prompt remains enabled.

### Round 2

- `test-assistant`: reran the full verifier. Evidence at that time: `token_saver` 22 passed, `token_filter_engine` 12 passed, `caveman` 4 passed, `PromptPanel` 4 passed, `tsc --noEmit` passed, fixture JSON passed, Caveman proxy static search passed, and the Token Saver hook count remained one.
- `test-assistant` AC result: AC 2-8 passed from automated evidence. AC 1 passed at code/component-test level but still needs a real UI smoke check. AC 9 remains incomplete until the second review-assistant result is recorded.
- `review-assistant`: no blocking issues. Evidence cited fixed Caveman ids, mode create/enable/off flow, default-disabled prompt creation, command-layer mode allowlist, service-layer prompt file coverage, and proxy static search. Conclusion: conditional release until real UI/Tauri chain validation is performed.

Additional main-agent evidence after round 2:

- `vite build --mode web` passed and produced a `PromptPanel` bundle chunk.
- Static proxy search for `caveman|Caveman|caveman_output_compression` under `src-tauri/src/proxy --glob !types.rs` returned no matches.
- Documentation search removed stale claims that the current UI only creates disabled presets requiring a separate manual enable step.
- Command-layer parser coverage rejects unknown Caveman modes outside `lite`, `full`, and `ultra`.
- Final enhanced verifier after command parser coverage passed with `caveman` 5 passed and `PromptPanel` 4 passed.
- Added `tests/components/PromptPanel.integration.test.tsx` after the round 2 findings. This test does not mock `usePromptActions`; it installs a Tauri-mode test transport and verifies the full Prompt panel flow:
  - Lite, Full, Ultra, and Turn off controls are visible.
  - Selecting a missing mode creates and enables that preset.
  - Switching to another missing mode creates it, enables it, and disables the previous Caveman mode.
  - Turning Caveman off keeps the preset record and clears the simulated live prompt file when no prompt remains enabled.
- `scripts/verify-token-cost-savers.ps1` now runs both the API-call component test and the runtime-flow Prompt panel test.
- Incremental review after the runtime-flow test found one test-quality issue: the test transport singleton had to be reset after the integration test. It also requested asynchronous assertions in the create-mode component test and stronger UI-visible assertions in the runtime-flow test.
- Follow-up fixes completed:
  - `tests/components/PromptPanel.integration.test.tsx` now resets `__setTransportForTesting(null)` in `afterEach`.
  - `tests/components/PromptPanel.test.tsx` wraps create-then-enable assertions in `waitFor`.
  - `tests/components/PromptPanel.integration.test.tsx` now also asserts active and use-existing button states after mode changes/off.
  - `scripts/verify-token-cost-savers.ps1` now scans provider runtime paths in addition to proxy runtime paths.
- Latest full verifier after these fixes passed:
  - `token_saver`: 22 passed
  - `token_filter_engine`: 12 passed
  - `caveman`: 5 passed
  - `PromptPanel.test.tsx`: 4 passed
  - `PromptPanel.integration.test.tsx`: 1 passed
  - frontend typecheck: passed
  - fixture JSON validation: passed
  - Caveman proxy static search: passed
  - Caveman provider runtime static search: passed
  - Token Saver forwarder hook count: exactly one
- Latest web build passed with a generated `PromptPanel` bundle chunk.
- Added `scripts/verify-caveman-api-smoke.ps1` to make the real Web Server/API smoke reproducible without shell JSON quoting. Latest run passed with:
  - isolated config dir: `.run/caveman-api-smoke\.openclaw`
  - `caveman-full` created as disabled, then enabled
  - switch to `caveman-lite` enabled Lite and disabled Full
  - turn off retained the Lite preset and cleared the live prompt file
- Added `scripts/verify-caveman-ui-smoke.ps1` to make the real Web UI flow reproducible. Latest run passed with:
  - system browser: `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`
  - isolated config dir: `.run\caveman-ui-smoke\.openclaw`
  - screenshots: `.run\caveman-ui-smoke\screenshots\00-home.png`, `01-openclaw-prompts.png`, `02-caveman-full.png`, `03-caveman-lite.png`, `04-caveman-ultra.png`, `05-caveman-off.png`
  - evidence manifest: `.run\caveman-ui-smoke\caveman-ui-smoke-evidence.json`, including SHA256 hashes for each screenshot
  - UI path: OpenClaw -> Prompts -> Full -> Lite -> Ultra -> Turn off
  - backend assertions: `ui_full=ok`, `ui_lite=ok`, `ui_ultra=ok`, `ui_off=ok`
- Replaced the local Docker test environment with the current worktree image `ccs-gateway-web:local`, container `ccs-gateway-web`, mounted `/root/.openclaw` as writable for prompt-file testing, and ran `scripts/verify-caveman-deployed-smoke.ps1` against the deployed environment through `http://127.0.0.1:17666/api/invoke`. Evidence: `.run\caveman-deployed-smoke\current.json`. The deployed smoke now snapshots the starting prompt state and restores it by default after proving the Caveman flow, so it should not leave test-created Caveman presets or clear a user's pre-existing enabled prompt.
  - `fullEnabled=true`
  - `liteEnabled=true`, `liteDisabledFull=true`
  - `ultraEnabled=true`, `ultraDisabledLite=true`, `ultraDisabledFull=true`
  - `turnOffRetainedProfiles=true`, `turnOffDisabledAllCavemanProfiles=true`, `turnOffClearedLivePrompt=true`
  - the measured off state keeps `caveman-full`, `caveman-lite`, and `caveman-ultra` present but disabled during the smoke assertion, then the script restores the pre-smoke deployed prompt state before exiting.
- Added `scripts/verify-caveman-deployed-smoke-restores-existing-prompt.ps1` as a deployed-state restoration probe. It first creates and enables a normal non-Caveman prompt in the deployed Docker OpenClaw state, runs `verify-caveman-deployed-smoke.ps1`, then asserts the normal prompt remains enabled and the live prompt content is restored before it finally restores the original deployed state. Evidence: `.run\caveman-deployed-smoke-restore\current.json`.
  - `baselineRestoredAfterSmoke=true`
  - `originalRestoredAfterProbe=true`
  - inner smoke evidence also shows `postRestorePromptIdsMatchInitial=true`, `postRestoreEnabledPromptIdsMatchInitial=true`, and `postRestoreLivePromptMatchesInitial=true` while a normal prompt was enabled.

### Incremental Cross-Check After Runtime-Flow Test

- `test-assistant`: reran `scripts/verify-token-cost-savers.ps1` and `vite build --mode web`. Conclusion: Caveman has enough automated evidence for a formal staged release argument; real desktop UI smoke is still recommended as a release-window check.
- `review-assistant`: no blocking code issues. Conclusion: conditional release before final desktop UI smoke. It recommended extending static checks beyond `src-tauri/src/proxy`, which has been implemented.
- Additional independent review found a test isolation issue in the runtime-flow test transport singleton. That issue has been fixed and the combined PromptPanel test run now passes in one Vitest invocation.

### Final Independent Cross-Check

- `test-assistant` reran the reproducible API smoke, full verifier, web build through the local Vite binary, and the combined PromptPanel Vitest files. Result: no automated failures.
- `test-assistant` AC result at that time: visible controls, missing-preset create/enable, existing-preset enable, mode switch, off-without-delete with live prompt clearing, no proxy/provider runtime rewriting, isolated API smoke config, and documentation alignment all passed from automated/API evidence. The desktop UI click path was still pass/weak at that point, before the later system Edge Web UI smoke and desktop packaging evidence were added.
- `review-assistant` found no blocking issues. It confirmed staged release can proceed, with non-blocking risks around final desktop smoke, deeper JSON Schema underscore handling, and conservative token-saver compression for unknown/object outputs.
- Final cross-check recommendation at that time: conditional release / staged release candidate. The later Web UI smoke and desktop packaging evidence below close the UI-chain and packaging-preflight gaps that drove this earlier condition.

### Web UI Smoke Cross-Check

- Main-agent verification added `scripts/verify-caveman-ui-smoke.ps1` and reran it successfully with system Edge. It proved the real Web UI can open OpenClaw Prompts, click Full, Lite, Ultra, and Turn off, and observe backend state changes after each action.
- Follow-up `review-assistant` found no Caveman prompt-level blockers. It independently confirmed:
  - Caveman is not wired into proxy/provider response rewriting.
  - Turn off is not a UI-only fake; it calls the existing disable path and clears the live prompt file when no prompt remains enabled.
  - Web UI smoke covers Web Server/API plus system Edge, while packaged Tauri shell remains a separate sanity check.
- Follow-up `review-assistant` release conclusion: conditional release. The condition is release-scope clarity: this conclusion applies to Caveman prompt/style-profile control only. Token saver or proxy request optimizer changes in the same branch need separate optimizer release risk confirmation.
- Follow-up `test-assistant` AC result: pass for OpenClaw Prompt entry, Lite/Full/Ultra selection, real off semantics with preset retained and live prompt cleared, default-disabled Caveman preset creation, no Caveman proxy/provider response rewriting, and build/type/diff gates.
- Follow-up `test-assistant` release recommendation: conditional release. The test condition matches review: keep the Caveman release scope limited to prompt/style-profile control, and evaluate token saver/proxy optimizer changes under a separate release gate.

### Approval Packet Cross-Check

- Added `scripts\new-caveman-release-approval-packet.ps1` to combine the readiness audit, formal checklist, deployed Docker smoke evidence, existing-prompt restore probe evidence, and local aggregate gate summary into `.run\caveman-release-approval\caveman-release-approval-packet.json`.
- Latest packet generation returned `caveman_release_approval_status=conditional_caveman_only_ready_for_release_host_approval`, `localEvidenceStatus=local_caveman_evidence_present`, `formalReleaseReadiness=formal_release_prerequisites_blocked`, and blockers `release_signing_manifest_invalid,installed_app_path_missing`.
- Follow-up `review-assistant` found no P0/P1 blockers in the approval packet or gate chain. It confirmed the packet does not package local evidence as a formal release pass, still depends on deployed smoke, restore probe, readiness, and local gate summary, and preserves signing/updater signature/installed smoke/final aggregate gate blockers.
- The same review found one P2: the packet's `finalGateCommand` was too short for release-host operators to copy. Follow-up fixed it to include `-ReleaseSigningManifestPath`, `-InstalledAppPath`, `-InstalledSmokeEvidenceDir`, and all installed-app confirmation switches.
- `scripts\verify-caveman-release-hardening.ps1` now asserts the approval packet remains conditional/blocked and that its final gate command includes the required release-host arguments. Latest hardening run passed with `approval_packet_reports_conditional_status=ok` and `release_hardening=passed`.

### Desktop Packaging Preflight

- First desktop build attempt failed before compilation because Tauri detected JS/Rust package minor mismatches:
  - `tauri` 2.10.x vs `@tauri-apps/api` 2.8.x
  - `tauri-plugin-dialog` 2.6.x vs `@tauri-apps/plugin-dialog` 2.4.x
  - `tauri-plugin-updater` 2.10.x vs `@tauri-apps/plugin-updater` 2.9.x
- Follow-up fix aligned JS package declarations and locks:
  - `@tauri-apps/cli`: `2.10.1`
  - `@tauri-apps/api`: `2.10.1`
  - `@tauri-apps/plugin-dialog`: `2.6.0`
  - `@tauri-apps/plugin-updater`: `2.10.1`
- After alignment, `scripts/verify-caveman-desktop-preflight.ps1 -AllowEnvironmentBlocked` passed the Tauri JS package-version checks, wrote `.run\caveman-desktop-preflight\tauri-npm-build-config.json`, completed `npm run build:renderer`, and completed Rust release compilation through `tauri build --no-bundle`.
- The latest local desktop preflight no longer hits the earlier Windows `os error 5` build-script execution block. It returned:

```text
desktop_preflight=artifact_build_no_bundle_passed
```

The CI/release-host command for the same gate is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-desktop-preflight.ps1
```

- Full local bundle command, rerun after the final off-state regression fix:

```powershell
rtk powershell -NoProfile -Command "npm exec -- tauri build --config .\.run\caveman-desktop-preflight\tauri-npm-build-config.json"
```

This completed renderer build, Rust release compilation, and installer generation on the post-fix tree:

```text
Built application at: <repo-root>\src-tauri\target\release\cc-switch.exe
<repo-root>\src-tauri\target\release\bundle\msi\CC Switch_3.14.1_x64_en-US.msi
<repo-root>\src-tauri\target\release\bundle\nsis\CC Switch_3.14.1_x64-setup.exe
```

The command exited non-zero only after installer generation because updater signing requires the release secret:

```text
A public key has been found, but no private key. Make sure to set `TAURI_SIGNING_PRIVATE_KEY` environment variable.
```

### Final Review/Test Closeout

- Latest `review-assistant` found one P2 edge case: if persisted data somehow has both a Caveman preset and a normal prompt enabled, turning Caveman off should not leave the live prompt file on the Caveman content. Follow-up fix changed the disable path so the live file follows the remaining enabled prompt; if no prompt remains enabled, it clears the live file.
- Added regression coverage: `services::prompt::tests::caveman_turn_off_restores_remaining_enabled_prompt`.
- Latest Caveman Rust test result after the fix: `6 passed`.
- Latest `review-assistant` P3 test gap was Japanese Turn off label coverage in the UI smoke. Follow-up fix added `Caveman をオフ` to the smoke script button matcher.
- Latest `test-assistant` AC matrix passed the user-facing Caveman behavior and runtime-boundary checks. Its remaining conditions are release-scope controls: keep Token Saver/proxy optimizer out of the Caveman approval, run desktop installer smoke after installation, and provide `TAURI_SIGNING_PRIVATE_KEY` on the release build host for updater signing.
- Additional post-fix `test-assistant` reruns/复核 converged on the same result: all Caveman-only AC items pass, including Lite/Full/Ultra selection, create-and-enable, existing-preset enable, mutually exclusive mode switching, real Turn off semantics, disabled-by-default creation, backend mode allowlist, and no proxy/provider Caveman rewriting. Release recommendation remains conditional only because release signing and installed-app smoke are release-environment gates.
- Post-fix main-agent verification passed:
  - `scripts/verify-token-cost-savers.ps1`
  - `scripts/verify-caveman-api-smoke.ps1`
  - `scripts/verify-caveman-ui-smoke.ps1`
  - `scripts/verify-caveman-desktop-preflight.ps1`
  - `scripts/verify-caveman-release-signing.ps1 -SkipBuild` correctly fails locally because `TAURI_SIGNING_PRIVATE_KEY` is not present
  - `scripts/verify-caveman-release-signing.ps1 -SkipBuild` with a fake `TAURI_SIGNING_PRIVATE_KEY` also fails locally when no real `.sig` artifact exists; this guards against treating the NSIS setup executable as updater-signing evidence
  - `scripts/verify-caveman-installed-smoke.ps1` correctly rejects an installer path as not being an installed app executable
  - `scripts/verify-caveman-release-hardening.ps1` covers release-gate negative controls for missing signing key during signing, missing matching `<setup.exe>.sig` in an isolated fake bundle, missing aggregate signing manifest, tampered signing manifest hashes, installed-path prefix spoofing such as `ProgramsFake`, missing installed-smoke evidence directory, empty installed-smoke evidence directory, repo artifacts, non-CC Switch executables, installer paths, `SkipBuild` signing manifests, and installed executables whose SHA256 does not match the signed build manifest app executable
  - `vite build --mode web`
  - `git diff --check`
- Post-fix full local `tauri build` regenerated both MSI and NSIS installers, then stopped only at updater signing because this local environment does not provide `TAURI_SIGNING_PRIVATE_KEY`.
- Additional independent review/test pass on the current tree:
  - `review-assistant` confirmed the release gate does not print `ready_for_formal_release` unless both signing and installed smoke are required, and did not find a mismatch in Lite/Full/Ultra/off behavior. It did find installed-smoke weaknesses in three passes: first, a fake installed exe plus any non-empty evidence file could satisfy the earlier evidence-dir check; second, an exe self-hash manifest still did not bind the installed smoke to the signed release artifacts; third, the signed installer and installed executable still needed a direct same-build hash binding. The current scripts address this by requiring `caveman-installed-smoke-evidence.json` to bind the installed exe absolute path and SHA256 to the evidence files, by requiring the formal `RequireSigning + RequireInstalledSmoke` path to match a non-`SkipBuild` release signing manifest with NSIS installer and updater `.sig` hashes, and by requiring the installed exe SHA256 to match the release signing manifest's `appExeSha256`.
  - `test-assistant` supports the current conclusion as `conditional_caveman_only`, not `ready_for_formal_release`. It confirmed the local PromptPanel tests and release hardening checks, and asked for API Ultra coverage plus stronger evidence-dir validation. The API smoke now covers Full -> Lite -> Ultra -> off.
  - Main-agent focused reruns after hardening integration confirmed `scripts/verify-caveman-release-hardening.ps1` exits 0 with `release_hardening=passed`, `verify-caveman-installed-smoke.ps1 -ValidatePathOnly` rejects a `%LOCALAPPDATA%\ProgramsFake\...` spoof path, installed smoke cannot be confirmed without a structured evidence manifest, `scripts/new-caveman-installed-smoke-evidence.ps1` can generate a validated evidence manifest, `scripts/new-caveman-installed-smoke-evidence.ps1 -ReleaseSigningManifestPath <manifest>` rejects a fake `.sig` before writing formal release-bound evidence, `verify-caveman-installed-smoke.ps1 -ReleaseSigningManifestPath <manifest>` also rejects a fake `.sig` during evidence validation, `SkipBuild` signing manifests are rejected for formal installed-smoke evidence, installed exe SHA mismatch is rejected before signing validation can mask that mismatch, aggregate signing manifest validation rejects a fake `.sig` that does not verify against the configured updater public key, and targeted `git diff --check` exits 0 for the release gate/signing/installed-smoke/readiness files.
- Final-release blocker preflight on this local environment is explicit:
  - `scripts/verify-caveman-release-gate.ps1 -RequireSigning` exits non-zero before the long verifier chain unless a non-`SkipBuild` release signing manifest already exists and its MSI, NSIS, app executable, and updater signature hashes still match the files on disk.
  - `scripts/verify-caveman-release-gate.ps1 -RequireInstalledSmoke` exits non-zero before the long verifier chain because `-InstalledAppPath`, `-InstalledSmokeEvidenceDir`, and the installed-app confirmation switches are required.
  - These negative preflights are expected locally and prove the aggregate gate will not upgrade the local conditional result to `ready_for_formal_release` without release-host signing evidence and installed-app smoke evidence artifacts.

### Aggregate Release Gate

The reusable aggregate gate is `scripts/verify-caveman-release-gate.ps1`.

Latest local run passed in conditional mode:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1
```

Observed terminal evidence:

```text
release_signing=skipped_local_condition
installed_smoke=skipped_local_condition
formal_release_blocked_reason=release_signing_not_required,installed_smoke_not_required
Caveman release gate passed.
release_gate=conditional_caveman_only
```

The release-host handoff manifest can be regenerated with:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-formal-release-checklist.ps1
```

It writes `.run\caveman-formal-release-checklist\caveman-formal-release-checklist.json` and records the non-SkipBuild signing, installed desktop smoke, evidence-manifest generation, and final aggregate-gate commands required before the Caveman release can move from `conditional_caveman_only` to `ready_for_formal_release`.

Before the final aggregate gate, the release host can also run a quick prerequisite audit:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-formal-release-readiness.ps1 -ReleaseSigningManifestPath ".run\caveman-release-signing\caveman-release-signing-manifest.json" -InstalledAppPath "INSTALLED_APP_EXE_PATH" -InstalledSmokeEvidenceDir "INSTALLED_SMOKE_EVIDENCE_DIR"
```

This writes `.run\caveman-formal-release-readiness\caveman-formal-release-readiness.json`. A passing audit must print `formal_release_readiness=formal_release_prerequisites_present`. It is only a prerequisite audit; the formal release decision still requires the final aggregate gate with both `-RequireSigning` and `-RequireInstalledSmoke`.

The readiness audit also records `localCavemanEvidence`. On the latest local run, `.run\caveman-formal-release-readiness\after-local-evidence-audit.json` reports `localCavemanEvidence.status=local_caveman_evidence_present` while the top-level status remains `formal_release_prerequisites_blocked`. This split is intentional: the local evidence proves the prompt-level Caveman behavior and deployed-state restoration are covered, but it does not satisfy release-host signing or installed-app smoke.

The current local approval packet can be generated with:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-release-approval-packet.ps1
```

It writes `.run\caveman-release-approval\caveman-release-approval-packet.json` and must report `caveman_release_approval_status=conditional_caveman_only_ready_for_release_host_approval`. This packet is the review bundle for Caveman prompt-level approval preparation; it deliberately keeps `formalReleaseReadiness=formal_release_prerequisites_blocked` until release-host signing and installed-app smoke evidence are attached. The packet also records `evidenceArtifacts` with SHA256 hashes for the readiness audit, formal checklist, release-host runbook, UI smoke evidence manifest, deployed smoke, deployed restore probe, and local gate summary, so reviewers can tell whether the evidence files changed after the packet was generated. The packet's local capability list includes `ui_smoke_screenshots_are_hashed`, which is backed by `.run\caveman-ui-smoke\caveman-ui-smoke-evidence.json`. The packet can be revalidated with `scripts\verify-caveman-release-approval-packet.ps1`; latest hardening also proves a tampered evidence hash is rejected through `approval_packet_verifier_rejects_tampered_evidence_hash=blocked`.

Installed-smoke evidence is bound to the installed executable and to the evidence files themselves. `scripts\new-caveman-installed-smoke-evidence.ps1` records each listed evidence file's SHA256, and `scripts\verify-caveman-installed-smoke.ps1` rejects evidence files that are missing, empty, path-escaped, or changed after the manifest was generated.

This conditional local result proves the Caveman prompt/style-profile gate can run end to end on the current workspace, including shared token-cost verifier, API smoke, real Web UI smoke, deployed Docker smoke with state restoration, deployed existing-prompt restore probe, desktop preflight, web production build, and diff whitespace check. It does not replace the release-host signing gate or installed-app smoke.

For a release-host pass that can support final formal release, run:

1. Produce the signed artifacts and signing manifest:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-signing.ps1
```

2. Install the generated NSIS package, complete the installed-app smoke, place screenshots or logs under the evidence directory, then generate and validate the installed-smoke evidence manifest:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-evidence.ps1 -InstalledAppPath "<installed app exe>" -EvidenceDir "<installed smoke evidence dir>" -EvidenceFiles "prompt-panel-full.png" "prompt-panel-lite.png" "prompt-panel-ultra.png" "prompt-panel-off.png" -ReleaseSigningManifestPath ".\.run\caveman-release-signing\caveman-release-signing-manifest.json"
```

3. Run the aggregate final release gate:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-gate.ps1 -RequireSigning -ReleaseSigningManifestPath ".\.run\caveman-release-signing\caveman-release-signing-manifest.json" -RequireInstalledSmoke -InstalledAppPath "<installed app exe>" -InstalledSmokeEvidenceDir "<installed smoke evidence dir>" -ConfirmInstalledAppLaunched -ConfirmInstalledPromptEntryVisible -ConfirmInstalledModesVisible -ConfirmInstalledModeSequence -ConfirmInstalledTurnOffRetainsPresetDisabled -ConfirmInstalledLivePromptNonCaveman -GateSummaryPath ".\.run\caveman-release-gate\caveman-release-gate-summary.json"
```

When `-RequireInstalledSmoke` is set, the aggregate gate requires the caller to pass granular installed-app confirmation switches plus `-InstalledSmokeEvidenceDir`, and forwards them to `verify-caveman-installed-smoke.ps1`. This prevents a final `ready_for_formal_release` result from being produced by a single ambiguous "manual smoke passed" flag or by the aggregate gate self-confirming manual UI checks. The installed app executable must also be named like the installed CC Switch app, be outside the source repo, and live under a standard Windows installed-app directory such as `Program Files` or `%LOCALAPPDATA%\Programs`. The installed smoke evidence directory must contain `caveman-installed-smoke-evidence.json`; that manifest must bind the installed exe absolute path and SHA256 to at least one non-empty relative evidence file, such as screenshots or a release-host smoke note/log captured during the installed-app run. When the aggregate gate is run with both `-RequireSigning` and `-RequireInstalledSmoke`, the installed-smoke preflight also requires the evidence manifest to match `.run\caveman-release-signing\caveman-release-signing-manifest.json`, that release signing manifest must come from a non-`SkipBuild` signing run, and the installed exe SHA256 must equal the signing manifest's `appExeSha256` before the longer verifier/build chain starts.

The aggregate release gate validates the existing signing manifest and artifact hashes, installed-app path, installed-app evidence, and installed-app confirmation arguments before running the longer verifier/build chain. For `-RequireSigning`, it calls `scripts/verify-caveman-release-signing.ps1 -ValidateManifestOnly -ValidateManifestPath <manifest>`; that validation checks the manifest fields, rejects `SkipBuild`, checks MSI/NSIS/app/signature SHA256 values against files on disk, requires `signaturePath` to equal `<nsis setup>.sig`, and runs the Rust `verify_updater_signature` helper against the updater public key configured in `src-tauri\tauri.conf.json`. A fake manifest plus fake `.sig` is therefore not sufficient signing evidence. The gate deliberately does not rerun signing during the final installed-app gate, because the installed executable and evidence manifest must remain tied to the signing manifest produced before installation. It also wraps child PowerShell scripts, `vite.cmd`, and `git diff --check` with explicit exit-code checks, so a failed child step cannot be logged and then followed by `Caveman release gate passed`. Because several release-gate files may be new/untracked before staging, the aggregate gate also scans the named text files directly for missing paths, trailing whitespace, and conflict markers instead of relying only on `git diff --check`. The aggregate gate also runs `scripts/verify-caveman-release-hardening.ps1`, which keeps the signing and installed-app smoke negative controls reproducible instead of relying on one-off manual commands. The hardening script uses an isolated fake bundle for missing-signature checks so release-host signed artifacts do not make the negative test fail for the wrong reason. The gate writes `.run\caveman-release-gate\caveman-release-gate-summary.json` by default, or another path under `.run\caveman-release-gate\` passed through `-GateSummaryPath`; the summary records `requireSigning`, `requireInstalledSmoke`, `formalReleaseBlockedReasons`, and `releaseGate` so approval reviewers can inspect a stable file even when long terminal output is truncated.

That release-host run must finish with:

```text
release_gate=ready_for_formal_release
```

## Final Release Checklist

The automated runtime-flow test covers the Prompt panel behavior at the React hook and Tauri transport boundary.
The Web UI smoke covers the real browser and Web Server/API path.
The desktop packaging evidence covers Tauri version matching, renderer production build, Rust release compilation, and local MSI/NSIS installer generation. Final release should still run these checks in CI or the release build machine:

1. Open the Prompt panel for OpenClaw or another prompt-supported app.
2. Confirm Lite, Full, Ultra, and Turn off controls are visible and not confused with the reserved optimizer setting.
3. Select a mode when no Caveman preset exists; confirm the preset appears and becomes enabled.
4. Switch to another mode; confirm only the selected Caveman mode is enabled.
5. Turn Caveman off; confirm the preset remains present and disabled.
6. Confirm the app's live prompt file follows the selected mode and is cleared when no prompt remains enabled.
7. Run `scripts/verify-caveman-desktop-preflight.ps1` and archive the build log.
8. Run the full Tauri build in the release environment with `TAURI_SIGNING_PRIVATE_KEY` set, then archive the signed updater artifacts. The reusable gate is:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-release-signing.ps1
```

For final release approval, do not use `-SkipBuild`: the signing gate checks that MSI, NSIS, the desktop app executable, and the updater signature artifact matching the selected NSIS setup path (`<setup.exe>.sig`) are newer than the current signed build start time. The signing manifest records `appExePath` and `appExeSha256`; installed-app smoke uses that hash to prove the smoked executable matches the signed build output. The signing gate also validates the updater signature against the configured updater public key before treating a non-`SkipBuild` manifest as signed release evidence. `-SkipBuild` is only for local gate-shape checks and stale-artifact diagnostics, and its output is intentionally labeled `release_signing=local_shape_only`.

9. Install the produced desktop package and complete the installed-app smoke. Create at least one non-empty evidence file, write the structured confirmation note, then generate the structured evidence manifest:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-confirmation.ps1 -EvidenceDir "<installed smoke evidence dir>" -InstalledAppPath "<installed app exe>" -ReleaseSigningManifestPath ".\.run\caveman-release-signing\caveman-release-signing-manifest.json" -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman
```

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new-caveman-installed-smoke-evidence.ps1 -InstalledAppPath "<installed app exe>" -EvidenceDir "<installed smoke evidence dir>" -EvidenceFiles "prompt-panel-full.png" "prompt-panel-lite.png" "prompt-panel-ultra.png" "prompt-panel-off.png" -ReleaseSigningManifestPath ".\.run\caveman-release-signing\caveman-release-signing-manifest.json"
```

When `-ReleaseSigningManifestPath` is supplied, the helper first runs `verify-caveman-release-signing.ps1 -ValidateManifestOnly -ValidateManifestPath <manifest>`, so it will not create release-bound installed-smoke evidence from a fake manifest or fake updater `.sig`.

Then run the reusable confirmation gate:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-caveman-installed-smoke.ps1 -InstalledAppPath "<installed app exe>" -EvidenceDir "<installed smoke evidence dir>" -ReleaseSigningManifestPath ".\.run\caveman-release-signing\caveman-release-signing-manifest.json" -ConfirmAppLaunched -ConfirmPromptEntryVisible -ConfirmModesVisible -ConfirmModeSequence -ConfirmTurnOffRetainsPresetDisabled -ConfirmLivePromptNonCaveman
```

This confirmation gate also validates the referenced signing manifest with `verify-caveman-release-signing.ps1 -ValidateManifestOnly`, after checking that the evidence manifest binds the installed executable, source installer, build executable, and updater signature hashes to the same release manifest.

Residual risk: the installed-app confirmation note is structured manual smoke evidence, not cryptographic proof that the operator performed the UI clicks. The gate prevents missing confirmations, empty evidence, post-generation evidence tampering, untrusted signing manifests, `SkipBuild` manifests, and installed-exe/signing-manifest mismatches. It still relies on the release operator to attach truthful installed-app screenshots, logs, or notes from the actual smoke run.

The evidence directory must include a manifest shaped like:

```json
{
  "installedAppPath": "C:\\Program Files\\CC Switch\\cc-switch.exe",
  "installedAppSha256": "<SHA256 of installed app exe>",
  "releaseSigningManifestPath": "<repo-root>\\.run\\caveman-release-signing\\caveman-release-signing-manifest.json",
  "sourceInstallerPath": "<repo-root>\\src-tauri\\target\\release\\bundle\\nsis\\CC Switch_<version>_x64-setup.exe",
  "sourceInstallerSha256": "<SHA256 from signing manifest>",
  "releaseAppExePath": "<repo-root>\\src-tauri\\target\\release\\cc-switch.exe",
  "releaseAppExeSha256": "<SHA256 from signing manifest appExeSha256; must match installedAppSha256>",
  "sourceSignaturePath": "<repo-root>\\src-tauri\\target\\release\\bundle\\nsis\\CC Switch_<version>_x64-setup.exe.sig",
  "sourceSignatureSha256": "<SHA256 from signing manifest>",
  "evidenceFiles": ["prompt-panel-full.png", "prompt-panel-lite.png", "prompt-panel-ultra.png", "prompt-panel-off.png", "caveman-installed-smoke-confirmation.json"],
  "evidenceFileSha256": {
    "prompt-panel-full.png": "<SHA256 of full-mode screenshot>",
    "prompt-panel-lite.png": "<SHA256 of lite-mode screenshot>",
    "prompt-panel-ultra.png": "<SHA256 of ultra-mode screenshot>",
    "prompt-panel-off.png": "<SHA256 of off-state screenshot>",
    "caveman-installed-smoke-confirmation.json": "<SHA256 of confirmation note>"
  }
}
```

Current release conclusion after incremental fixes, final independent cross-checks, Web Server/API smoke, real Web UI smoke, Tauri package-version alignment, desktop packaging preflight, local installer generation, and the local aggregate release gate: Caveman prompt-level mode control is conditionally ready locally, but formal release approval is still blocked until the release host supplies a non-SkipBuild `TAURI_SIGNING_PRIVATE_KEY` signing run and an installed-app smoke result with a structured evidence manifest. The approval scope is Caveman prompt/style-profile control only and does not approve same-batch token/proxy optimizer changes. The Caveman code path is backed by automated evidence for mode selection, off semantics, prompt-file behavior, server/API execution, real Web UI clicks, renderer production build, Rust release compile preflight, local MSI/NSIS installer generation, aggregate gate execution, aggregate signing-manifest cryptographic validation, and no proxy/provider Caveman response mutation. Same-batch token/proxy optimizer changes must keep their own release gate, and the current gate remains `conditional_caveman_only` until the release host evidence is attached.
