use std::collections::HashMap;

use serde_json::Value;

use crate::error::AppError;
use crate::provider::{UsageData, UsageProbe, UsageProbeType, UsageResult};

pub(crate) fn has_enabled_probes(probes: &[UsageProbe]) -> bool {
    probes.iter().any(|probe| probe.enabled)
}

pub(crate) fn validate_probe_list(probes: &[UsageProbe]) -> Result<(), AppError> {
    let mut enabled_usage_count = 0;

    for probe in probes {
        if probe.id.is_empty() {
            return Err(AppError::InvalidInput(
                "usage probe id 不能为空".to_string(),
            ));
        }
        if !probe
            .id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        {
            return Err(AppError::InvalidInput(format!(
                "usage probe id 仅允许 ASCII 字母数字、_、-: {}",
                probe.id
            )));
        }

        if probe.enabled && probe.probe_type == UsageProbeType::Usage {
            enabled_usage_count += 1;
            if enabled_usage_count > 1 {
                return Err(AppError::InvalidInput(
                    "最多只能启用一个 usage probe".to_string(),
                ));
            }
        }
    }

    Ok(())
}

#[derive(Debug, Default)]
pub(crate) struct ProbeAccumulator {
    usage_data: Option<Vec<UsageData>>,
    usage_error: Option<String>,
    rate: Option<f64>,
    rate_label: Option<String>,
    models: Option<Vec<String>>,
    probe_errors: HashMap<String, String>,
}

pub(crate) fn apply_probe_value(
    accumulator: &mut ProbeAccumulator,
    probe: &UsageProbe,
    value: Value,
) -> Result<(), AppError> {
    match probe.probe_type {
        UsageProbeType::Usage => apply_usage_value(accumulator, value),
        UsageProbeType::Rate => apply_rate_value(accumulator, value),
        UsageProbeType::Models => apply_models_value(accumulator, value),
        UsageProbeType::Account => apply_account_value(accumulator, probe, value),
    }
}

pub(crate) fn finalize_probe_result(accumulator: ProbeAccumulator) -> UsageResult {
    let probe_errors = if accumulator.probe_errors.is_empty() {
        None
    } else {
        Some(accumulator.probe_errors)
    };

    if let Some(error) = accumulator.usage_error {
        return UsageResult {
            success: false,
            data: accumulator.usage_data,
            error: Some(error),
            rate: accumulator.rate,
            rate_label: accumulator.rate_label,
            models: accumulator.models,
            probe_errors,
        };
    }

    let success = accumulator.usage_data.is_some();

    UsageResult {
        success,
        data: accumulator.usage_data,
        error: None,
        rate: accumulator.rate,
        rate_label: accumulator.rate_label,
        models: accumulator.models,
        probe_errors,
    }
}

fn apply_usage_value(accumulator: &mut ProbeAccumulator, value: Value) -> Result<(), AppError> {
    if value
        .get("success")
        .and_then(Value::as_bool)
        .is_some_and(|success| !success)
    {
        accumulator.usage_error = Some(
            value
                .get("error")
                .and_then(Value::as_str)
                .filter(|message| !message.trim().is_empty())
                .unwrap_or("用量异常")
                .to_string(),
        );
        return Ok(());
    }

    let usage_value = value.get("data").cloned().unwrap_or(value);
    let usage_data = if usage_value.is_array() {
        serde_json::from_value::<Vec<UsageData>>(usage_value)
    } else {
        serde_json::from_value::<UsageData>(usage_value).map(|usage| vec![usage])
    }
    .map_err(|e| AppError::InvalidInput(format!("usage probe 数据格式错误: {e}")))?;

    accumulator.usage_data = Some(usage_data);
    Ok(())
}

fn apply_rate_value(accumulator: &mut ProbeAccumulator, value: Value) -> Result<(), AppError> {
    let rate = value.get("rate").and_then(Value::as_f64).ok_or_else(|| {
        AppError::InvalidInput("rate probe 必须返回 number 类型的 rate".to_string())
    })?;

    let rate_label = match value.get("rateLabel") {
        Some(label) => {
            let label = label
                .as_str()
                .ok_or_else(|| AppError::InvalidInput("rateLabel 必须是非空字符串".to_string()))?;
            if label.trim().is_empty() {
                return Err(AppError::InvalidInput(
                    "rateLabel 必须是非空字符串".to_string(),
                ));
            }
            Some(label.to_string())
        }
        None => None,
    };

    accumulator.rate = Some(rate);
    accumulator.rate_label = rate_label;
    Ok(())
}

