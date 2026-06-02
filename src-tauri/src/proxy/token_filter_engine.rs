//! RTK-inspired pure token filtering engine.
//!
//! This module is intentionally side-effect free. It does not inspect or mutate
//! protocol JSON; callers must pass only text values that are already known safe.

use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FieldKind {
    AnthropicToolResult,
    OpenAiResponsesFunctionOutput,
    OpenAiChatToolContent,
    TypedTextBlock,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterCategory {
    CargoTestOrBuild,
    JavaScriptTestOrBuild,
    TypeScriptCompiler,
    GitStatusOrLog,
    GitDiff,
    SearchResults,
    PlainLog,
    FileReadOrSourceText,
    UnknownText,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterProfile {
    Cargo,
    JavaScriptTest,
    TypeScript,
    GitStatus,
    GitDiffPassthrough,
    SearchResults,
    PlainLog,
    Passthrough,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterConfidence {
    TrustedCommand,
    Heuristic,
    Fallback,
}

#[derive(Debug, Clone, Copy)]
pub struct CommandContext<'a> {
    pub tool_name: Option<&'a str>,
    pub command: Option<&'a str>,
    pub args: &'a [&'a str],
    pub exit_code: Option<i32>,
    pub cwd: Option<&'a str>,
    pub trusted_source: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct FilterInput<'a> {
    pub text: &'a str,
    pub field_kind: FieldKind,
    pub command_context: Option<CommandContext<'a>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[derive(Debug, Clone, Copy)]
pub struct FilterLimits {
    pub max_lines: usize,
    pub max_line_chars: usize,
    pub search_per_file: usize,
    pub keep_chars: usize,
}

impl Default for FilterLimits {
    fn default() -> Self {
        Self {
            max_lines: 80,
            max_line_chars: 180,
            search_per_file: 5,
            keep_chars: 800,
        }
    }
}

pub fn filter(input: FilterInput<'_>, limits: FilterLimits) -> FilterOutput {
    let original_chars = char_count(input.text);
    let (category, confidence) = classify(&input);
    let (profile, filtered) = match category {
        FilterCategory::CargoTestOrBuild => {
            (FilterProfile::Cargo, filter_cargo(input.text, limits))
        }
        FilterCategory::JavaScriptTestOrBuild => (
            FilterProfile::JavaScriptTest,
            filter_javascript_test(input.text, limits),
        ),
        FilterCategory::TypeScriptCompiler => {
            (FilterProfile::TypeScript, filter_tsc(input.text, limits))
        }
        FilterCategory::GitStatusOrLog => (
            FilterProfile::GitStatus,
            filter_git_status_or_log(input.text, limits),
        ),
        FilterCategory::GitDiff => (FilterProfile::GitDiffPassthrough, input.text.to_string()),
        FilterCategory::SearchResults => (
            FilterProfile::SearchResults,
            filter_search_results(input.text, limits),
        ),
        FilterCategory::PlainLog => (
            FilterProfile::PlainLog,
            filter_plain_log(input.text, limits),
        ),
        // V0 deliberately does not filter file reads until fixtures prove safety.
        FilterCategory::FileReadOrSourceText => {
            (FilterProfile::Passthrough, input.text.to_string())
        }
        // Unknown text may be source, markdown, file content, or task context. Keep it intact
        // until a safer classifier proves it is disposable output.
        FilterCategory::UnknownText => (FilterProfile::Passthrough, input.text.to_string()),
    };

    let fallback_used = !input.text.is_empty() && filtered.trim().is_empty();
    let text = if fallback_used {
        head_tail(input.text, limits.keep_chars)
    } else {
        filtered
    };
    let output_chars = char_count(&text);

    FilterOutput {
        text,
        category,
        profile,
        original_chars,
        output_chars,
        omitted_chars: original_chars.saturating_sub(output_chars),
        confidence,
        fallback_used,
    }
}

fn classify(input: &FilterInput<'_>) -> (FilterCategory, FilterConfidence) {
    if let Some(ctx) = input.command_context {
        if ctx.trusted_source {
            if let Some(category) = classify_command(ctx) {
                return (category, FilterConfidence::TrustedCommand);
            }
        }
    }

    let text = input.text;
    if looks_like_cargo(text) {
        return (
            FilterCategory::CargoTestOrBuild,
            FilterConfidence::Heuristic,
        );
    }
    if looks_like_javascript_test(text) {
        return (
            FilterCategory::JavaScriptTestOrBuild,
            FilterConfidence::Heuristic,
        );
    }
    if looks_like_tsc(text) {
        return (
            FilterCategory::TypeScriptCompiler,
            FilterConfidence::Heuristic,
        );
    }
    if looks_like_git_status_or_log(text) {
        return (FilterCategory::GitStatusOrLog, FilterConfidence::Heuristic);
    }
    if looks_like_git_diff(text) {
        return (FilterCategory::GitDiff, FilterConfidence::Heuristic);
    }
    if looks_like_search_results(text) {
        return (FilterCategory::SearchResults, FilterConfidence::Heuristic);
    }
    if looks_like_plain_log(text) {
        return (FilterCategory::PlainLog, FilterConfidence::Heuristic);
    }

    (FilterCategory::UnknownText, FilterConfidence::Fallback)
}

fn classify_command(ctx: CommandContext<'_>) -> Option<FilterCategory> {
    let cmd = ctx.command.or(ctx.tool_name).unwrap_or_default();
    let first = cmd.split_whitespace().next().unwrap_or(cmd);
    let args = ctx.args;

    match first {
        "cargo" => Some(FilterCategory::CargoTestOrBuild),
        "npm" | "pnpm" | "yarn" | "bun" => {
            if args
                .iter()
                .any(|arg| matches!(*arg, "test" | "vitest" | "jest"))
            {
                Some(FilterCategory::JavaScriptTestOrBuild)
            } else {
                None
            }
        }
        "vitest" | "jest" => Some(FilterCategory::JavaScriptTestOrBuild),
        "tsc" => Some(FilterCategory::TypeScriptCompiler),
        "rg" | "grep" => Some(FilterCategory::SearchResults),
        "cat" | "read" => Some(FilterCategory::FileReadOrSourceText),
        "git" => match args.first().copied() {
            Some("status") | Some("log") => Some(FilterCategory::GitStatusOrLog),
            // Git diff is explicit passthrough in v0.
            Some("diff") => Some(FilterCategory::GitDiff),
            _ => None,
        },
        _ => None,
    }
}

fn filter_cargo(text: &str, limits: FilterLimits) -> String {
    let mut kept = Vec::new();
    let mut compiled = 0usize;
    let mut in_diagnostic = false;

    for line in text.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("Compiling")
            || trimmed.starts_with("Checking")
            || trimmed.starts_with("Downloading")
            || trimmed.starts_with("Downloaded")
            || trimmed.starts_with("running ")
        {
            compiled += 1;
            in_diagnostic = false;
            continue;
        }

        if trimmed.starts_with("error")
            || trimmed.starts_with("warning")
            || trimmed.starts_with("note:")
            || trimmed.starts_with("help:")
            || trimmed.starts_with("-->")
        {
            in_diagnostic = true;
            kept.push(truncate_line(trimmed, limits.max_line_chars));
            continue;
        }

        if in_diagnostic
            && (trimmed.starts_with('|')
                || trimmed.starts_with('=')
                || trimmed.is_empty()
                || looks_like_cargo_code_excerpt(trimmed))
        {
            kept.push(truncate_line(trimmed, limits.max_line_chars));
            continue;
        }

        in_diagnostic = false;

        if trimmed.starts_with("Finished")
            || trimmed.starts_with("test ")
            || trimmed.starts_with("failures:")
            || trimmed.contains("panicked at")
            || trimmed.starts_with("test result:")
        {
            kept.push(truncate_line(trimmed, limits.max_line_chars));
            continue;
        }

        if !trimmed.is_empty() && (trimmed.contains("FAILED") || trimmed.contains("failed")) {
            kept.push(truncate_line(trimmed, limits.max_line_chars));
        }
    }

    if kept.is_empty() && compiled > 0 {
        return format!("cargo: ok ({} progress lines omitted)", compiled);
    }

    cap_lines(kept, limits.max_lines).join("\n")
}

fn filter_tsc(text: &str, limits: FilterLimits) -> String {
    let lines = text
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.contains("error TS") || trimmed.contains("warning TS") {
                Some(truncate_line(trimmed, limits.max_line_chars))
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    cap_lines(lines, limits.max_lines).join("\n")
}

fn filter_javascript_test(text: &str, limits: FilterLimits) -> String {
    let mut kept = Vec::new();

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || is_javascript_test_noise(trimmed) {
            continue;
        }

        if is_javascript_test_signal(trimmed) {
            kept.push(truncate_line(trimmed, limits.max_line_chars));
        }
    }

    cap_lines(kept, limits.max_lines).join("\n")
}

fn is_javascript_test_signal(line: &str) -> bool {
    line.starts_with("FAIL")
        || line.starts_with("Failed")
        || line.starts_with("Error:")
        || line.starts_with("TypeError:")
        || line.starts_with("AssertionError")
        || line.starts_with("Test Files")
        || line.starts_with("Tests")
        || line.starts_with("Snapshots")
        || line.starts_with("Duration")
        || line.starts_with("npm ERR!")
        || line.starts_with("ERR_PNPM")
        || line.contains("ELIFECYCLE")
        || line.contains(" failed")
        || looks_like_js_test_location(line)
}

fn is_javascript_test_noise(line: &str) -> bool {
    line.starts_with("PASS")
        || line.starts_with("RUN")
        || line.starts_with("Watch Usage")
        || (line.starts_with("Test Suites:") && line.contains("passed") && !line.contains("failed"))
}

fn looks_like_js_test_location(line: &str) -> bool {
    let has_test_file = line.contains(".test.") || line.contains(".spec.");
    has_test_file
        && line
            .split(':')
            .nth(1)
            .is_some_and(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
}

fn filter_git_status_or_log(text: &str, limits: FilterLimits) -> String {
    let lines = text
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                return None;
            }
            Some(truncate_line(trimmed, limits.max_line_chars))
        })
        .collect::<Vec<_>>();
    cap_lines(lines, limits.max_lines).join("\n")
}

