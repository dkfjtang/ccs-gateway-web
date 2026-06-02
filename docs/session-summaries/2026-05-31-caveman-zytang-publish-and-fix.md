# 2026-05-31 - Caveman zytang publish and fix

## Key Information
- Caveman remains prompt/profile-only. It is not wired into proxy response rewriting.
- The production Caveman UI issue on `zytang` was caused by `/root/.openclaw` being mounted read-only, which blocked prompt-file writes when enabling Lite/Full.
- The production container was republished with the same persistent `/root/.cc-switch` data and the same host loopback ports, but `/root/.openclaw` was changed to `rw`.
- zytang production current image after fix: `ccs-gateway-web:caveman-prod-20260531125500`.
- Rollback container after fix: `ccs-gateway-web-backup-before-caveman-prod-20260531125500`.

## Important Information
- Frontend label was shortened from `OpenClaw Caveman 模式` to `Caveman 模式`.
- Verified on zytang:
  - `CC_SWITCH_START_PROXY=true` preserved
  - `/root/.cc-switch` preserved
  - `/root/.openclaw:/root/.openclaw:rw` now mounted
  - Web health, proxy status, NGINX health, auth, and proxy smoke all passed
  - Recent log scan showed no `panic`, `error`, `failed`, `permission denied`, `connection refused`, or `connection reset`

## Project Information
- The deployed Caveman UI uses `PromptPanel` and `RectifierConfigPanel` with Lite / Full / Ultra / Turn off controls.
- Production auth on `/api/invoke` blocks unauthenticated prompt checks, so direct API verification without browser login is not possible.

## Follow-ups
- If the user reports the Caveman button still looks off in production UI, inspect the authenticated button click response and the `prompts` table state in the logged-in browser session.
- Keep the production deploy helper script in `.run/deploy_zytang_caveman.py` as the current replacement path for zytang-style releases.

## Dropped Noise
- Long build logs, repeated poll updates, and failed shell quoting experiments were intentionally omitted.
