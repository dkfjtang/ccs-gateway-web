# 2026-05-28 - Sanitized Production Deploy Notes

## Key Information

- Workspace: `<repo-root>`.
- Production work must be detect-first: inspect only until an explicit approval covers updates, restarts, file writes, Docker changes, or NGINX changes.
- SSH passwords must be supplied through environment variables only. Do not store, print, or pass secret values in command arguments.
- Production hosts are represented with placeholders such as `<host-a>` and `<host-b>` in this public repository.
- NGINX should proxy only to the host-local Web UI/API port. Do not expose the model proxy port externally.
- Preserve the previous container runtime contract when replacing a container: command, loopback port bindings, persistent mounts, restart policy, network, and required environment variables.

## Deployment Result

- New images and rollback containers were created with placeholder-style tags and names.
- Final checks confirmed the replacement containers were running and the Web UI/API health endpoint responded.
- This note intentionally omits private hostnames, real ports outside the documented product examples, container IDs, image digests, and raw runtime inspection output.

## OpenClaw Fast Priority Patch

- Production hosts may use different OpenClaw install layouts. The patch and verification flow must discover the install root, Node executable, service name, hashed dist filenames, and export aliases instead of assuming one local shape.
- Final verification should prove that the proxy helper and fast-mode marker are present and that OpenClaw fast mode maps to `service_tier:priority`.

## Reusable Lessons

- OpenClaw releases can use hashed dist files and minified export aliases. Patch scripts must parse the proxy dist export block dynamically instead of assuming fixed aliases such as `_` or `u`.
- OpenClaw fast patch needs both pieces:
  - proxy wrapper guard must allow `openai-responses` and `openai-codex-responses` even for non-official providers.
  - extra params wrapper must call the discovered `resolveOpenAIFastMode` alias and wrap the stream function with the discovered `createOpenAIFastModeWrapper` alias.
- Do not rely on default install root detection only. Production hosts may use system global npm paths, user-managed Node paths, or another layout.
- When packaging the repo for remote Docker build, add files only after filtering. Do not add directories recursively after filtering, because that can accidentally include build output such as `target`, `node_modules`, `.git`, `dist`, `.run`, or private environment files.

## Follow-ups

- Business-path testing remains separate from infrastructure health checks.
- Future deploy automation should use environment-variable credentials only, detect-first mode, sanitized runtime snapshots, file-only tar packaging, rollback container creation, and OpenClaw alias-aware patch verification.

## Dropped Noise

- Raw Docker build logs, dependency download lists, repeated progress updates, private host details, PowerShell quoting mistakes, and sensitive credential values were intentionally not preserved.
