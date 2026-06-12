# CCS Gateway Web Release and Observability Plan

This document defines the local WSL build path and the production release/log probe workflow for the two Ubuntu production targets: `<host-a>` and `<host-b>`.

The repository is public. Do not commit secrets, host-private values, tokens, passwords, provider keys, WebDAV credentials, or real bootstrap credentials. Load all sensitive values from host environment variables or server-local files.

## Goals

- Build and test from WSL with Docker so the Windows host stays clean.
- Keep production runtime state outside the repository.
- Use the same release/probe commands for `<host-a>` and `<host-b>`.
- Add a mandatory pre-push secret check before publishing to GitHub.
- Keep `15721` private to the host loopback; expose only the Web UI/API through the controlled NGINX entry.

## Local WSL Build

Run from Windows PowerShell:

```powershell
rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && docker build -f Dockerfile.web -t ccs-gateway-web:local .'
```

If the Windows host has a local proxy, pass it explicitly into the Docker build. In this environment the proxy is:

```text
http://<proxy-host>:<proxy-port>
```

From WSL, `127.0.0.1` can resolve to the WSL network namespace rather than the Windows host. Prefer Docker Desktop's host alias first:

```powershell
rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && docker build --build-arg HTTP_PROXY=http://<proxy-host>:<proxy-port> --build-arg HTTPS_PROXY=http://<proxy-host>:<proxy-port> --build-arg http_proxy=http://<proxy-host>:<proxy-port> --build-arg https_proxy=http://<proxy-host>:<proxy-port> -f Dockerfile.web -t ccs-gateway-web:local .'
```

If `host.docker.internal` is unavailable in the WSL Docker engine, resolve the WSL default gateway and use that address:

```powershell
rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && proxy_host="$(ip route | awk "/default/ {print \$3; exit}")" && docker build --build-arg HTTP_PROXY="http://$proxy_host:7890" --build-arg HTTPS_PROXY="http://$proxy_host:7890" --build-arg http_proxy="http://$proxy_host:7890" --build-arg https_proxy="http://$proxy_host:7890" -f Dockerfile.web -t ccs-gateway-web:local .'
```

Run the local container without using production data:

```powershell
rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && mkdir -p .run/local-cc-switch .run/local-openclaw && docker run --rm --name ccs-gateway-web-local -p 127.0.0.1:17666:17666 -p 127.0.0.1:15721:15721 -e CC_SWITCH_HOST=0.0.0.0 -e CC_SWITCH_PORT=17666 -e CC_SWITCH_AUTO_PORT=false -e CC_SWITCH_START_PROXY=true -e RUST_LOG=cc_switch_server=info,tower_http=info -v "$PWD/.run/local-cc-switch:/root/.cc-switch" -v "$PWD/.run/local-openclaw:/root/.openclaw" ccs-gateway-web:local'
```

Smoke test from another shell:

```powershell
rtk wsl.exe -d <wsl-distro> -- bash -lc 'cd <repo-root-wsl> && CCS_TARGET_NAME=local CCS_CONTAINER_NAME=ccs-gateway-web-local ./scripts/ccs-prod-probe.sh'
```

## Sensitive Data Policy

Allowed in the public repository:

- Environment variable names.
- Placeholder values such as `<set-on-host>`.
- Paths to server-local files.
- Non-secret build mode values, for example `VITE_CC_SWITCH_MODE=ws`.

Not allowed in the public repository:

- API keys, provider tokens, OAuth tokens, passwords, cookies, private keys.
- Real contents of `/root/.cc-switch/web-auth.json`.
- Real contents of `/root/.cc-switch/web-auth-password.txt`.
- Real WebDAV password or token values.
- Host-private notes that reveal credentials or account recovery data.

Before any push:

```bash
./scripts/ccs-secret-preflight.sh
git diff --cached
git status --short --branch
```

If `gitleaks` is installed, the preflight script also runs it. If not installed, the script still runs filename, Docker context, large-file, and regex checks.

## Production Runtime Contract

Each production host keeps runtime data outside the repo:

| Path | Purpose |
| --- | --- |
| `/root/.cc-switch` | CCS database, settings, proxy config, backups, Web auth |
| `/root/.cc-switch/web-auth.json` | Server-local Web Auth config |
| `/root/.cc-switch/web-auth-password.txt` | Server-local password note, never committed |
| `/root/.openclaw` | OpenClaw config mounted read-write so OpenClaw/Caveman prompt config can be updated |

