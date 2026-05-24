# CCS Gateway Web Production Runbook

This runbook records the production operating checks for the WSL/Ubuntu + Docker + OpenClaw + NGINX deployment.

## Target boundary

```text
External clients
  -> NGINX :30034
  -> 127.0.0.1:17666 inside WSL/Ubuntu
  -> CCS Web UI/API in Docker

OpenClaw inside WSL/Ubuntu
  -> 127.0.0.1:15721/v1
  -> CCS OpenAI-compatible proxy in Docker
```

Required state:

- `17666` is CCS Web UI/API and is published on the host loopback only.
- `15721` is the model proxy and is published on the host loopback only.
- `30034` is the external NGINX entry and proxies only to `127.0.0.1:17666`.
- External clients must not be able to reach `17666` or `15721` directly.
- Web auth must be enabled before exposing `30034`.
- The CCS proxy must start automatically after container restart.

## Important files

| Path | Purpose |
| --- | --- |
| `/root/.cc-switch` | CCS persistent data: database, providers, settings, proxy config, backups, Web auth config |
| `/root/.cc-switch/web-auth.json` | Web auth configuration; must exist in production |
| `/root/.cc-switch/web-auth-password.txt` | Local bootstrap password note, root-only; never commit or paste to chat |
| `/root/.openclaw/openclaw.json` | OpenClaw config mounted read-only into the container |
| `docker-compose.ccs-web.yml` | Docker runtime definition for this deployment |
| `/etc/nginx/sites-available/ccs-gateway-web-30034` | NGINX entry that should proxy `30034 -> 127.0.0.1:17666` |

## Daily health check

Run from the WSL/Ubuntu host:

```bash
cd /home/zytang/openclaw/workspace-ccs-gateway-web/ccs-gateway-web

docker ps --filter name=ccs-gateway-web
ss -ltnp | grep -E ':(17666|15721|30034)\b' || true
curl -fsS http://127.0.0.1:17666/health
curl -fsS http://127.0.0.1:15721/status
curl -fsS http://127.0.0.1:30034/health
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30034/.env
```

Expected:

```text
ccs-gateway-web is running
127.0.0.1:17666 is listening
127.0.0.1:15721 is listening
30034 is listening via NGINX
/health on 17666 returns success
/status on 15721 returns success
/health on 30034 returns success
/.env on 30034 returns 404
```

## External exposure check

Run from the WSL/Ubuntu host using its LAN-facing WSL IP:

```bash
ip=$(hostname -I | awk '{print $1}')
curl --connect-timeout 2 "http://$ip:17666/health" || echo '17666 blocked as expected'
curl --connect-timeout 2 "http://$ip:15721/status" || echo '15721 blocked as expected'
curl -fsS "http://$ip:30034/health"
```

Expected:

```text
17666 blocked as expected
15721 blocked as expected
30034 returns health successfully
```

If `17666` or `15721` is reachable through `$ip`, stop and fix the Docker port publishing before continuing.

## Web auth check

```bash
ls -l /root/.cc-switch/web-auth.json
curl -sS -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:17666/api/invoke \
  -d '{"command":"auth.status","payload":{}}'

curl -sS -i -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:17666/api/invoke \
  -d '{"command":"get_settings","payload":{}}'
```

Expected:

- `web-auth.json` exists.
- `auth.status` reports `enabled: true`.
- Unauthenticated protected RPC calls return `401`.

Password handling:

- Do not commit `web-auth.json` or `web-auth-password.txt`.
- Do not paste the bootstrap password into chat.
- If the password needs to be rotated, update `/root/.cc-switch/web-auth.json`, keep the local root-only note current, and restart the container.

## Proxy auto-start check

The compose file must include:

```yaml
environment:
  CC_SWITCH_START_PROXY: "true"
ports:
  - "127.0.0.1:17666:17666"
  - "127.0.0.1:15721:15721"
```

After a restart, verify that the proxy comes back without manually pressing start in the Web UI:

```bash
docker compose -f docker-compose.ccs-web.yml restart ccs-gateway-web
sleep 5
curl -fsS http://127.0.0.1:15721/status
```

Expected status includes `running: true` or an equivalent healthy proxy state.

## Business smoke test

Use the CCS proxy directly, not the historical temporary upstream `127.0.0.1:20128`:

```bash
curl -sS --max-time 120 \
  -D /tmp/ccs_smoke_headers.txt \
  -o /tmp/ccs_smoke_body.json \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:15721/v1/responses \
  -d '{"model":"gpt-5.5","input":[{"role":"user","content":"Return exactly: CCS_PING_OK"}],"max_output_tokens":32}'

cat /tmp/ccs_smoke_body.json
```

Expected:

