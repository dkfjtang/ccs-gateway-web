//! Token Saver request compression inspired by 9Router RTK.
//!
//! This module intentionally only rewrites large textual payloads. Protocol identity
//! fields (`id`, `call_id`, `tool_call_id`, `previous_response_id`), tool call
//! structure, reasoning blocks, signatures and `cache_control` are preserved.

use serde_json::Value;

use super::{
    token_filter_engine::{self, CommandContext, FieldKind, FilterInput, FilterLimits},
    types::OptimizerConfig,
};

const MAX_COMPRESS_CHARS: usize = 10 * 1024 * 1024;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TokenSaverSummary {
    pub candidate_fields: usize,
    pub compressed_fields: usize,
    pub skipped_below_threshold: usize,
    pub skipped_json_like: usize,
    pub skipped_too_large: usize,
    pub skipped_not_smaller: usize,
    pub skipped_empty_output: usize,
    pub original_chars: usize,
    pub output_chars: usize,
    pub omitted_chars: usize,
}

impl TokenSaverSummary {
    pub fn saved_chars(&self) -> usize {
        self.original_chars.saturating_sub(self.output_chars)
    }

    fn record_skip(&mut self, reason: CompressionSkipReason, original_chars: usize) {
        self.candidate_fields += 1;
        self.original_chars += original_chars;
        self.output_chars += original_chars;
        match reason {
            CompressionSkipReason::BelowThreshold => self.skipped_below_threshold += 1,
            CompressionSkipReason::JsonLike => self.skipped_json_like += 1,
            CompressionSkipReason::TooLarge => self.skipped_too_large += 1,
        }
    }