Required runtime environment:

```bash
export CC_SWITCH_HOST=0.0.0.0
export CC_SWITCH_PORT=17666
export CC_SWITCH_AUTO_PORT=false
export CC_SWITCH_START_PROXY=true
export RUST_LOG=cc_switch_server=info,tower_http=info
```

Do not put secret values in the compose file. Put them in server-local environment files or systemd/drop-in files that are not copied into the repository.

## Host Profiles

Use the same probe script with different host-level variables.

`<host-a>`:

```bash
export CCS_TARGET_NAME=<host-a>
export CCS_WEB_BASE_URL=http://127.0.0.1:17666
export CCS_PROXY_BASE_URL=http://127.0.0.1:15721
export CCS_NGINX_BASE_URL=http://127.0.0.1:30033
export CCS_CONTAINER_NAME=ccs-gateway-web
export CCS_REQUIRE_AUTH=true
export CCS_REQUIRE_NGINX=true
./scripts/ccs-prod-probe.sh
```

`<host-b>`:

```bash
export CCS_TARGET_NAME=<host-b>
export CCS_WEB_BASE_URL=http://127.0.0.1:17666
export CCS_PROXY_BASE_URL=http://127.0.0.1:15721
export CCS_NGINX_BASE_URL=http://127.0.0.1:30033
export CCS_CONTAINER_NAME=ccs-gateway-web
export CCS_REQUIRE_AUTH=true
export CCS_REQUIRE_NGINX=true
./scripts/ccs-prod-probe.sh
```

If either host uses a different external NGINX port, override only `CCS_NGINX_BASE_URL` on that host.

## Release Flow

1. Run the official upstream and local overlay gates from Windows PowerShell:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-official-upstream-alignment.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1
```

The gates must print:

```text
official_upstream_alignment=ready
overlay_status=overlay_ready
```

The upstream alignment gate also enforces that desktop updater endpoints use the fork release channel and that `.upstream/` remains a local, untracked comparison cache. Do not publish fork desktop builds that still point to the official `farion1231/cc-switch` updater feed.

2. Local build in WSL Docker.
3. Local smoke test with isolated `.run/local-*` volumes.
4. Run `./scripts/ccs-secret-preflight.sh`.
5. Commit only source, docs, scripts, and safe config templates.
6. Build or pull the image on `<host-a>`.
7. Back up `/root/.cc-switch` and `/root/.openclaw/openclaw.json`.
8. Run the OpenClaw patch health check on the target host before and after OpenClaw upgrades:

```bash
bash skills/openclaw-fast-priority-patch/scripts/apply_openclaw_fast_priority_patch.sh --check
```

For automation, parse `check_status=` as well as the exit code: `0` means `ok`, `1` means `needs_patch`, and `2` means `unsupported_shape`.

9. Deploy with loopback-only port publishing.
10. Run `CCS_TARGET_NAME=<host-a> ./scripts/ccs-prod-probe.sh`.
11. Repeat the same flow on `<host-b>`.
12. Verify the last hop from OpenClaw through `ccs/gpt-5.5` before declaring the release healthy.

## Log Analysis Baseline

Primary command:

```bash
./scripts/ccs-prod-probe.sh
```

Manual fallback:

```bash
docker ps --filter name=ccs-gateway-web
docker logs --tail 200 ccs-gateway-web
ss -ltnp | grep -E ':(17666|15721|30033)\b' || true
curl -fsS http://127.0.0.1:17666/health
curl -fsS http://127.0.0.1:15721/status
curl -fsS http://127.0.0.1:30033/health
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30033/.env
```

Token Saver aggregate report from copied or local logs:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\report-token-saver-usage.ps1 -LogPath .\logs\ccs-gateway-web.log
```

Release is not healthy until:

- Web health returns `200`.
- Proxy status returns `200`.
- NGINX health returns `200` where NGINX is enabled.
- `/.env` through NGINX returns `404`.
- Unauthenticated protected API calls return `401` when Web Auth is enabled.
- OpenClaw last-hop model call succeeds through the CCS proxy route.
- `verify-official-upstream-alignment.ps1` prints `official_upstream_alignment=ready`.
- `verify-local-overlays.ps1` prints `overlay_status=overlay_ready`.