fn apply_models_value(accumulator: &mut ProbeAccumulator, value: Value) -> Result<(), AppError> {
    let models_value = value.get("models").ok_or_else(|| {
        AppError::InvalidInput("models probe 必须返回 string[] 类型的 models".to_string())
    })?;
    let models = models_value
        .as_array()
        .ok_or_else(|| {
            AppError::InvalidInput("models probe 必须返回 string[] 类型的 models".to_string())
        })?
        .iter()
        .map(|item| {
            item.as_str().map(str::to_string).ok_or_else(|| {
                AppError::InvalidInput("models probe 必须返回 string[] 类型的 models".to_string())
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    accumulator.models = Some(models);
    Ok(())
}

fn apply_account_value(
    accumulator: &mut ProbeAccumulator,
    probe: &UsageProbe,
    value: Value,
) -> Result<(), AppError> {
    match value.get("isValid") {
        Some(Value::Bool(false)) => {
            let message = value
                .get("invalidMessage")
                .and_then(Value::as_str)
                .filter(|message| !message.trim().is_empty())
                .unwrap_or("账号异常")
                .to_string();
            accumulator.probe_errors.insert(probe.id.clone(), message);
            Ok(())
        }
        Some(Value::Bool(true)) | None => Ok(()),
        Some(_) => Err(AppError::InvalidInput(
            "account probe 的 isValid 必须是 boolean".to_string(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        apply_probe_value, finalize_probe_result, has_enabled_probes, validate_probe_list,
        ProbeAccumulator,
    };
    use crate::provider::{UsageProbe, UsageProbeRequest, UsageProbeType};
    use serde_json::json;

    fn probe(id: &str, probe_type: UsageProbeType, enabled: bool) -> UsageProbe {
        UsageProbe {
            id: id.to_string(),
            probe_type,
            enabled,
            request: UsageProbeRequest {
                url: "https://example.test".to_string(),
                method: "GET".to_string(),
                headers: Default::default(),
                body: None,
            },
            extractor: "return value".to_string(),
            timeout: None,
        }
    }

    #[test]
    fn empty_and_disabled_probes_do_not_enable_multi_probe_mode() {
        assert!(!has_enabled_probes(&[]));
        assert!(!has_enabled_probes(&[probe(
            "usage-main",
            UsageProbeType::Usage,
            false,
        )]));
    }

    #[test]
    fn rejects_multiple_enabled_usage_probes() {
        let probes = vec![
            probe("usage-main", UsageProbeType::Usage, true),
            probe("usage-backup", UsageProbeType::Usage, true),
        ];

        assert!(validate_probe_list(&probes).is_err());
    }

    #[test]
    fn rejects_unsafe_probe_id() {
        let probes = vec![probe("usage/main", UsageProbeType::Usage, true)];

        assert!(validate_probe_list(&probes).is_err());
    }

    #[test]
    fn usage_failure_keeps_successful_rate_fields() {
        let usage_probe = probe("usage-main", UsageProbeType::Usage, true);
        let rate_probe = probe("rate-main", UsageProbeType::Rate, true);
        let mut accumulator = ProbeAccumulator::default();

        apply_probe_value(
            &mut accumulator,
            &usage_probe,
            json!({ "success": false, "error": "用量异常" }),
        )
        .expect("record usage failure");
        apply_probe_value(
            &mut accumulator,
            &rate_probe,
            json!({ "rate": 1.5, "rateLabel": "x1.5" }),
        )
        .expect("record rate");

        let result = finalize_probe_result(accumulator);

        assert!(!result.success);
        assert_eq!(result.error.as_deref(), Some("用量异常"));
        assert_eq!(result.rate, Some(1.5));
        assert_eq!(result.rate_label.as_deref(), Some("x1.5"));
    }

    #[test]
    fn non_core_probe_failure_keeps_successful_usage() {
        let usage_probe = probe("usage-main", UsageProbeType::Usage, true);
        let account_probe = probe("account-main", UsageProbeType::Account, true);
        let mut accumulator = ProbeAccumulator::default();

        apply_probe_value(
            &mut accumulator,
            &usage_probe,
            json!({ "planName": "Pro", "remaining": 42.0 }),
        )
        .expect("record usage");
        apply_probe_value(
            &mut accumulator,
            &account_probe,
            json!({ "isValid": false }),
        )
        .expect("record account issue");

        let result = finalize_probe_result(accumulator);

        assert!(result.success);
        assert_eq!(result.data.expect("usage data").len(), 1);
        assert_eq!(
            result
                .probe_errors
                .expect("probe errors")
                .get("account-main")
                .map(String::as_str),
            Some("账号异常")
        );
    }

    #[test]
    fn rejects_non_number_rate() {
        let rate_probe = probe("rate-main", UsageProbeType::Rate, true);
        let mut accumulator = ProbeAccumulator::default();

        let result = apply_probe_value(&mut accumulator, &rate_probe, json!({ "rate": "fast" }));

        assert!(result.is_err());
    }

    #[test]
    fn rejects_models_that_are_not_string_array() {
        let models_probe = probe("models-main", UsageProbeType::Models, true);
        let mut accumulator = ProbeAccumulator::default();

        let result = apply_probe_value(
            &mut accumulator,
            &models_probe,
            json!({ "models": ["claude-sonnet-4", 42] }),
        );

        assert!(result.is_err());
    }
}