fn filter_search_results(text: &str, limits: FilterLimits) -> String {
    let mut per_file: BTreeMap<String, usize> = BTreeMap::new();
    let mut kept = Vec::new();
    let mut omitted = 0usize;

    for line in text.lines() {
        let Some((file, _rest)) = split_search_line(line) else {
            continue;
        };
        let count = per_file.entry(file.to_string()).or_default();
        if *count < limits.search_per_file && kept.len() < limits.max_lines {
            kept.push(truncate_line(line.trim(), limits.max_line_chars));
            *count += 1;
        } else {
            omitted += 1;
        }
    }

    if omitted > 0 {
        kept.push(format!(
            "[CCS TokenFilterEngine: omitted {omitted} search result lines]"
        ));
    }
    kept.join("\n")
}

fn filter_plain_log(text: &str, limits: FilterLimits) -> String {
    let mut kept = Vec::new();
    let mut last = "";
    let mut repeat = 0usize;

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == last {
            repeat += 1;
            continue;
        }
        if repeat > 0 {
            kept.push(format!("[repeated previous line {repeat} times]"));
            repeat = 0;
        }
        kept.push(truncate_line(trimmed, limits.max_line_chars));
        last = trimmed;
        if kept.len() >= limits.max_lines {
            break;
        }
    }

    if repeat > 0 && kept.len() < limits.max_lines {
        kept.push(format!("[repeated previous line {repeat} times]"));
    }

    kept.join("\n")
}

