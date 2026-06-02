# 2026-05-28 - zytang / tang Production Deploy

## Key Information

- Workspace: `F:\development\ccs-gateway-web`.
- User required a detect-first flow: first connect and inspect production only; no updates, restarts, file writes, Docker changes, or NGINX changes until explicit confirmation.
- SSH passwords were provided through environment variables only:
  - `CCS_ZYTANG_SSH_PASSWORD`
  - `CCS_TANG_SSH_PASSWORD`
  Do not store or print password values.
- Production hosts used in this session:
  - `zytang`: `root@81.71.156.28:20025`
  - `tang`: `root@1.14.163.241:22`
- NGINX was not changed.
  - `zytang` CCS public NGINX port observed: `30034 -> 127.0.0.1:17666`
  - `tang` CCS public NGINX port observed: `30002 -> 127.0.0.1:17666`
- CCS Docker runtime parameters preserved:
  - container: `ccs-gateway-web`
  - command: `/usr/local/bin/cc-switch-web`
  - ports: `127.0.0.1:17666:17666`, `127.0.0.1:15721:15721`
  - mounts: `/root/.openclaw:/root/.openclaw:ro`, `/root/.cc-switch:/root/.cc-switch`
  - restart policy: `unless-stopped`
  - network preserved per host (`zytang`: `ccs-gateway-web_default`; `tang`: `bridge`)

## Deployment Result

- `zytang`:
  - New CCS image: `ccs-gateway-web:codex-prod-20260528202657`
  - Backup container: `ccs-gateway-web-backup-before-codex-20260528202657`
  - Final check: container running, `curl http://127.0.0.1:17666/` OK.
- `tang`:
  - New CCS image: `ccs-gateway-web:codex-prod-20260528205707`
  - Backup container: `ccs-gateway-web-backup-before-codex-20260528205707`
  - Final check: container running, `curl http://127.0.0.1:17666/` OK.
- Deployment built from the current working tree on 2026-05-28, not from a clean committed tag. The worktree already had local changes before deployment.

## OpenClaw Fast Priority Patch

- Both production hosts were running OpenClaw `2026.5.4`.
- `zytang` OpenClaw:
  - install root: `/usr/lib/node_modules/openclaw`
  - node: `/usr/bin/node`
  - service: `openclaw-gateway.service`
  - final service state: `active/running`
- `tang` OpenClaw:
  - install root: `/root/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw`
  - node: `/root/.nvm/versions/node/v24.14.1/bin/node`
  - service: `openclaw-gateway.service`
  - final service state: `active/running`
- Final verification on both hosts:
  - `proxy_helper=present`
  - `extra_fast_marker=present`
  - wrapper test returned `openclaw_wrapper_test=service_tier:priority`

## Reusable Lessons

- Production OpenClaw `2026.5.4` uses hashed dist files and export aliases different from the earlier local test version:
  - `createOpenAIFastModeWrapper as c`
  - `resolveOpenAIFastMode as h`
  The patch script must parse the proxy dist export block dynamically instead of assuming fixed aliases such as `_` or `u`.
- OpenClaw fast patch needs both pieces:
  - proxy wrapper guard must allow `openai-responses` and `openai-codex-responses` even for non-official providers.
  - extra params wrapper must call `resolveOpenAIFastMode(ctx.effectiveExtraParams)` and wrap `ctx.agent.streamFn` with the real `createOpenAIFastModeWrapper` alias.
- Do not rely on default install root detection only. Production paths differed:
  - `zytang`: system global npm path under `/usr/lib/node_modules/openclaw`
  - `tang`: nvm path under `/root/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw`
- When packaging the repo for remote Docker build, do not `tar.add()` directories recursively after filtering. It can accidentally include `src-tauri/target` and produce a 1.5GB package. Add files only and exclude any path part named `target`, `node_modules`, `.git`, `dist`, etc. The corrected package size was about 16MB.
- Local Docker CLI was unavailable, so production image builds were performed on the target hosts from an uploaded source tarball.

## Follow-ups

- User will perform business-path testing manually.
- Consider committing or otherwise preserving the corrected `skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh` changes so future production OpenClaw patching works for both old and new alias layouts.
- For future deploy automation, prefer a maintained deployment script with:
  - environment-variable credentials only,
  - detect-first mode,
  - explicit Docker inspect snapshot,
  - file-only tar packaging,
  - rollback container creation,
  - OpenClaw alias-aware patch verification.

## Dropped Noise

- Raw Docker build logs, dependency download lists, repeated progress updates, PowerShell quoting mistakes, and sensitive credential values were intentionally not preserved.
