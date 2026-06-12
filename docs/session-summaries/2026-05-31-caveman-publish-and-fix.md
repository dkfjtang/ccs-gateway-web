# 2026-05-31 - Caveman Publish And Fix Notes

## Key Information

- Caveman remains prompt/profile-only. It is not wired into proxy response rewriting.
- If Caveman UI controls need to write OpenClaw prompt files, the OpenClaw config mount must allow writes for that deployment. A read-only mount can make the UI appear to toggle while the underlying prompt state remains unchanged.
- Production image tags, rollback container names, hostnames, and one-off runtime evidence are intentionally represented with placeholders or omitted in this public repository.

## Important Information

- Frontend label was shortened from `OpenClaw Caveman 模式` to `Caveman 模式`.
- Verification should cover required environment variables, CCS persistence, OpenClaw config mount mode, Web health, proxy status, NGINX health, auth behavior, proxy smoke, and a bounded log scan.

## Project Information

- The deployed Caveman UI uses `PromptPanel` and `RectifierConfigPanel` with Lite / Full / Ultra / Turn off controls.
- Production auth on `/api/invoke` blocks unauthenticated prompt checks, so direct API verification without browser login may be insufficient.

## Follow-ups

- If the Caveman button still looks wrong in production UI, inspect the authenticated button click response and the `prompts` table state in a logged-in browser session.
- Keep host-specific deploy helpers and raw evidence under `.run/`, not in tracked docs.

## Dropped Noise

- Long build logs, host-specific paths, runtime dumps, repeated poll updates, and failed shell quoting experiments were intentionally omitted.