fn looks_like_cargo(text: &str) -> bool {
    text.contains("Compiling ") || text.contains("error[E") || text.contains("test result:")
}

fn looks_like_cargo_code_excerpt(line: &str) -> bool {
    let Some((line_no, _rest)) = line.split_once('|') else {
        return false;
    };
    !line_no.trim().is_empty() && line_no.trim().chars().all(|c| c.is_ascii_digit())
}

fn looks_like_tsc(text: &str) -> bool {
    text.contains("error TS") || text.contains("warning TS")
}

fn looks_like_javascript_test(text: &str) -> bool {
    if text.contains("Test Files")
        || text.contains("npm ERR!")
        || text.contains("ERR_PNPM")
        || text.contains("Vitest")
    {
        return true;
    }

    let has_test_file_marker = text.contains(".test.") || text.contains(".spec.");
    has_test_file_marker
        && text.lines().any(|line| {
            let trimmed = line.trim_start();
            trimmed.starts_with("FAIL") || trimmed.starts_with("AssertionError")
        })
}

fn looks_like_git_status_or_log(text: &str) -> bool {
    text.contains("On branch ") || text.lines().any(is_git_log_line)
}

fn looks_like_git_diff(text: &str) -> bool {
    text.lines().take(16).any(|line| {
        line.starts_with("diff --git ")
            || line.starts_with("@@ ")
            || line.starts_with("+++ ")
            || line.starts_with("--- ")
    })
}