- HTTP 200.
- Response status is completed.
- Output contains `CCS_PING_OK`.
- CCS request logs show the current production provider, currently `发现AI` / `发现ai-1779516790556`.

## OpenClaw last-hop check

After any deployment, provider, auth, or proxy change, also verify OpenClaw can use the configured model path.

Expected model path:

```text
OpenClaw -> ccs/gpt-5.5 -> http://127.0.0.1:15721/v1 -> CCS current provider
```

Do not mark the deployment healthy only because `curl` succeeds. A complete verification also needs one OpenClaw model call through `ccs/gpt-5.5` returning the expected sentinel text.

Known good sentinels from previous verification:

```text
CCS_VERIFY_OK
CCS_HARDENING_OK
CCS_AUTOSTART_OK
```

## Provider switching checklist

Before switching provider:

1. Back up `/root/.cc-switch`.
2. Confirm Web auth is enabled.
3. Switch provider from the Web UI/API.
4. Run `/v1/responses` smoke through `127.0.0.1:15721`.
5. Confirm request logs and `get_proxy_status` show the intended provider.
6. Run one OpenClaw last-hop check through `ccs/gpt-5.5`.

Do not treat `127.0.0.1:20128` as production verification. It belongs to another local service and is not the CCS production route.

## Backup before risky changes

Run before destructive rebuilds, migrations, provider experiments, or auth rewrites:

```bash
stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/home/win-files/openclaw-backups/ccs-gateway-web-data/$stamp"
mkdir -p "$backup_dir/openclaw-config"
tar -czf "$backup_dir/root-cc-switch.tar.gz" -C /root .cc-switch
cp -a /root/.openclaw/openclaw.json "$backup_dir/openclaw-config/openclaw.json"
```

Confirm backup files exist before proceeding:

```bash
ls -lh "$backup_dir"
ls -lh "$backup_dir/openclaw-config"
```

## Rollback procedure

Use this when a new image, compose change, auth change, or provider change breaks the deployment.

### 1. Stop the container

```bash
cd /home/zytang/openclaw/workspace-ccs-gateway-web/ccs-gateway-web
docker compose -f docker-compose.ccs-web.yml down
```

### 2. Restore CCS data if needed

```bash
backup_dir="/home/win-files/openclaw-backups/ccs-gateway-web-data/<timestamp>"
tar -xzf "$backup_dir/root-cc-switch.tar.gz" -C /root
```

Only restore `/root/.openclaw/openclaw.json` if the OpenClaw config was also changed and you have an explicit reason to roll it back.

### 3. Rebuild/restart the last known good image

```bash
git log --oneline -5
git checkout <known-good-commit>
docker compose -f docker-compose.ccs-web.yml up -d --build
```

Known good commits in this deployment line:

```text
34db7ad Harden CCS Docker network and require web auth
2f6ffe9 Auto-start CCS local proxy in Docker
```

### 4. Re-run minimum gates

```bash
curl -fsS http://127.0.0.1:17666/health
curl -fsS http://127.0.0.1:15721/status
curl -fsS http://127.0.0.1:30034/health
```

Then run the business smoke and OpenClaw last-hop checks.

## Common failures

### `15721/status` connection reset after switching to Docker bridge

Likely cause: the proxy inside the container is bound to container-local `127.0.0.1` instead of `0.0.0.0`.

Fix: keep host publishing restricted to `127.0.0.1:15721:15721`, but ensure the proxy inside the container listens on an address Docker bridge can reach.

### Proxy is down after container restart

Likely cause: `CC_SWITCH_START_PROXY` is missing or false.

Fix: set `CC_SWITCH_START_PROXY=true`, rebuild/restart, and re-run the proxy auto-start check.

### Web API returns sensitive provider fields unauthenticated

Likely cause: Web auth is disabled or bypassed.

Fix: enable `/root/.cc-switch/web-auth.json`, restart, and verify unauthenticated protected RPC returns `401`.

### GitHub push fails with TLS/GnuTLS errors

This has been seen as a transient GitHub credential/network path issue.

Fix:

```bash
gh auth setup-git
git push origin main
```

## Completion criteria

A CCS deployment change is not complete until all are true:

- Docker container is running with `restart: unless-stopped`.
- `17666` and `15721` are host-loopback only.
- External WSL IP cannot access `17666` or `15721`.
- NGINX `30034` is reachable and proxies only to Web UI/API.
- Web auth is enabled and unauthenticated protected RPC returns `401`.
- Proxy auto-start works after container restart.
- `/v1/responses` smoke through `127.0.0.1:15721` succeeds.
- One OpenClaw last-hop call through `ccs/gpt-5.5` succeeds.
- Any source/docs changes are committed, and remote push is verified when a push is explicitly requested.
