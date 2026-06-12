---
name: openclaw-fast-priority-patch
description: Apply, verify, and operate the OpenClaw fast-mode priority service tier patch on Ubuntu hosts. Use when deploying OpenClaw behind non-official OpenAI-compatible openai-responses endpoints, especially when "fast on" must add service_tier=priority for providers such as CCS Gateway / ccs-gateway-web.
---

# OpenClaw Fast Priority Patch

Use this skill when OpenClaw must route non-official `openai-responses` providers through fast mode and send `service_tier=priority`.

## Scope

- Target hosts are Ubuntu systems running OpenClaw Gateway, represented in public docs as placeholders such as `<host-a>` and `<host-b>`.
- This is an OpenClaw installed-package patch, not a `ccs-gateway-web` source patch.
- Do not print or copy API keys, bearer tokens, provider headers, or raw `models.json` / `openclaw.json` contents.
- Never touch production until the target host and rollback point are explicit.

## Patch Script

Use the bundled script:

```bash
skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh
```

Typical production command on each host:

```bash
bash apply_openclaw_fast_priority_patch.sh --restart
```

Dry run:

```bash
bash apply_openclaw_fast_priority_patch.sh --dry-run
```

Read-only health check:

```bash
bash apply_openclaw_fast_priority_patch.sh --check
```

`--check` never writes files or restarts services. It prints `check_status=ok`, `check_status=needs_patch`, or `check_status=unsupported_shape`.

Exit codes:

- `0`: `check_status=ok`
- `1`: `check_status=needs_patch`
- `2`: `check_status=unsupported_shape`

Custom install root:

```bash
OPENCLAW_INSTALL_ROOT=/root/.hermes/node/lib/node_modules/openclaw \
bash apply_openclaw_fast_priority_patch.sh --restart
```

## Standard Workflow

1. Confirm host and service.
   Run `hostname`, `uname -a`, `systemctl --user status openclaw-gateway.service --no-pager`, and confirm the host is the intended production target.
2. Confirm OpenClaw files without exposing secrets.
   Check that the install root contains `dist/`, `openclaw.mjs`, and `package.json`; print only version and paths.
3. Run read-only check first.
   `bash apply_openclaw_fast_priority_patch.sh --check`
4. Apply the patch.
   `bash apply_openclaw_fast_priority_patch.sh --restart`
5. Verify.
   The script must report:
   - both dist files located
   - backups created or patch already present
   - `node --check` passed
   - local wrapper test returned `service_tier=priority`
   - gateway active after restart, if `--restart` was used
6. End-to-end verification.
   Send one small OpenClaw request from a session where fast mode is enabled. Confirm CCS receives the request and the upstream provider shows Fast / priority tier.

## Rollback

The script creates timestamped `.bak-openclaw-fast-priority-*` files next to patched dist files.

Rollback manually:

```bash
cp -p <backup-file> <original-dist-file>
systemctl --user restart openclaw-gateway.service
```

Only rollback the exact files patched by the script.

## Notes

- If OpenClaw is upgraded, rerun the dry run because dist filenames can change.
- If `fast on` appears enabled in session metadata but no priority tier reaches CCS, rerun this patch and verify the generic extra-params wrapper was patched.
- If the service is not managed by `systemctl --user`, apply with `--no-restart`, then restart using the host's actual OpenClaw process manager.
