# CCS RTK Source Audit

## Source

- Repository: <https://github.com/rtk-ai/rtk>
- Audited checkout: `805caf7 Merge pull request #1741 from gitbluf/develop`
- Local audit path: `/home/zytang/openclaw/workspace-ccs-gateway-web/repos/source-audit/rtk`
- License evidence:
  - `LICENSE`: Apache-2.0
  - `Cargo.toml`: currently says MIT
  - README badge/text: Apache-2.0

Because the repository license files disagree, CCS must treat any source-backed port as at least Apache-2.0 attribution-sensitive until the upstream license status is clarified.

## What RTK Actually Is

RTK is not a generic `tool_result` string truncator. It is a CLI proxy and command-output filtering system.

Key properties:

- Single Rust binary.
- Command-aware output filtering.
- Built-in command modules for common dev tools.
- TOML filter engine for declarative command filters.
- Tracking/savings telemetry.
- Hook/plugin integrations that rewrite shell commands before an AI agent sees raw output.

This is materially different from CCS Token Saver v1, which currently compacts selected request-body text fields.

## Relevant RTK Architecture

### Language-aware file filtering

Source: `src/core/filter.rs`

- `FilterLevel`: `none`, `minimal`, `aggressive`.
- Detects source language by extension.
- `MinimalFilter` strips comments and normalizes blank lines, but keeps Python docstrings and language-sensitive structures.
- `AggressiveFilter` keeps signatures/imports/structural lines and removes implementation details more heavily.
- Data files are intentionally not comment-stripped.

Implication for CCS:

- A source-backed CCS port should not blindly truncate any large text. It should first classify what kind of content it is.
- For file-read-like tool outputs, a language-aware filter is much closer to RTK than the current head/tail compaction.

### Global truncation caps

Source: `src/core/truncate.rs`

RTK defines semantic caps:

- errors: `20`
- warnings/test failures: `10`
- flat lists: `20`
- inventories: `50`

It also tests that reductions cannot underflow or empty non-zero caps.

Implication for CCS:

- Token Saver v2 should use semantic caps by output class, not one global character threshold.
- For test/build outputs, errors should receive more budget than progress/noise lines.

### TOML filter pipeline

Source: `src/core/toml_filter.rs`

RTK has an 8-stage declarative pipeline:

1. strip ANSI
2. regex replace
3. `match_output` short-circuit
4. strip / keep lines by regex
5. truncate lines at N characters
6. head / tail lines
7. max lines
8. `on_empty` fallback

Filters are loaded from:

1. project `.rtk/filters.toml`
2. user `~/.config/rtk/filters.toml`
3. built-in `src/filters/*.toml`
4. passthrough if no match

The schema supports inline filter tests.

Implication for CCS:

- CCS should not expand Token Saver by hardcoding endless Rust `if command contains ...` cases.
- A source-backed route is a filter registry with testable rules, likely starting with built-in read-only profiles.
- Project-local/user-defined filters require trust and security gates before being exposed inside CCS.

### Built-in command filters

Examples from `src/filters/*.toml`:

- `gradle.toml`: strip progress/config/cache lines, keep failed test/build summary, cap to 50 lines.
- `nx.toml`: strip Nx task graph noise, keep build output/errors, cap to 60 lines.
- `terraform-plan.toml`: strip refresh/lock noise, keep plan actions, use `on_empty` for no changes.
- `systemctl-status.toml`: strip blank lines, max 20 lines.

Implication for CCS:

- RTK's strongest transferable asset is not the exact text marker. It is the command-specific filter library and rule semantics.
- CCS v2 should prioritize command output classes used by coding agents: `cargo`, `npm/pnpm/tsc`, `git`, `rg/grep/find`, `docker`, `kubectl`.

### Command-specific Rust modules

Examples:

- `src/cmds/rust/cargo_cmd.rs`
  - Tracks compiled crates, warnings, errors, test failures.
  - Skips progress/download noise.
  - Emits structured summaries for successful builds/tests.
- `src/cmds/js/tsc_cmd.rs`
  - Parses `file(line,col): error TSxxxx`.
  - Groups errors by file and code.
- `src/cmds/git/diff_cmd.rs`
  - Condenses diff metadata and summarizes file changes.
  - Explicitly comments that diff content should not be blindly truncated because users make decisions from it.
- `src/cmds/system/grep_cmd.rs`
  - Uses `rg` first, grep fallback.
  - Groups matches by file.
  - Applies per-file and global caps.
  - Keeps passthrough for output flags that are already compact.
- `src/cmds/system/read.rs`
  - Language-aware file read filtering.
  - Safety fallback: if filter empties a non-empty file, show raw content.

Implication for CCS:

- A real RTK-backed Token Saver needs parser/strategy per output type, plus no-empty-output safeguards.
- The current CCS Token Saver v1 is safe but shallow: it lacks command awareness and failure-focused summaries.

## Current CCS Token Saver v1 Gap Analysis

Current CCS implementation:

- Runs in proxy request body after provider transform/outbound sanitizer.
- Default-off.
- Compresses selected fields only:
  - Anthropic `tool_result.content`
  - OpenAI Responses `function_call_output.output`
  - OpenAI Chat `role=tool.content`
  - typed text block `text`
- Skips JSON-looking strings and structured object outputs by default.
- Protects protocol identity fields and reasoning/tool-call structures.

Gaps versus RTK:

- No command detection.
- No per-command filter profiles.
- No line-based pipeline.
- No failures-first handling.
- No built-in rules for cargo/npm/tsc/git/grep/docker.
- No telemetry / savings accounting.
- No filter test schema.
- No trust model for user/project filters.

## Recommended CCS Roadmap

### RTK-1: Source-backed behavior spec

Create a CCS `TokenFilterEngine` design based on RTK concepts:

- input classifier: detect command/tool output type
- built-in profile registry
- line pipeline: strip ansi, replace, keep/strip lines, head/tail, max lines
- safety fallback: never empty non-empty output
- protocol guard: never touch IDs/cache/reasoning/tool-call structure
- telemetry: original chars, filtered chars, profile used

### RTK-2: Built-in filters, no user TOML yet

Start with read-only built-in filters only:

- `cargo test/build/check/clippy`
- `tsc`
- `npm/pnpm/vitest`
- `git status/log/diff`
- `rg/grep/find`

Do not expose project-local filter loading until a trust model exists.

### RTK-3: Integrate with CCS Token Saver

Instead of direct head/tail truncation first:

1. If field is safe textual tool output, classify content.
2. If known command output, apply command filter.
3. Else fallback to conservative head/tail compaction.
4. Record `profile=...` in request log/debug telemetry, not upstream payload.

### RTK-4: Optional external RTK binary mode

Possible but not first choice:

- Calling `rtk` binary from CCS would preserve upstream behavior but adds process overhead, installation dependency, path/security complexity, and Windows/WSL differences.
- A Rust port of the filter rules is more maintainable inside CCS.

## Go / No-Go

- Current Token Saver v1: acceptable as default-off experimental baseline.
- Claiming RTK parity: no-go.
- Next implementation should be source-backed, command-aware, and test-driven.
