# CCS Gateway Web Branch Maintenance Ledger

This ledger records public-safe branch decisions for this fork. It is meant to
preserve upgrade reasoning without publishing local runtime evidence.

## Current Branch Roles

| Branch | Role | Status |
| --- | --- | --- |
| `main` | Stable public branch | Merge target |
| `codex/ccs-3.16.2-align` | Current official CC Switch alignment branch | Primary integration branch |
| `codex/usage-status-filter` | Legacy feature branch based on the older v3.15 line | Cherry-pick feature only |
| `codex/upgrade-cp-yu-v315` | Historical v3.15 integration branch | Do not merge directly |

## 2026-06-12 Branch Cleanup Decision

### `codex/usage-status-filter`

Decision: preserve the feature by cherry-picking the single functional commit
onto `codex/ccs-3.16.2-align`.

Reason:

- The branch contains a useful request-log status group filter.
- It is based on the older v3.15 integration line, so merging the branch itself
  would reintroduce stale history.
- The feature applies cleanly to the 3.16.2 alignment branch with targeted
  backend and frontend changes.

Expected preserved behavior:

- Request logs can be filtered by grouped HTTP status:
  - `success`: 2xx
  - `redirect`: 3xx
  - `client_error`: 4xx
  - `server_error`: 5xx
  - `other`: outside 2xx-5xx

### `codex/upgrade-cp-yu-v315`

Decision: do not merge this branch into the current integration line.

Reason:

- It was an older v3.15 integration branch and has no merge base with the
  current 3.16.2 alignment branch.
- Its latest useful content is documentation strategy: keep a version ledger,
  record patch decisions, and avoid silently dropping local gateway behavior
  during upstream syncs.
- The old v3.15 ledger should not be copied as current truth for the 3.16.2
  line.

Preserved rule:

- When following a new upstream version, start from the official upstream
  reference, replay only deliberate local additions, and record each preserved,
  retired, or manually reviewed patch group.

## Public Repository Guardrails

Tracked docs may mention generic operational paths only when they are part of
the documented product contract. They must not include local evidence from a
private machine.

Use placeholders such as:

- `<repo-root>`
- `<wsl-distro>`
- `<host-a>`
- `<ssh-user>`
- `<timestamp>`
- `<image-tag>`
- `<container-name>`

Keep these out of tracked docs:

- local absolute paths from one operator's machine
- real private hostnames, user names, or account identifiers
- raw API responses, cookies, bearer tokens, JWTs, and provider keys
- container IDs, image digests, and long runtime inspection output
- deployment tarball paths and one-off log files