fn looks_like_search_results(text: &str) -> bool {
    text.lines()
        .take(8)
        .filter(|line| split_search_line(line).is_some())
        .count()
        >= 2
}

fn looks_like_plain_log(text: &str) -> bool {
    let mut total = 0usize;
    let mut log_like = 0usize;

    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        total += 1;
        if looks_like_plain_log_line(line) {
            log_like += 1;
        }
    }

    total > 20 && log_like >= 3
}

fn looks_like_plain_log_line(line: &str) -> bool {
    let trimmed = line.trim_start();
    if matches!(
        trimmed.split_whitespace().next(),
        Some("TRACE" | "DEBUG" | "INFO" | "WARN" | "WARNING" | "ERROR" | "FATAL")
    ) {
        return true;
    }

    trimmed.starts_with("[TRACE]")
        || trimmed.starts_with("[DEBUG]")
        || trimmed.starts_with("[INFO]")
        || trimmed.starts_with("[WARN]")
        || trimmed.starts_with("[WARNING]")
        || trimmed.starts_with("[ERROR]")
        || trimmed.starts_with("[FATAL]")
        || trimmed.contains(" INFO ")
        || trimmed.contains(" WARN ")
        || trimmed.contains(" ERROR ")
        || trimmed.contains(" DEBUG ")
}

fn is_git_log_line(line: &str) -> bool {
    let trimmed = line.trim();
    trimmed.len() >= 8 && trimmed.chars().take(8).all(|c| c.is_ascii_hexdigit())
}

fn split_search_line(line: &str) -> Option<(&str, &str)> {
    let mut parts = line.splitn(3, ':');
    let file = parts.next()?;
    let line_no = parts.next()?;
    let rest = parts.next()?;
    if file.is_empty() || rest.is_empty() || !line_no.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    Some((file, rest))
}

fn cap_lines(mut lines: Vec<String>, max_lines: usize) -> Vec<String> {
    if lines.len() <= max_lines {
        return lines;
    }
    let omitted = lines.len() - max_lines;
    lines.truncate(max_lines);
    lines.push(format!("[CCS TokenFilterEngine: omitted {omitted} lines]"));
    lines
}

fn truncate_line(line: &str, max_chars: usize) -> String {
    if char_count(line) <= max_chars {
        return line.to_string();
    }
    let mut out = line.chars().take(max_chars).collect::<String>();
    out.push_str("...");
    out
}

fn head_tail(text: &str, keep_chars: usize) -> String {
    let total = char_count(text);
    if total <= keep_chars {
        return text.to_string();
    }
    let head_chars = keep_chars / 2;
    let tail_chars = keep_chars.saturating_sub(head_chars);
    let head = text.chars().take(head_chars).collect::<String>();
    let tail = text
        .chars()
        .rev()
        .take(tail_chars)
        .collect::<String>()
        .chars()
        .rev()
        .collect::<String>();
    let omitted = total.saturating_sub(head_chars + tail_chars);
    format!("{head}\n\n[CCS TokenFilterEngine: omitted {omitted} chars]\n\n{tail}")
}

