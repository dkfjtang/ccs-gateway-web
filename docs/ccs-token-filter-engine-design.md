# CCS TokenFilterEngine Design

## Status

Runtime v0 is implemented and remains default-off. Current v0 covers Cargo, TypeScript compiler, JavaScript test/build summaries, git status/log, search results, plain logs, unknown-text fallback, and explicit passthrough for trusted git diff and file-read/source text.

## Goal

Move CCS Token Saver from a safe but shallow head/tail compactor toward an RTK-inspired command-aware filter engine.

This design is source-backed by:

- [CCS RTK Source Audit](ccs-rtk-source-audit.md)
- [CCS Caveman Source Audit](ccs-caveman-source-audit.md)
- [CCS 9Router-Inspired Upgrade Spec](ccs-9router-upgrade-spec.md)

## Non-goals

- Do not claim full RTK parity.
- Do not execute external `rtk` binary from CCS in v0.
- Do not load user/project TOML filters in v0.
- Do not mutate SSE streams or output responses.
- Do not implement Caveman runtime output rewriting.
- Do not enable Token Saver by default.
- Do not compress Git diffs in v0 unless a later guarded design and fixtures explicitly allow it.

## Current baseline

Current Token Saver v1:

- is default-off;
- runs after provider transform and outbound sanitizer;
- only touches selected textual tool-result fields;
- skips JSON-looking strings and structured object outputs;
- protects protocol identity fields, reasoning, tool calls, signatures and cache controls.

This remains the fallback path for unknown text.

## Proposed architecture

```text
safe request field
  -> TokenSaver
      -> TokenFilterEngine
          -> classify text / command output
          -> apply built-in profile
          -> fallback head/tail compaction
      -> return compacted text
  -> upstream request body
```

### TokenFilterEngine

A pure Rust module with no I/O:

```rust
pub struct FilterInput<'a> {
    pub text: &'a str,
    pub field_kind: FieldKind,
    pub command_context: Option<CommandContext<'a>>,
}

pub struct CommandContext<'a> {
    pub tool_name: Option<&'a str>,
    pub command: Option<&'a str>,
    pub args: &'a [&'a str],
    pub exit_code: Option<i32>,
    pub cwd: Option<&'a str>,
    pub trusted_source: bool,
}

pub struct FilterOutput {
    pub text: String,
    pub category: FilterCategory,
    pub profile: FilterProfile,
    pub original_chars: usize,
    pub output_chars: usize,
    pub omitted_chars: usize,
    pub confidence: FilterConfidence,
    pub fallback_used: bool,
}
```

The engine must be deterministic and side-effect free.

### FieldKind

Initial kinds:

- `AnthropicToolResult`
- `OpenAiResponsesFunctionOutput`
- `OpenAiChatToolContent`
- `TypedTextBlock`

Field kind is derived by the existing Token Saver traversal. The engine should not walk JSON protocol structure itself in v0.

### CommandContext

RTK is command-aware. CCS v0 must therefore prefer trusted command metadata when available.

Rules:

- If `command_context.trusted_source == true`, category detection may use `tool_name`, `command`, `args` and `exit_code`.
- If command metadata is absent or untrusted, classification must fall back to conservative text heuristics.
- Text heuristics must never enable risky profiles such as GitDiff truncation.
- Provider identity must not decide protocol safety. Provider metadata can be logged later, but it is not part of v0 safety branching.

## Classification

The engine should classify safe text into one of these categories:

1. `CargoTestOrBuild`
2. `JavaScriptTestOrBuild`
3. `TypeScriptCompiler`
4. `GitStatusOrLog`
5. `SearchResults`
6. `PlainLog`
7. `FileReadOrSourceText`
8. `UnknownText`

V0 classification should be heuristic and conservative:

| Category | Trigger examples | Notes |
|---|---|---|
| `CargoTestOrBuild` | `Compiling`, `Finished`, `error[E`, `running N tests`, `test result:` | Keep errors/failures/summaries. |
| `JavaScriptTestOrBuild` | trusted `npm/pnpm/yarn/bun test`, `vitest`, `jest`, or `FAIL` / `Test Files` markers | Keep failures, assertion/errors, test file locations and summary lines; drop pass/run noise. |
| `TypeScriptCompiler` | `error TS`, `file.ts(line,col)` | Group by file/code later; v0 keep matching lines. |
| `GitStatusOrLog` | trusted `git status` / `git log`, or clear status/log markers | Compact list format later. |
| `SearchResults` | trusted `rg` / `grep`, or `path:line:match` output | V0 must cap per file and globally. |
| `PlainLog` | many lines, repeated prefixes, timestamps | Strip blank/repeated lines in v0. |
| `FileReadOrSourceText` | trusted read/cat output with file path/extension metadata | Interface in v0; profile may be disabled until fixtures are strong. |
| `UnknownText` | fallback | Existing head/tail compaction. |

## Built-in profiles

### Common stages

Inspired by RTK TOML pipeline, but implemented as built-in Rust profiles first:

