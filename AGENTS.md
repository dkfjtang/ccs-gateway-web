# Project Operating Principles

This repository is public on GitHub. Treat every tracked file as publishable to the internet.

## Privacy And Secret Handling

- Do not commit API keys, tokens, cookies, private base URLs, account names, customer data, local machine identifiers, local absolute paths, WSL distro-specific private state, or container runtime dumps.
- Do not commit real `.env` files, private service exports, local logs, transcripts, screenshots containing private data, database dumps, or generated artifacts from local release verification.
- Use placeholders for examples, such as `{{apiKey}}`, `{{baseUrl}}`, `example.com`, and synthetic IDs.
- GitHub-facing documentation must not include local machine details, private hostnames, real server IPs, personal workspace paths, WSL distro names from one operator's machine, local proxy endpoints, container IDs, image digests, or runtime evidence copied from a private environment. Replace them with placeholders such as `<repo-root>`, `<wsl-distro>`, `<host-a>`, `<host-ip>`, `<proxy-url>`, and `<timestamp>`.
- Keep local release evidence under ignored local folders such as `.run/`. If a reusable script writes logs, it must default to an ignored local directory.
- Before staging or publishing changes, review `git status --short` and `git diff` for accidental sensitive content.

## Documentation Rules

- Keep GitHub-facing docs focused on reusable procedure, contract, and sanitized decisions.
- Do not preserve one-off production command output, raw container inspection, private account names, host nicknames, or local filesystem paths in tracked docs.
- If a session note is worth keeping, rewrite it as a sanitized summary with placeholders and durable lessons.
- Put detailed local release logs, screenshots, tarball names, and runtime evidence in `.run/` or another ignored local folder.

## Local WSL Release Boundary

- The local WSL container release target is the `ccs-gateway-web` service from `docker-compose.ccs-web.yml`.
- Do not touch the desktop CC Switch installation when the request is about the WSL `ccs-web` modified build.
- Local WSL container publishing must go through `scripts/publish-local-wsl-ccs-web.ps1` so build, recreate, health checks, and ignored local logs stay consistent.
- Local WSL relay inspection and repair must also go through `scripts/publish-local-wsl-ccs-web.ps1` using `-RepairRelay` with either `-DryRun` or `-Force`; do not add or use separate relay repair scripts.
- One-click local WSL release wrappers must call `scripts/publish-local-wsl-ccs-web.ps1` and keep temporary files/logs under ignored local directories such as `<repo-root>/tmp/` and `<repo-root>/.run/`.
- Local container state, mounts, image IDs, and health-check output are operational evidence only. Keep them out of tracked documentation unless sanitized.

## Upstream Routing Alignment

- Provider routing, failover, circuit breaker, and retry classification should stay aligned with official CC Switch unless a CCS-specific feature explicitly requires divergence.
- When changing proxy routing behavior, first compare against the pinned upstream reference under `.upstream/cc-switch-v3.16.3`, then preserve only deliberate local additions such as web/server compatibility, managed-account guards, Responses session stickiness, and local overlay behavior.
- Do not narrow official failover behavior by default. HTTP retry buckets, provider health updates, circuit breaker state transitions, and runtime circuit-config hot updates should match upstream unless the change has a documented product reason and regression coverage.