fn char_count(text: &str) -> usize {
    text.chars().count()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(text: &str) -> FilterInput<'_> {
        FilterInput {
            text,
            field_kind: FieldKind::AnthropicToolResult,
            command_context: None,
        }
    }

    #[test]
    fn filters_cargo_progress_but_keeps_failures() {
        let text = "Downloading crates\nCompiling a v1\nrunning 2 tests\ntest foo ... FAILED\nfailures:\nthread 'foo' panicked at src/lib.rs:1\ntest result: FAILED. 1 passed; 1 failed";
        let out = filter(input(text), FilterLimits::default());
        assert_eq!(out.category, FilterCategory::CargoTestOrBuild);
        assert!(out.text.contains("test foo ... FAILED"));
        assert!(out.text.contains("test result: FAILED"));
        assert!(!out.text.contains("Compiling a"));
    }

    #[test]
    fn cargo_compile_error_keeps_context_lines() {
        let text = "Compiling demo v0.1.0\nerror[E0425]: cannot find value `x` in this scope\n --> src/lib.rs:1:5\n  |\n1 | x;\n  | ^ not found in this scope\nhelp: consider importing it\n";
        let out = filter(input(text), FilterLimits::default());
        assert_eq!(out.category, FilterCategory::CargoTestOrBuild);
        assert!(out.text.contains("error[E0425]"));
        assert!(out.text.contains("--> src/lib.rs:1:5"));
        assert!(out.text.contains("| ^ not found"));
        assert!(out.text.contains("help:"));
        assert!(!out.text.contains("Compiling demo"));
    }

    #[test]
    fn filters_tsc_errors_only() {
        let text = "Watching for file changes.\nsrc/a.ts(1,2): error TS2322: Type bad\nsrc/b.ts(3,4): warning TS9999: Warn";
        let out = filter(input(text), FilterLimits::default());
        assert_eq!(out.category, FilterCategory::TypeScriptCompiler);
        assert!(out.text.contains("TS2322"));
        assert!(out.text.contains("TS9999"));
        assert!(!out.text.contains("Watching"));
    }

    #[test]
    fn filters_javascript_test_output_to_failures_and_summary() {
        let text = "RUN  v2.1.1 /repo\nPASS src/ok.test.ts\nFAIL src/bad.test.ts > suite > fails\nAssertionError: expected 1 to be 2\nsrc/bad.test.ts:12:5\nTest Files  1 failed | 1 passed (2)\nTests  1 failed | 3 passed (4)\nDuration  1.23s";
        let out = filter(input(text), FilterLimits::default());
        assert_eq!(out.category, FilterCategory::JavaScriptTestOrBuild);
        assert!(out.text.contains("FAIL src/bad.test.ts"));
        assert!(out.text.contains("AssertionError"));
        assert!(out.text.contains("src/bad.test.ts:12:5"));
        assert!(out.text.contains("Test Files"));
        assert!(!out.text.contains("PASS src/ok.test.ts"));
        assert!(!out.text.contains("RUN  v2.1.1"));
    }

    #[test]
    fn trusted_pnpm_test_uses_javascript_profile() {
        let args = ["test"];
        let input = FilterInput {
            text: "PASS src/ok.test.ts\nFAIL src/bad.test.ts\nTests  1 failed",
            field_kind: FieldKind::OpenAiChatToolContent,
            command_context: Some(CommandContext {
                tool_name: Some("pnpm"),
                command: Some("pnpm"),
                args: &args,
                exit_code: Some(1),
                cwd: None,
                trusted_source: true,
            }),
        };
        let out = filter(input, FilterLimits::default());
        assert_eq!(out.category, FilterCategory::JavaScriptTestOrBuild);
        assert_eq!(out.profile, FilterProfile::JavaScriptTest);
        assert!(out.text.contains("FAIL src/bad.test.ts"));
        assert!(!out.text.contains("PASS src/ok.test.ts"));
    }

    #[test]
    fn generic_fail_log_does_not_use_javascript_profile() {
        let text =
            "FAIL: health probe unavailable\nAssertionError: generic service assertion failed";
        let out = filter(input(text), FilterLimits::default());
        assert_eq!(out.category, FilterCategory::UnknownText);
        assert_eq!(out.profile, FilterProfile::Passthrough);
        assert_eq!(out.text, text);
    }

    #[test]
    fn search_results_apply_per_file_cap() {
        let text = "src/a.rs:1:one\nsrc/a.rs:2:two\nsrc/a.rs:3:three\nsrc/b.rs:1:four";
        let limits = FilterLimits {
            search_per_file: 2,
            max_lines: 10,
            ..Default::default()
        };
        let out = filter(input(text), limits);
        assert_eq!(out.category, FilterCategory::SearchResults);
        assert!(out.text.contains("src/a.rs:1:one"));
        assert!(out.text.contains("src/a.rs:2:two"));
        assert!(!out.text.contains("src/a.rs:3:three"));
        assert!(out.text.contains("omitted 1 search result"));
    }

    #[test]
    fn git_diff_without_trusted_metadata_is_passthrough() {
        let text = "diff --git a/a.rs b/a.rs\n@@ -1 +1 @@\n-old\n+new";
        let out = filter(
            input(text),
            FilterLimits {
                keep_chars: 20,
                ..Default::default()
            },
        );
        assert_eq!(out.category, FilterCategory::GitDiff);
        assert_eq!(out.profile, FilterProfile::GitDiffPassthrough);
        assert_eq!(out.text, text);
    }

    #[test]
    fn trusted_git_diff_is_passthrough_in_v0() {
        let args = ["diff"];
        let large_diff = format!(
            "diff --git a/a.rs b/a.rs\n@@ -1 +1 @@\n{}",
            "-old\n+new\n".repeat(200)
        );
        let input = FilterInput {
            text: &large_diff,
            field_kind: FieldKind::AnthropicToolResult,
            command_context: Some(CommandContext {
                tool_name: Some("git"),
                command: Some("git"),
                args: &args,
                exit_code: Some(0),
                cwd: None,
                trusted_source: true,
            }),
        };
        let out = filter(
            input,
            FilterLimits {
                keep_chars: 20,
                ..Default::default()
            },
        );
        assert_eq!(out.category, FilterCategory::GitDiff);
        assert_eq!(out.profile, FilterProfile::GitDiffPassthrough);
        assert_eq!(out.text, large_diff);
    }

    #[test]
    fn unknown_text_is_passthrough() {
        let text = "abcdefghijklmnopqrstuvwxyz0123456789";
        let out = filter(
            input(text),
            FilterLimits {
                keep_chars: 10,
                ..Default::default()
            },
        );
        assert_eq!(out.category, FilterCategory::UnknownText);
        assert_eq!(out.profile, FilterProfile::Passthrough);
        assert_eq!(out.text, text);
        assert!(!out.fallback_used);
    }

    #[test]
    fn long_markdown_like_text_is_not_plain_log() {
        let text = (1..=40)
            .map(|i| format!("## Section {i}\nThis is ordinary task context, not disposable log output."))
            .collect::<Vec<_>>()
            .join("\n");
        let out = filter(
            input(&text),
            FilterLimits {
                keep_chars: 20,
                ..Default::default()
            },
        );

        assert_eq!(out.category, FilterCategory::UnknownText);
        assert_eq!(out.profile, FilterProfile::Passthrough);
        assert_eq!(out.text, text);
    }

    #[test]
    fn file_read_category_passthrough_for_now() {
        let args = ["src/lib.rs"];
        let input = FilterInput {
            text: "fn main() { println!(\"hi\"); }",
            field_kind: FieldKind::TypedTextBlock,
            command_context: Some(CommandContext {
                tool_name: Some("cat"),
                command: Some("cat"),
                args: &args,
                exit_code: Some(0),
                cwd: None,
                trusted_source: true,
            }),
        };
        let out = filter(input, FilterLimits::default());
        assert_eq!(out.category, FilterCategory::FileReadOrSourceText);
        assert_eq!(out.text, input.text);
    }
}
