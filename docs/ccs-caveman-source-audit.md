# CCS Caveman Source Audit

## Source

- Repository: <https://github.com/JuliusBrussee/caveman>
- Audited checkout: `655b7d9 docs: feature caveman-code with a callout card after Before/After`
- Local audit path: `/home/zytang/openclaw/workspace-ccs-gateway-web/repos/source-audit/caveman`
- License: MIT

## What Caveman Actually Is

Caveman is not primarily a proxy-layer response compressor. It is a Claude Code skill / prompt / hook ecosystem for token-efficient communication.

Main components:

- `skills/caveman/SKILL.md`: terse response style rules.
- `src/rules/caveman-activate.md`: compact activation rule.
- `src/hooks/caveman-config.js`: mode config, safe flag file handling, status/history helpers.
- `skills/caveman-compress/SKILL.md`: memory/prose file compression workflow.
- `skills/caveman-compress/scripts/*.py`: compression orchestrator, file-type detection, validation.
- `commands/*.toml`, agents, install scripts and platform integration files.

## Caveman Skill Behavior

Source: `skills/caveman/SKILL.md`

Key rules:

- Drop articles, filler, pleasantries, hedging.
- Keep technical terms exact.
- Fragments are allowed.
- Code blocks, errors, commits and PRs stay normal / exact.
- Pattern: `[thing] [action] [reason]. [next step].`
- Modes:
  - `lite`
  - `full`
  - `ultra`
  - `wenyan-lite`
  - `wenyan-full`
  - `wenyan-ultra`

Important safety boundary:

- Auto-Clarity disables caveman for security warnings, irreversible actions, multi-step sequences where ambiguity matters, or when the user is confused.
- Caveman resumes after the clear section.

Implication for CCS:

- Caveman should not be implemented as a blind response-body transformer inside the CCS proxy.
- A source-backed CCS integration should be a style/profile instruction for supported agents, not a post-hoc mutation of JSON/SSE output.

## Caveman Compress Behavior

Source: `skills/caveman-compress/SKILL.md` and `skills/caveman-compress/scripts/*.py`

Purpose:

- Compress natural language memory files such as `CLAUDE.md`, todos and preferences.
- Preserve technical substance, code, URLs and markdown structure.
- Backup original as `<filename>.original.md` before overwriting.

Hard preserve rules:

- fenced code blocks
- inline code
- URLs and markdown links
- file paths
- commands
- technical terms
- proper nouns
- dates, versions and numeric values
- environment variables
- markdown headings, lists, tables and frontmatter

Hard boundaries:

- Only natural language file types.
- Never modify `.py`, `.js`, `.ts`, `.json`, `.yaml`, `.toml`, `.env`, `.lock`, `.css`, `.html`, `.xml`, `.sql`, `.sh`.
- If unsure whether something is code or prose, leave unchanged.
- Never compress backup files.

Security implementation details:

- `compress.py` refuses sensitive path names such as `.env`, credentials, secrets, keys, `.ssh`, `.aws`, `.kube`, `.docker`.
- Max file size is 500KB.
- Compression sends text to Anthropic or Claude CLI; this is an explicit third-party boundary.
- Backup is verified after write before touching the original.
- If validation fails, it attempts targeted fix rather than full recompression.
- If still failing, original file is left untouched.

Validation behavior from `validate.py`:

- headings count/order
- fenced code blocks exact match
- URLs exact set match
- paths warning
- bullet count drift warning
- inline code exact multiset match

Implication for CCS:

- Caveman-compress is suitable for a separate memory/prose file compressor tool, not for runtime model response mutation.
- If CCS adds a memory/config compression feature, it should borrow these hard preserve + backup + validation rules.

## Hook / Config Safety

Source: `src/hooks/caveman-config.js`

Notable design points:

- Mode resolution order:
  1. `CAVEMAN_DEFAULT_MODE`
  2. config file
  3. default `full`
- Valid modes include `off`, `lite`, `full`, `ultra`, `wenyan-*`, `commit`, `review`, `compress`.
- Flag file writes are symlink-safe:
  - creates parent directory
  - handles symlinked parent dirs carefully
  - uses `O_NOFOLLOW` where available
  - writes temp file then rename
  - permissions `0600`
- Flag reads are size-capped and whitelist-validated to prevent secret exfiltration by symlink substitution.

Implication for CCS:

- If CCS stores Caveman profile flags/config, use the same security posture:
  - avoid predictable unsafe file writes
  - cap and validate flag content
  - do not read arbitrary user-controlled paths into prompts

## Current CCS Caveman Status

Current CCS implementation keeps proxy-layer Caveman output compression reserved, but adds an opt-in prompt preset path for style profiles:

- no runtime output compression
- no SSE mutation
- no Responses item mutation
- no usage parsing changes
- prompt preset creation exists for `lite`, `full`, and `ultra`
- created presets are disabled by default and must be manually enabled per app

This is correct given source audit findings because Caveman is applied at the prompt/style layer, not as a post-hoc response transformer.

## Recommended CCS Integration

### Caveman-1: Agent style profile, not proxy output transformer

Implemented first as disabled prompt presets:

- `caveman-lite`
- `caveman-full`
- `caveman-ultra`

Apply it at the agent instruction / prompt layer where supported:

- OpenClaw agent config/profile
- provider-specific system prompt augmentation where safe
- user-visible opt-in setting

Do not mutate streamed response chunks or OpenAI Responses items after generation. The current UI creates disabled prompt presets; users must manually enable one for the selected app.

### Caveman-2: Auto-Clarity rules

Any CCS/OpenClaw integration must preserve Caveman's automatic clarity exits:

- security warnings
- destructive or irreversible confirmation prompts
- ambiguous multi-step instructions
- user asks for clarification
- code, commits and PR text stay normal

### Caveman-3: Memory/prose compressor

If CCS adds file compression:

- support only natural language files
- require explicit file selection
- back up original first
- validate code blocks, URLs, headings and inline code
- refuse sensitive filenames and private config directories
- leave original untouched on validation failure

### Caveman-4: No production default

Caveman should remain off by default and never be silently enabled for all responses.

## Go / No-Go

- Proxy response-body Caveman transformer: no-go.
- Agent style profile based on Caveman skill rules: go for spec, then opt-in implementation.
- Memory/prose file compressor based on `caveman-compress`: go for separate feature, with strong safety gates.
