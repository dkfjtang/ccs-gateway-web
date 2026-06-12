# 2026-05-28 - OpenClaw Fast Priority Patch Session

## Key Information

- Project workspace: `<repo-root>`.
- Local WSL distro used for OpenClaw testing: `<wsl-distro>`, using root-owned OpenClaw installation.
- Local CCS test gateway must use `<loopback-host>:<port>`; never use `15722`, because it is reserved by the local CCS desktop instance.
- Local CCS API used during verification: `http://<loopback-host>:<port>/api/invoke`.
- Local OpenClaw gateway systemd user service: `openclaw-gateway.service`.
- OpenClaw gateway command path observed during this session: `<hermes-data-dir>/node/bin/node <hermes-data-dir>/node/lib/node_modules/openclaw/dist/index.js gateway --port 18789`.
- Production hosts mentioned for later deployment: `<host-a>` and `<host-b>`, both Ubuntu. They were not touched in this session.

## Patch Artifact

- Repo skill created: `skills/openclaw-fast-priority-patch`.
- Main instructions: `skills/openclaw-fast-priority-patch/SKILL.md`.
- Patch script: `skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh`.
- Agent metadata: `skills/openclaw-fast-priority-patch/agents/openai.yaml`.
- Purpose: after OpenClaw install or upgrade, patch bundled dist files so non-official `openai-responses` endpoints can still transmit `service_tier=priority` when fast mode is enabled.

## Upgrade And Verification Results

- OpenClaw was upgraded from `2026.5.12` to `2026.5.27`.
- Final version check returned: `OpenClaw 2026.5.27 (27ae826)`.
- The skill patch script successfully patched the upgraded OpenClaw dist files:
  - `<hermes-data-dir>/node/lib/node_modules/openclaw/dist/proxy-stream-wrappers-Dte4KBWq.js`
  - `<hermes-data-dir>/node/lib/node_modules/openclaw/dist/extra-params-BxDvfOci.js`
- A post-patch dry run returned `dry_run_status=already_patched`.
- Local wrapper verification returned `local_wrapper_test=service_tier:priority`.
- Real request verification used a temporary safe capture proxy on `<loopback-host>:<port>`, forwarding to local CCS `<loopback-host>:<port>`.
- Capture proxy logged only safe fields and confirmed:
  - method: `POST`
  - URL: `/v1/responses`
  - model: `gpt-5.5`
  - `service_tier`: `priority`
  - `has_service_tier`: `true`
- CCS latest usage log matched provider `<provider-name>`, model `gpt-5.5`, status `200`.
- The user provided a <provider-name> usage screenshot showing `Fast` service tier at `2026/05/28 19:55:00`.
- CCS epoch timestamp `1779969299` converted to `2026-05-28 19:54:59 CST`, matching the screenshot within about one second.

## Commands Worth Reusing

Upgrade OpenClaw:

```bash
<hermes-data-dir>/node/bin/node <hermes-data-dir>/node/lib/node_modules/openclaw/openclaw.mjs update --yes --json --timeout 1800
```

Apply or reapply the skill patch:

```bash
bash <repo-root-wsl>/skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --restart
```

Check patch status without modifying files:

```bash
bash <repo-root-wsl>/skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --dry-run
```

Check OpenClaw version:

```bash
<hermes-data-dir>/node/bin/node <hermes-data-dir>/node/lib/node_modules/openclaw/openclaw.mjs --version
```

Check gateway service:

```bash
systemctl --user is-active openclaw-gateway.service
```

## Important Implementation Lessons

- Newer OpenClaw dist file names are hashed; the script must auto-detect `proxy-stream-wrappers-*.js` and `extra-params-*.js`.
- The `extra-params` import line can include additional imported symbols, so the script must match and preserve dynamic import contents instead of expecting an exact import list.
- Dry-run must not run wrapper verification before the patch is applied. It should report `dry_run_status=patch_needed` or `dry_run_status=already_patched`.
- Partial patch states are possible after a failed run. The script must detect and replace the old provider-limited guard directly, not infer success from unrelated helper symbols.
- Keep backups with `.bak-openclaw-fast-priority-*` before mutating installed OpenClaw dist files.
- Run `node --check` after patching each generated JS file.

## Security And Safety Notes

- Do not print raw `<openclaw-data-dir>/openclaw.json` or `<openclaw-data-dir>/agents/main/agent/models.json`; they may contain secret-bearing fields.
- During the OpenClaw update, doctor warned about plaintext secret-bearing fields and a memory search provider without API key. This was not remediated in this session.
- Any temporary capture proxy must log only safe fields such as method, URL, model, `service_tier`, `has_service_tier`, and body size. It must not log prompts, headers, API keys, tokens, or raw request bodies.
- After capture verification, restore `zdy.baseUrl` from `<loopback-host>:<port>/v1` back to `<loopback-host>:<port>/v1`, restart `openclaw-gateway.service`, and stop the temporary capture proxy.
- Before pushing this public repo, re-run sensitive keyword checks on touched files.

## Follow-ups

- Prepare production deployment notes for `<host-a>` and `<host-b>` before touching either host.
- For production, preserve each host's existing Docker and OpenClaw runtime parameters; only apply the patch and verification procedure after confirming paths and service names.
- Consider adding a concise production runbook section for OpenClaw upgrade plus fast priority patch verification.

## Dropped Noise

- Repeated progress messages, shell quoting mistakes, and raw long logs were not preserved.
- No secrets, raw provider config, prompts, headers, or API keys were recorded.
