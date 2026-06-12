# 2026-05-29 - Token Saver / Caveman Release Notes

## Key Information

- Workspace: `<repo-root>`.
- Token-saving features should remain overlay-like so future upstream upgrades do not require broad reimplementation.
- Local validation endpoints, container names, image tags, tarball paths, and production hosts are represented with placeholders in this public repository.
- SSH passwords must be supplied through environment variables only. Do not store, print, or pass secret values in command arguments.

## Implementation / Behavior Decisions

- Token Saver remains an explicit optimizer-controlled feature.
- Caveman is intentionally not wired into proxy runtime. It remains prompt/profile-only or reserved; runtime response rewriting is disabled.
- Token Saver is implemented as a small overlay with a single normal hot-path hook:
  - `src-tauri/src/proxy/forwarder.rs`: `token_saver::optimize(&mut request_body, &optimizer_config)`
  - Main logic stays in `src-tauri/src/proxy/token_saver.rs` and `src-tauri/src/proxy/token_filter_engine.rs`.
- Safety rules verified in tests: do not compress user input, assistant replies, error tool outputs, structured object results, JSON-looking tool outputs, git diff, or unknown long text. Only safe long tool/function output classes may be compacted.

## Verification Expectations

- Automated local gates should cover Token Saver tests, Token Filter Engine tests, Caveman prompt tests, static checks that Caveman is not wired into proxy runtime, and static checks that Token Saver has exactly one forwarder hook.
- Web typecheck and secret preflight should run before public push.
- Runtime validation can check Web health, proxy status, NGINX health, Web Auth enabled, unauthenticated protected RPC returning `401`, and absence of obvious error patterns in a bounded log window.

## Production Runtime Contract

When replacing a production container, preserve the previous runtime contract unless a reviewed change explicitly requires divergence:

- command
- loopback-only Web UI/API and model proxy port bindings
- persistent CCS data mount
- OpenClaw config mount mode chosen for the target feature
- restart policy
- required environment variables, including whether the local proxy should auto-start
- Docker network

## Incident / Lesson

- A replacement that copies ports, mounts, network, restart policy, and command can still break the model proxy if it drops required environment variables.
- Future deploy automation must treat environment variables as part of the runtime contract and should fail before replacement if expected environment is missing.

## Independent Review / Test Notes

- Review should ask for evidence of persistence, rollback readiness, feature smoke, and bounded production health checks.
- Infrastructure validation is not a substitute for full business E2E validation through the real client workflow.

## Follow-ups

- Consider a maintained deploy script that reads original container env/ports/mounts/network/restart/cmd from `docker inspect`, builds from a filtered tarball, creates a named rollback container, performs health/auth/NGINX/persistence checks, and never logs credential values.
- Consider adding non-sensitive compression-hit metadata if future cost-saving proof needs per-request Token Saver hit evidence. Do not log request bodies or secrets.

## Dropped Noise

- Raw Docker build dependency download logs, long asset manifests, repeated progress updates, private host details, PowerShell quoting mistakes without durable lesson, and all credential values were intentionally not preserved.
