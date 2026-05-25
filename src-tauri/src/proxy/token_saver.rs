//! Token Saver request compression inspired by 9Router RTK.
//!
//! This module intentionally only rewrites large textual payloads. Protocol identity
//! fields (`id`, `call_id`, `tool_call_id`, `previous_response_id`), tool call
//! structure, reasoning blocks, signatures and `cache_control` are preserved.

use serde_json::Value;

use super::types::OptimizerConfig;

/// Apply request-side token saving in-place.
pub fn optimize(body: &mut Value, config: &OptimizerConfig) {
    if !config.enabled || !config.token_saver {
        return;
    }

    let min_chars = config.token_saver_min_chars.max(1);
    let keep_chars = config.token_saver_keep_chars.max(80).min(min_chars.saturating_sub(1));
    compress_value(body, min_chars, keep_chars);
}

fn compress_value(value: &mut Value, min_chars: usize, keep_chars: usize) {
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
            let compress_keys: &[&str] = match (block_type.as_str(), role.as_str()) {
                ("tool_result", _) => &["content"],
                ("function_call_output", _) => &["output"],
                ("output_text" | "text", _) => &["text"],
                ("", "tool") => &["content"],
                _ => &[],
            };

            for (key, child) in map.iter_mut() {
                if is_protected_field(key) || should_skip_block_field(block_type.as_str(), key) {
                    continue;
                }

                if compress_keys.contains(&key.as_str()) {
                    compress_text_like(child, min_chars, keep_chars);
                } else {
                    compress_value(child, min_chars, keep_chars);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                compress_value(item, min_chars, keep_chars);
            }
        }
        _ => {}
    }
}

fn compress_text_like(value: &mut Value, min_chars: usize, keep_chars: usize) {
    match value {
        Value::String(text) => {
            if should_compress_string(text, min_chars) {
                *text = summarize_text(text, keep_chars);
            }
        }
        Value::Array(items) => {
            for item in items {
                compress_value(item, min_chars, keep_chars);
            }
        }
        // Structured object outputs often encode machine-readable tool results.
        // Leave ordinary fields intact; only visit nested explicitly typed text blocks.
        Value::Object(_) => compress_typed_text_blocks(value, min_chars, keep_chars),
        _ => {}
    }
}

fn compress_typed_text_blocks(value: &mut Value, min_chars: usize, keep_chars: usize) {
    match value {
        Value::Object(map) => {
            if map.get("type").and_then(Value::as_str).is_some() {
                compress_value(value, min_chars, keep_chars);
            } else {
                for child in map.values_mut() {
                    compress_typed_text_blocks(child, min_chars, keep_chars);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                compress_typed_text_blocks(item, min_chars, keep_chars);
            }
        }
        _ => {}
    }
}

fn should_compress_string(text: &str, min_chars: usize) -> bool {
    if text.chars().count() < min_chars {
        return false;
    }

    // JSON-looking tool output is usually intended to stay machine-readable.
    let trimmed = text.trim_start();
    !(trimmed.starts_with('{') || trimmed.starts_with('['))
}

fn summarize_text(text: &str, keep_chars: usize) -> String {
    let char_count = text.chars().count();
    if char_count <= keep_chars {
        return text.to_string();
    }

    let head_chars = keep_chars / 2;
    let tail_chars = keep_chars.saturating_sub(head_chars);
    let head: String = text.chars().take(head_chars).collect();
    let tail: String = text
        .chars()
        .rev()
        .take(tail_chars)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    let omitted = char_count.saturating_sub(head_chars + tail_chars);

    format!(
        "{head}\n\n[CCS Token Saver: omitted {omitted} chars from a long tool/text payload]\n\n{tail}"
    )
}

fn is_protected_field(key: &str) -> bool {
    matches!(
        key,
        "id"
            | "call_id"
            | "tool_call_id"
            | "tool_use_id"
            | "previous_response_id"
            | "response_id"
            | "cache_control"
            | "signature"
            | "name"
            | "role"
            | "type"
            | "model"
    )
}

fn should_skip_block_field(block_type: &str, key: &str) -> bool {
    if matches!(block_type, "reasoning" | "thinking" | "redacted_thinking" | "tool_call" | "function_call" | "tool_use") {
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

    #[test]
    fn compresses_long_tool_result_but_keeps_protocol_fields() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
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
        let compressed = block["content"].as_str().unwrap();
        assert!(compressed.contains("CCS Token Saver"));
        assert!(compressed.starts_with("abcde"));
        assert!(compressed.ends_with("56789"));
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
    fn compresses_openai_tool_message_content() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({
            "messages": [{
                "role": "tool",
                "tool_call_id": "call_1",
                "content": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["messages"][0]["tool_call_id"], "call_1");
        assert!(body["messages"][0]["content"].as_str().unwrap().contains("CCS Token Saver"));
    }

    #[test]
    fn compresses_plain_function_call_output() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({
            "input": [{
                "type": "function_call_output",
                "call_id": "call_1",
                "output": long
            }]
        });

        optimize(&mut body, &enabled_config());

        assert_eq!(body["input"][0]["call_id"], "call_1");
        assert!(body["input"][0]["output"].as_str().unwrap().contains("CCS Token Saver"));
    }

    #[test]
    fn skips_json_string_tool_outputs() {
        let json_output = r#"{"records":[{"id":1,"value":"abcdefghijklmnopqrstuvwxyz0123456789"}]}"#;
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
    fn skips_object_tool_outputs_but_compresses_nested_typed_text_blocks() {
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
        assert!(content["rendered"]["text"].as_str().unwrap().contains("CCS Token Saver"));
    }

    #[test]
    fn disabled_by_default() {
        let long = "abcdefghijklmnopqrstuvwxyz0123456789";
        let mut body = json!({"messages": [{"role": "user", "content": long}]});
        optimize(&mut body, &OptimizerConfig::default());
        assert_eq!(body["messages"][0]["content"], long);
    }
}