1. strip ANSI
2. normalize blank lines
3. line-level noise removal
4. profile-specific keep/strip rules
5. line truncation
6. head/tail/max lines
7. on-empty fallback
8. no-empty-output safety check

### Safety invariant

If input text is non-empty and filtered output becomes empty unexpectedly, return the original text or a conservative head/tail fallback. Never emit empty output for non-empty tool data unless an explicit profile says `ok` / `no changes`.

### Initial profiles

#### CargoTestOrBuild

Keep:

- compile errors and warning blocks;
- failed test names;
- `test result:` lines;
- final `Finished` line only when useful;
- panic/failure sections.

Drop:

- `Compiling`, `Checking`, `Downloading`, `Downloaded` progress lines;
- duplicate warning summary lines.

#### JavaScriptTestOrBuild

Keep:

- failed test lines;
- assertion and error lines;
- test file locations such as `*.test.*:line:col` / `*.spec.*:line:col`;
- summary lines (`Test Files`, `Tests`, `Snapshots`, `Duration`);
- package-manager failure lines (`npm ERR!`, `ERR_PNPM`, `ELIFECYCLE`).

Drop:

- successful `PASS` lines;
- `RUN` / watch usage noise;
- passed-only suite summaries.

#### TypeScriptCompiler

Keep:

- lines matching TypeScript error/warning format;
- file path, line/col, code and message.

V0 can cap total lines. Grouping by file/code can be v1.

#### GitDiff

GitDiff is not an active v0 profile.

V0 behavior:

- passthrough by default;
- no text-heuristic diff compression;
- no code hunk rewriting;
- future guarded truncation requires trusted command metadata and dedicated diff fixtures.

Reason: diffs are high-risk decision material for review and patch generation. Blind compression can change model judgment.

#### SearchResults

Keep path/line/match lines.

V0 must include:

- per-file cap;
- global cap;
- clear omission markers when caps are hit.

#### PlainLog

Drop blank lines and repeated identical lines with count marker. Cap total lines.

#### FileReadOrSourceText

V0 design includes this category because RTK source audit shows language-aware file filtering is core.

Implementation options:

- v0 may classify but passthrough until enough fixtures exist;
- v0.1 should add language-aware minimal filtering for trusted file-read outputs.

Do not claim complete RTK absorption until this category exists.

#### UnknownText

Use existing Token Saver head/tail compaction.

## Configuration

Existing config remains:

- `tokenSaver`
- `tokenSaverMinChars`
- `tokenSaverKeepChars`

New optional config for future v1, not required for v0:

- `tokenSaverProfile`: `safe` | `balanced` | `aggressive`

Do not add user TOML filter loading in v0.

## Internal metrics

Do not send telemetry externally.

V0 `FilterOutput` should always include non-sensitive local metrics:

- category;
- selected profile;
- original chars;
- output chars;
- omitted chars;
- confidence;
- whether fallback was used.

Request logs may record these metrics later, but must not include raw tool result text.

## Protocol safety

The engine must never see or mutate protocol metadata. Existing Token Saver traversal remains responsible for selecting safe text values.

Still protected:

- IDs and call IDs;
- `previous_response_id`;
- `cache_control`;
- `signature`;
- reasoning/thinking blocks;
- tool/function call arguments;
- structured object tool outputs;
- JSON-looking tool output strings.

## Testing plan

### Unit tests

- classifier tests for each initial category;
- negative misclassification tests;
- profile tests with representative RTK-style examples;
- no-empty-output invariant;
- JSON-looking string skip remains in Token Saver;
- structured object output skip remains in Token Saver;
- protocol-field preservation remains in Token Saver.

### Integration-adjacent tests

- Anthropic `tool_result.content` cargo output;
- OpenAI Responses `function_call_output.output` tsc output;
- OpenAI Chat `role=tool.content` rg output with per-file cap;
- JavaScript/Vitest/Jest output keeps failures and summaries while dropping pass/run noise;
- GitDiff passthrough when metadata is absent/untrusted;
- unknown long text fallback;
- default-off no-op.

### Review gate

Any runtime implementation requires:

1. Rust tests passing in Docker or local cargo;
2. independent test agent review;
3. independent architecture review;
4. no production deployment unless explicitly requested.

## Migration path

1. Keep current Token Saver v1 committed and default-off.
2. Add `token_filter_engine.rs` as internal pure module.
3. Route safe strings through engine.
4. Keep existing head/tail behavior as fallback.
5. Add local debug logging only after core behavior is proven.
6. Consider built-in TOML-compatible profiles later.

## Future trust gate for user/project filters

User/project TOML filters are out of scope for v0.

Before enabling them, CCS needs:

- explicit trust UI;
- source display (project/user/global);
- disabled-by-default behavior;
- schema validation;
- inline tests or dry-run preview;
- ability to disable a filter quickly.

## Open questions for implementation

- Can CCS reliably capture command metadata from tool results, or do we need a separate metadata propagation task first?
- Should FileReadOrSourceText ship as passthrough in v0 or minimal language-aware filtering?
- Should metrics live in request logs or separate local counters?
- Should Token Saver remain under Optimizer settings, or move to a dedicated Compression/Token panel?
