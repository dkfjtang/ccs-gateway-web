## 2026-06-11 - Usage probes, price display, local release and auth

### Key Information
- Branch: `codex/ccs-3.16.2-align`.
- Latest pushed commits:
  - `f4f02e3a fix: display usage price instead of rate`
  - `8e1d7bdf test: cover unit price compatibility display`
- Usage page enhancement keeps old script compatibility while adding multi-probe support through `probes`.
- Probe results may come from multiple different endpoints. The legacy single `code` path remains supported.
- UI wording was changed from rate/multiplier semantics to unit price semantics:
  - Display label is `单价`.
  - `rate` / `rateLabel` remain compatibility carrier fields.
  - `rateLabel` is treated as final display text, for example `¥0.06`.
  - Numeric-only `rate` no longer auto-appends `x`.
- Extra usage text should remain visible in the original CCS style. Do not hide or reshape the main list for this enhancement.
- Failure handling expectation: if `usage` fails but `rate` succeeds, still show the successful unit-price data; failed probes show a short exception marker.

### Important Information
- Main touched files:
  - `<repo-root>\src\components\UsageFooter.tsx`
  - `<repo-root>\tests\components\UsageFooter.test.tsx`
  - `<repo-root>\src\i18n\locales\zh.json`
  - `<repo-root>\src\i18n\locales\zh-TW.json`
  - `<repo-root>\src\i18n\locales\en.json`
  - `<repo-root>\src\i18n\locales\ja.json`
- Validation completed:
  - `vitest run tests/components/UsageFooter.test.tsx tests/lib/i18n.test.ts`: passed, 8 tests.
  - `tsc --noEmit`: passed.
  - `git diff --check`: passed.
- Cross review completed for the unit-price change:
  - Test perspective: no blocker; numeric-only `rate` must not display as `1x`.
  - Compatibility perspective: no blocker; avoid backend protocol migration.
  - Product semantics perspective: old scripts returning `x1.5` can still display that text, but new expectation is to return final unit-price text.

### Local Deployment
- Latest build was deployed locally with:
  - `docker compose -f docker-compose.ccs-web.yml build`
  - `docker compose -f docker-compose.ccs-web.yml up -d`
- Container: `ccs-gateway-web`.
- Image: `ccs-gateway-web:<local-image-tag>`.
- Internal local web/API: `http://<loopback-host>:<port>`.
- WSL NGINX external entry: `http://<loopback-host>:<port>`.
- WSL NGINX listens on `<bind-host>:<port>` and proxies to `<loopback-host>:<port>`.
- Do not expose port `15721` publicly.
- NGINX should stay on host WSL, not inside the container.

### Auth And Security
- Local CCS Web auth is enabled for public exposure.
- Auth config path: `<app-data-dir>/web-auth.json`.
- Password file path: `<app-data-dir>/web-auth-password.txt`.
- Do not store or print the generated password in summaries.
- Operator-only password retrieval commands are intentionally omitted from public documentation.
- Auth verification completed:
  - `auth.status` returned `enabled=true`.
  - Unauthenticated `get_settings` returned `401 Unauthorized`.
  - Login with generated password succeeded.
  - Authenticated management API call returned `200`.

### Deployment Boundaries
- Keep these deployment files stable unless explicitly requested:
  - `<repo-root>\.env.web`
  - `<repo-root>\docker-compose.ccs-web.yml`
  - `<repo-root>\Dockerfile.web`
  - `<repo-root>\.dockerignore`
  - `<repo-root>\pnpm-workspace.yaml`
- Container port bindings should remain local-only:
  - `<loopback-host>:<port>`
  - `<loopback-host>:<port>`
- Public access should go through WSL NGINX port `30033`.

### Follow-ups
- If public access from outside the machine is needed, verify Windows firewall, WSL forwarding, router/cloud firewall, and confirm that only `30033` is reachable.
- If another local release is requested, rebuild and restart `docker-compose.ccs-web.yml`, then re-check health and auth.
- If a new probe script example is needed, keep the old `code` path valid and prefer `probes` as a list for multi-endpoint metrics.

### Dropped Noise
- User-provided provider token, generated auth password, repeated status confirmations, and raw command logs were intentionally not preserved.
- Superseded "rate/multiplier" wording was only retained as compatibility context.