    fn record_result(&mut self, result: &CompressionResult) {
        self.candidate_fields += 1;
        self.original_chars += result.original_chars;
        self.output_chars += match result.action {
            CompressionAction::Compressed => result.output_chars,
            CompressionAction::SkippedEmptyOutput | CompressionAction::SkippedNotSmaller => {
                result.original_chars
            }
        };
        self.omitted_chars += match result.action {
            CompressionAction::Compressed => result.omitted_chars,
            CompressionAction::SkippedEmptyOutput | CompressionAction::SkippedNotSmaller => 0,
        };
        match result.action {
            CompressionAction::Compressed => self.compressed_fields += 1,
            CompressionAction::SkippedEmptyOutput => self.skipped_empty_output += 1,
            CompressionAction::SkippedNotSmaller => self.skipped_not_smaller += 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CompressionResult {
    original_chars: usize,
    output_chars: usize,
    omitted_chars: usize,
    category: token_filter_engine::FilterCategory,
    profile: token_filter_engine::FilterProfile,
    fallback_used: bool,
    action: CompressionAction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CompressionAction {
    Compressed,
    SkippedEmptyOutput,
    SkippedNotSmaller,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CompressionSkipReason {
    BelowThreshold,
    JsonLike,
    TooLarge,
}

/// Apply request-side token saving in-place.
pub fn optimize(body: &mut Value, config: &OptimizerConfig) -> TokenSaverSummary {
    if !config.enabled || !config.token_saver {
        return TokenSaverSummary::default();
    }

    let min_chars = config.token_saver_min_chars.max(1);
    let keep_chars = config
        .token_saver_keep_chars
        .max(80)
        .min(min_chars.saturating_sub(1));
    let mut summary = TokenSaverSummary::default();
    compress_value(body, min_chars, keep_chars, &mut summary);
    summary
}

fn compress_value(
    value: &mut Value,
    min_chars: usize,
    keep_chars: usize,
    summary: &mut TokenSaverSummary,
) {
    match value {
        Value::Object(map) => {
            let block_type = map
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let role = map
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            if is_error_result_block(map) {
                return;
            }
            let compress_keys: &[&str] = match (block_type.as_str(), role.as_str()) {
                ("tool_result", _) => &["content"],
                ("function_call_output", _) => &["output"],
                ("", "tool") => &["content"],
                _ => &[],
            };

            for (key, child) in map.iter_mut() {
                if is_protected_field(key) || should_skip_block_field(block_type.as_str(), key) {
                    continue;
                }

                if compress_keys.contains(&key.as_str()) {
                    compress_text_like(
                        child,
                        min_chars,
                        keep_chars,
                        field_kind_for(block_type.as_str(), role.as_str()),
                        summary,
                    );
                } else {
                    compress_value(child, min_chars, keep_chars, summary);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                compress_value(item, min_chars, keep_chars, summary);
            }
        }
        _ => {}
    }
}

fn compress_text_like(
    value: &mut Value,
    min_chars: usize,
    keep_chars: usize,
    field_kind: FieldKind,
    summary: &mut TokenSaverSummary,
) {
    match value {
        Value::String(text) => {
            if let Some(reason) = compression_skip_reason(text, min_chars) {
                summary.record_skip(reason, text.chars().count());
            } else {
                let filtered = filter_safe_text(text, keep_chars, field_kind);
                log_compression_result(field_kind, &filtered.metrics);
                summary.record_result(&filtered.metrics);
                *text = filtered.text;
            }
        }
        Value::Array(items) => {
            for item in items {
                compress_text_part(item, min_chars, keep_chars, field_kind, summary);
            }
        }
        // Structured object outputs often encode machine-readable tool results.
        // Keep them intact instead of guessing which fields are safe to compact.
        Value::Object(_) => {}
        _ => {}
    }
}

fn compress_text_part(
    value: &mut Value,
    min_chars: usize,
    keep_chars: usize,
    field_kind: FieldKind,
    summary: &mut TokenSaverSummary,
) {
    let Value::Object(map) = value else {
        return;
    };
    let part_type = map.get("type").and_then(Value::as_str).unwrap_or_default();
    if !matches!(part_type, "text" | "input_text" | "output_text") {
        return;
    }
    let Some(Value::String(text)) = map.get_mut("text") else {
        return;
    };
    if let Some(reason) = compression_skip_reason(text, min_chars) {
        summary.record_skip(reason, text.chars().count());
    } else {
        let filtered = filter_safe_text(text, keep_chars, field_kind);
        log_compression_result(field_kind, &filtered.metrics);
        summary.record_result(&filtered.metrics);
        *text = filtered.text;
    }
}

fn field_kind_for(block_type: &str, role: &str) -> FieldKind {
    match (block_type, role) {
        ("tool_result", _) => FieldKind::AnthropicToolResult,
        ("function_call_output", _) => FieldKind::OpenAiResponsesFunctionOutput,
        ("", "tool") => FieldKind::OpenAiChatToolContent,
        _ => FieldKind::TypedTextBlock,
    }
}

struct FilteredText {
    text: String,
    metrics: CompressionResult,
}

fn filter_safe_text(text: &str, keep_chars: usize, field_kind: FieldKind) -> FilteredText {
    let input = FilterInput {
        text,
        field_kind,
        command_context: infer_command_context(text),
    };
    let output = token_filter_engine::filter(
        input,
        FilterLimits {
            keep_chars,
            ..FilterLimits::default()
        },
    );
    let original_chars = text.chars().count();
    let output_chars = output.text.chars().count();
    let action = if output.text.trim().is_empty() {
        CompressionAction::SkippedEmptyOutput
    } else if output_chars >= original_chars {
        CompressionAction::SkippedNotSmaller
    } else {
        CompressionAction::Compressed
    };
    let text = if action == CompressionAction::Compressed {
        output.text
    } else {
        text.to_string()
    };
    FilteredText {
        text,
        metrics: CompressionResult {
            original_chars,
            output_chars,
            omitted_chars: output.omitted_chars,
            category: output.category,
            profile: output.profile,
            fallback_used: output.fallback_used,
            action,
        },
    }
}

fn log_compression_result(field_kind: FieldKind, result: &CompressionResult) {
    log::debug!(
        "[TokenSaver] action={:?} field_kind={:?} category={:?} profile={:?} original_chars={} output_chars={} omitted_chars={} fallback_used={}",
        result.action,
        field_kind,
        result.category,
        result.profile,
        result.original_chars,
        result.output_chars,
        result.omitted_chars,
        result.fallback_used
    );
}

fn infer_command_context(text: &str) -> Option<CommandContext<'_>> {
    let first = text
        .lines()
        .find(|line| !line.trim().is_empty())?
        .trim_start();
    let command = if first.starts_with("Compiling ")
        || first.contains("error[E")
        || first.contains("test result:")
    {
        Some("cargo")
    } else if first.contains("error TS")
        || first.contains("warning TS")
        || text.contains("error TS")
    {
        Some("tsc")
    } else if first.starts_with("FAIL")
        || first.contains("AssertionError")
        || first.contains("Vitest")
        || text.contains("Test Files")
        || text.contains("npm ERR!")
        || text.contains("ERR_PNPM")
    {
        Some("vitest")
    } else if text
        .lines()
        .take(8)
        .filter(|line| looks_like_search_result_line(line))
        .count()
        >= 2
    {
        Some("rg")
    } else {
        None
    }?;

    Some(CommandContext {
        tool_name: Some(command),
        command: Some(command),
        args: &[],
        exit_code: None,
        cwd: None,
        trusted_source: false,
    })
}

fn looks_like_search_result_line(line: &str) -> bool {
    let mut parts = line.splitn(3, ':');
    let Some(file) = parts.next() else {
        return false;
    };
    let Some(line_no) = parts.next() else {
        return false;
    };
    let Some(rest) = parts.next() else {
        return false;
    };
    !file.is_empty() && !rest.is_empty() && line_no.chars().all(|c| c.is_ascii_digit())
}

fn compression_skip_reason(text: &str, min_chars: usize) -> Option<CompressionSkipReason> {
    let char_count = text.chars().count();
    if char_count < min_chars {
        return Some(CompressionSkipReason::BelowThreshold);
    }
    if char_count > MAX_COMPRESS_CHARS {
        return Some(CompressionSkipReason::TooLarge);
    }

    // JSON-looking tool output is usually intended to stay machine-readable.
    let trimmed = text.trim_start();
    if trimmed.starts_with('{') || trimmed.starts_with('[') {
        return Some(CompressionSkipReason::JsonLike);
    }

    None
}

fn is_error_result_block(map: &serde_json::Map<String, Value>) -> bool {
    map.get("is_error").and_then(Value::as_bool) == Some(true)
        || map.get("status").and_then(Value::as_str) == Some("error")
}

fn is_protected_field(key: &str) -> bool {
    matches!(
        key,
        "id" | "call_id"
            | "tool_call_id"
            | "tool_use_id"
            | "previous_response_id"
            | "response_id"
            | "cache_control"
            | "signature"
            | "encrypted_content"
            | "name"
            | "role"
            | "type"
            | "model"
    )
}

fn should_skip_block_field(block_type: &str, key: &str) -> bool {
    if matches!(
        block_type,
        "reasoning"
            | "thinking"
            | "redacted_thinking"
            | "tool_call"
            | "function_call"
            | "tool_use"
            | "computer_call_output"
    ) {
        return true;
    }

    // Responses function_call_output must keep its call identity, but its textual output can be compacted.
    block_type == "function_call_output" && key != "output"
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn enabled_config() -> OptimizerConfig {
        OptimizerConfig {
            enabled: true,
            token_saver: true,
            token_saver_min_chars: 20,
            token_saver_keep_chars: 10,
            ..Default::default()
        }
    }

    fn long_plain_text() -> String {
        "abcdefghijklmnopqrstuvwxyz0123456789".repeat(20)
    }

    #[test]
    fn leaves_unknown_tool_result_text_unchanged_but_keeps_protocol_fields() {
        let long = long_plain_text();
        let mut body = json!({
            "previous_response_id": "resp_prev",
            "input": [{
                "type": "message",
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": "tool_123",
                    "cache_control": {"type": "ephemeral"},
                    "content": long
                }]
            }]
        });

        optimize(&mut body, &enabled_config());

        let block = &body["input"][0]["content"][0];
        assert_eq!(body["previous_response_id"], "resp_prev");
        assert_eq!(block["tool_use_id"], "tool_123");
        assert_eq!(block["cache_control"]["type"], "ephemeral");
        assert_eq!(block["content"], long);
    }

    #[test]
    fn leaves_reasoning_and_tool_call_payloads_unchanged() {
        let arguments = "abcdefghijklmnopqrstuvwxyz0123456789";
        let reasoning = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({
            "input": [{
                "type": "reasoning",
                "id": "rs_1",
                "summary": [{"type": "text", "text": reasoning}],
                "signature": "sig_1"
            }, {
                "type": "function_call",
                "call_id": "call_1",
                "name": "read_file",
                "arguments": arguments
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["summary"][0]["text"], reasoning);
        assert_eq!(body["input"][0]["signature"], "sig_1");
        assert_eq!(body["input"][1]["call_id"], "call_1");
        assert_eq!(body["input"][1]["arguments"], arguments);
    }

    #[test]
    fn leaves_unknown_openai_tool_message_content_unchanged() {
        let long = long_plain_text();
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["tool_call_id"], "call_1");
        assert_eq!(body["messages"][0]["content"], long);
    }

    #[test]
    fn leaves_unknown_openai_tool_message_text_parts_unchanged() {
        let long = long_plain_text();
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": [{"type": "text", "text": long}]
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["tool_call_id"], "call_1");
        assert_eq!(body["messages"][0]["content"][0]["text"], long);
    }

    #[test]
    fn leaves_long_user_text_blocks_unchanged() {
        let long = long_plain_text();
        let mut body = json!({
            "messages": [{
                "role": "user",
                "content": [{"type": "text", "text": long}]
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["content"][0]["text"], long);
    }

    #[test]
    fn leaves_unknown_function_call_output_unchanged() {
        let long = long_plain_text();
        let mut body = json!({
            "input": [{
                "type": "function_call_output",
                "call_id": "call_1",
                "output": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["call_id"], "call_1");
        assert_eq!(body["input"][0]["output"], long);
    }

    #[test]
    fn filter_safe_text_reports_compression_metrics_without_body_content() {
        let input = (1..=160)
            .map(|i| format!("INFO build log line {i} {}", "z".repeat(48)))
            .collect::<Vec<_>>()
            .join("\n");

        let filtered = filter_safe_text(&input, 10, FieldKind::OpenAiResponsesFunctionOutput);

        assert_eq!(filtered.metrics.action, CompressionAction::Compressed);
        assert_eq!(
            filtered.metrics.category,
            token_filter_engine::FilterCategory::PlainLog
        );
        assert!(filtered.metrics.original_chars > filtered.metrics.output_chars);
        assert!(filtered.metrics.omitted_chars > 0);
        assert!(filtered.text.contains("INFO build log line 1"));
    }

    #[test]
    fn filter_safe_text_reports_not_smaller_skip() {
        let input = "diff --git a/a.rs b/a.rs\n@@ -1 +1 @@\n-old\n+new";

        let filtered = filter_safe_text(input, 10, FieldKind::OpenAiChatToolContent);

        assert_eq!(
            filtered.metrics.action,
            CompressionAction::SkippedNotSmaller
        );
        assert_eq!(
            filtered.metrics.category,
            token_filter_engine::FilterCategory::GitDiff
        );
        assert_eq!(
            filtered.metrics.profile,
            token_filter_engine::FilterProfile::GitDiffPassthrough
        );
        assert_eq!(filtered.text, input);
    }

    #[test]
    fn leaves_error_tool_result_unchanged() {
        let long_error = long_plain_text();
        let mut body = json!({
            "messages": [{
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": "tool_1",
                    "is_error": true,
                    "content": long_error
                }]
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["content"][0]["content"], long_error);
    }

    #[test]
    fn leaves_error_function_call_output_unchanged() {
        let long_error = long_plain_text();
        let mut body = json!({
            "input": [{
                "type": "function_call_output",
                "call_id": "call_1",
                "status": "error",
                "output": long_error
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["output"], long_error);
    }

    #[test]
    fn compresses_cargo_output_with_filter_engine() {
        let cargo = "Downloading crates
Compiling demo v0.1.0
running 1 test
test foo ... FAILED
test result: FAILED. 0 passed; 1 failed";
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": cargo
            }]
        });

        optimize(&mut body, &enabled_config());

        let compressed = body["messages"][0]["content"].as_str().unwrap();
        assert!(compressed.contains("test foo ... FAILED"));
        assert!(compressed.contains("test result: FAILED"));
        assert!(!compressed.contains("Compiling demo"));
    }

    #[test]
    fn compresses_javascript_test_output_with_filter_engine() {
        let js_test = "RUN  v2.1.1 /repo
PASS src/ok.test.ts
FAIL src/bad.test.ts > suite > fails
AssertionError: expected 1 to be 2
src/bad.test.ts:12:5
Test Files  1 failed | 1 passed (2)
Tests  1 failed | 3 passed (4)";
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": js_test
            }]
        });

        optimize(&mut body, &enabled_config());

        let compressed = body["messages"][0]["content"].as_str().unwrap();
        assert!(compressed.contains("FAIL src/bad.test.ts"));
        assert!(compressed.contains("AssertionError"));
        assert!(compressed.contains("Test Files"));
        assert!(!compressed.contains("PASS src/ok.test.ts"));
        assert!(!compressed.contains("RUN  v2.1.1"));
    }

    #[test]
    fn compresses_search_results_with_per_file_cap() {
        let results = (1..=40)
            .map(|i| format!("src/a.rs:{i}:match {i} {}", "x".repeat(30)))
            .chain(std::iter::once(format!(
                "src/b.rs:1:seven {}",
                "y".repeat(30)
            )))
            .collect::<Vec<_>>()
            .join("\n");
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": results
            }]
        });

        optimize(&mut body, &enabled_config());

        let compressed = body["messages"][0]["content"].as_str().unwrap();
        assert!(compressed.contains("src/a.rs:1:match 1"));
        assert!(compressed.contains("src/a.rs:5:match 5"));
        assert!(compressed.contains("src/b.rs:1:seven"));
        assert!(!compressed.contains("src/a.rs:6:match 6"));
        assert!(compressed.contains("omitted 35 search result"));
    }

    #[test]
    fn skips_json_string_tool_outputs() {
        let json_output =
            r#"{"records":[{"id":1,"value":"abcdefghijklmnopqrstuvwxyz0123456789"}]}"#;
        let mut body = json!({
            "input": [{
                "type": "function_call_output",
                "call_id": "call_1",
                "output": json_output
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["output"], json_output);
    }

    #[test]
    fn skips_json_array_string_tool_outputs() {
        let json_output = r#"[{"id":1,"value":"abcdefghijklmnopqrstuvwxyz0123456789"}]"#;
        let mut body = json!({
            "input": [{
                "type": "function_call_output",
                "call_id": "call_1",
                "output": json_output
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["output"], json_output);
    }

    #[test]
    fn leaves_computer_call_output_unchanged() {
        let long = long_plain_text();
        let mut body = json!({
            "input": [{
                "type": "computer_call_output",
                "call_id": "call_1",
                "output": {
                    "type": "input_image",
                    "image_url": long,
                    "file_id": long
                },
                "text": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["call_id"], "call_1");
        assert_eq!(body["input"][0]["output"]["image_url"], long);
        assert_eq!(body["input"][0]["output"]["file_id"], long);
        assert_eq!(body["input"][0]["text"], long);
    }

    #[test]
    fn leaves_reasoning_encrypted_content_unchanged() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({
            "input": [{
                "type": "reasoning",
                "id": "rs_1",
                "encrypted_content": long,
                "summary": [{"type": "text", "text": long}],
                "signature": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["encrypted_content"], long);
        assert_eq!(body["input"][0]["summary"][0]["text"], long);
        assert_eq!(body["input"][0]["signature"], long);
    }

    #[test]
    fn skips_object_tool_outputs_including_nested_typed_text_blocks() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({
            "messages": [{
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": "tool_1",
                    "content": {
                        "metadata": "abcdefghijklmnopqrstuvwxyz0123456789",
                        "rendered": {"type": "text", "text": long}
                    }
                }]
            }]
        });

        optimize(&mut body, &enabled_config());

        let content = &body["messages"][0]["content"][0]["content"];
        assert_eq!(content["metadata"], "abcdefghijklmnopqrstuvwxyz0123456789");
        assert_eq!(content["rendered"]["text"], long);
    }

    #[test]
    fn leaves_git_diff_tool_output_unchanged() {
        let diff = "diff --git a/a.rs b/a.rs
@@ -1 +1 @@
-old
+new";
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": diff
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["content"], diff);
    }

    #[test]
    fn replay_mixed_request_only_compresses_safe_tool_text() {
        let fixture = load_fixture("mixed-request-safety.json");
        let original = fixture["body"].clone();
        let mut body = original.clone();

        optimize(&mut body, &enabled_config());

        assert_fixture_unchanged_paths(&original, &body, &fixture);
        assert_fixture_shorter_paths(&original, &body, &fixture);
    }

    #[test]
    fn disabled_by_default() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({"messages": [{"role": "user", "content": long}]});
        let summary = optimize(&mut body, &OptimizerConfig::default());
        assert_eq!(body["messages"][0]["content"], long);
        assert_eq!(summary, TokenSaverSummary::default());
    }

    #[test]
    fn optimize_returns_summary_for_compressed_text() {
        let log_text = (1..=120)
            .map(|i| format!("INFO build log line {i} {}", "z".repeat(48)))
            .collect::<Vec<_>>()
            .join("\n");
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": log_text
            }]
        });

        let summary = optimize(&mut body, &enabled_config());

        assert!(summary.candidate_fields >= 1);
        assert!(summary.compressed_fields >= 1);
        assert!(summary.saved_chars() > 0);
        assert!(summary.original_chars > summary.output_chars);
    }

    #[test]
    fn optimize_summary_counts_json_like_skips() {
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": r#"{"records":[{"id":1,"value":"abcdefghijklmnopqrstuvwxyz0123456789"}]}"#
            }]
        });

        let summary = optimize(&mut body, &enabled_config());

        assert_eq!(summary.skipped_json_like, 1);
        assert_eq!(summary.compressed_fields, 0);
        assert_eq!(summary.saved_chars(), 0);
    }

    fn load_fixture(file_name: &str) -> Value {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("fixtures")
            .join("token-cost-savers")
            .join(file_name);
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read fixture {}: {err}", path.display()));
        serde_json::from_str(&raw)
            .unwrap_or_else(|err| panic!("parse fixture {}: {err}", path.display()))
    }

    fn assert_fixture_unchanged_paths(original: &Value, optimized: &Value, fixture: &Value) {
        for pointer in fixture["assertions"]["unchanged"]
            .as_array()
            .expect("fixture unchanged assertions")
        {
            let pointer = pointer.as_str().expect("unchanged pointer is string");
            assert_eq!(
                optimized.pointer(pointer),
                original.pointer(pointer),
                "fixture path should remain unchanged: {pointer}"
            );
        }
    }

    fn assert_fixture_shorter_paths(original: &Value, optimized: &Value, fixture: &Value) {
        for pointer in fixture["assertions"]["shorter"]
            .as_array()
            .expect("fixture shorter assertions")
        {
            let pointer = pointer.as_str().expect("shorter pointer is string");
            let before = original
                .pointer(pointer)
                .and_then(Value::as_str)
                .unwrap_or_else(|| {
                    panic!("fixture original shorter path must be string: {pointer}")
                });
            let after = optimized
                .pointer(pointer)
                .and_then(Value::as_str)
                .unwrap_or_else(|| {
                    panic!("fixture optimized shorter path must be string: {pointer}")
                });
            assert!(
                after.len() < before.len(),
                "fixture path should become shorter: {pointer}"
            );
            assert!(
                !after.trim().is_empty(),
                "fixture path should not become empty: {pointer}"
            );
        }
    }
}
