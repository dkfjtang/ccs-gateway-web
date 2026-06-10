use std::collections::HashMap;

use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use rquickjs::{Context, Function, Runtime};
use serde_json::Value;
use url::{Host, Url};

use crate::error::AppError;
use crate::provider::{UsageData, UsageProbe, UsageProbeRequest, UsageProbeType, UsageResult};

const DEFAULT_PROBE_TIMEOUT_SECS: u64 = 10;

#[derive(Clone, Copy)]
struct ProbeSecretContext<'a> {
    api_key: &'a str,
    access_token: Option<&'a str>,
}

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
    apply_probe_value_with_secret_context(
        accumulator,
        probe,
        value,
        ProbeSecretContext {
            api_key: "",
            access_token: None,
        },
    )
}

fn apply_probe_value_with_secret_context(
    accumulator: &mut ProbeAccumulator,
    probe: &UsageProbe,
    value: Value,
    secrets: ProbeSecretContext<'_>,
) -> Result<(), AppError> {
    match probe.probe_type {
        UsageProbeType::Usage => apply_usage_value(accumulator, value, secrets),
        UsageProbeType::Rate => apply_rate_value(accumulator, value),
        UsageProbeType::Models => apply_models_value(accumulator, value),
        UsageProbeType::Account => apply_account_value(accumulator, probe, value, secrets),
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

pub(crate) async fn execute_usage_probes(
    probes: &[UsageProbe],
    api_key: &str,
    base_url: &str,
    access_token: Option<&str>,
    user_id: Option<&str>,
) -> Result<UsageResult, AppError> {
    validate_probe_list(probes)?;

    let mut accumulator = ProbeAccumulator::default();
    let secrets = ProbeSecretContext {
        api_key,
        access_token,
    };
    for probe in probes.iter().filter(|probe| probe.enabled) {
        let result = execute_single_probe(probe, api_key, base_url, access_token, user_id).await;
        match result.and_then(|value| {
            apply_probe_value_with_secret_context(&mut accumulator, probe, value, secrets)
        }) {
            Ok(()) => {}
            Err(err) if probe.probe_type == UsageProbeType::Usage => {
                accumulator.usage_error =
                    Some(sanitize_probe_error_message(&err.to_string(), secrets));
            }
            Err(err) => {
                accumulator.probe_errors.insert(
                    probe.id.clone(),
                    sanitize_probe_error_message(&err.to_string(), secrets),
                );
            }
        }
    }

    Ok(finalize_probe_result(accumulator))
}

async fn execute_single_probe(
    probe: &UsageProbe,
    api_key: &str,
    base_url: &str,
    access_token: Option<&str>,
    user_id: Option<&str>,
) -> Result<Value, AppError> {
    let request = build_probe_request(&probe.request, api_key, base_url, access_token, user_id);
    validate_probe_request_url(&request.url, base_url)?;
    let response_data = send_probe_http_request(
        &request,
        probe.timeout.unwrap_or(DEFAULT_PROBE_TIMEOUT_SECS),
    )
    .await?;
    execute_probe_extractor(&probe.extractor, &response_data)
}

fn build_probe_request(
    request: &UsageProbeRequest,
    api_key: &str,
    base_url: &str,
    access_token: Option<&str>,
    user_id: Option<&str>,
) -> UsageProbeRequest {
    let replace = |value: &str| {
        replace_probe_vars(
            value,
            api_key,
            base_url,
            access_token.unwrap_or(""),
            user_id.unwrap_or(""),
        )
    };

    UsageProbeRequest {
        url: replace(&request.url),
        method: request.method.clone(),
        headers: request
            .headers
            .iter()
            .map(|(key, value)| (key.clone(), replace(value)))
            .collect(),
        body: request.body.as_ref().map(|body| replace(body)),
    }
}

fn replace_probe_vars(
    value: &str,
    api_key: &str,
    base_url: &str,
    access_token: &str,
    user_id: &str,
) -> String {
    value
        .replace("{{apiKey}}", api_key)
        .replace("{{baseUrl}}", base_url)
        .replace("{{accessToken}}", access_token)
        .replace("{{userId}}", user_id)
}

fn validate_probe_request_url(request_url: &str, _base_url: &str) -> Result<(), AppError> {
    let parsed_request = Url::parse(request_url).map_err(|e| {
        AppError::localized(
            "usage_probe.request_url_invalid",
            format!("无效的 probe 请求 URL: {e}"),
            format!("Invalid probe request URL: {e}"),
        )
    })?;

    let is_request_loopback = is_loopback_host(&parsed_request);
    if parsed_request.scheme() != "https" && !is_request_loopback {
        return Err(AppError::localized(
            "usage_probe.request_https_required",
            "probe 请求 URL 必须使用 HTTPS 协议（localhost 除外）",
            "Probe request URL must use HTTPS (localhost allowed)",
        ));
    }

    Ok(())
}

async fn send_probe_http_request(
    request: &UsageProbeRequest,
    timeout_secs: u64,
) -> Result<String, AppError> {
    let method: reqwest::Method = request.method.parse().map_err(|_| {
        AppError::localized(
            "usage_probe.invalid_http_method",
            format!("不支持的 probe HTTP 方法: {}", request.method),
            format!("Unsupported probe HTTP method: {}", request.method),
        )
    })?;
    let mut headers = HeaderMap::new();
    for (key, value) in &request.headers {
        let name: HeaderName = key
            .parse()
            .map_err(|_| AppError::InvalidInput(format!("probe 请求头名称无效: {key}")))?;
        let value = HeaderValue::from_str(value)
            .map_err(|_| AppError::InvalidInput(format!("probe 请求头值无效: {key}")))?;
        headers.insert(name, value);
    }

    let client = build_probe_http_client()?;
    let request_timeout = std::time::Duration::from_secs(timeout_secs.clamp(2, 30));
    let mut builder = client
        .request(method, &request.url)
        .headers(headers)
        .timeout(request_timeout);

    if let Some(body) = &request.body {
        builder = builder.body(body.clone());
    }

    let response = builder.send().await.map_err(|e| {
        AppError::localized(
            "usage_probe.request_failed",
            format!("probe 请求失败: {e}"),
            format!("Probe request failed: {e}"),
        )
    })?;
    let status = response.status();
    let text = response.text().await.map_err(|e| {
        AppError::localized(
            "usage_probe.read_response_failed",
            format!("读取 probe 响应失败: {e}"),
            format!("Failed to read probe response: {e}"),
        )
    })?;

    if !status.is_success() {
        let preview = truncate_for_error(&text, 200);
        return Err(AppError::localized(
            "usage_probe.http_error",
            format!("probe HTTP {status}: {preview}"),
            format!("Probe HTTP {status}: {preview}"),
        ));
    }

    Ok(text)
}

fn build_probe_http_client() -> Result<reqwest::Client, AppError> {
    let mut builder = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(std::time::Duration::from_secs(600))
        .connect_timeout(std::time::Duration::from_secs(30))
        .pool_max_idle_per_host(10)
        .tcp_keepalive(std::time::Duration::from_secs(60));

    if let Some(proxy_url) = crate::proxy::http_client::get_current_proxy_url() {
        let proxy = reqwest::Proxy::all(&proxy_url).map_err(|e| {
            AppError::localized(
                "usage_probe.proxy_config_invalid",
                format!("probe 代理配置无效: {e}"),
                format!("Invalid probe proxy configuration: {e}"),
            )
        })?;
        builder = builder.proxy(proxy);
    }

    builder.build().map_err(|e| {
        AppError::localized(
            "usage_probe.client_create_failed",
            format!("创建 probe HTTP 客户端失败: {e}"),
            format!("Failed to create probe HTTP client: {e}"),
        )
    })
}

fn execute_probe_extractor(extractor_code: &str, response_data: &str) -> Result<Value, AppError> {
    let runtime = Runtime::new().map_err(|e| {
        AppError::localized(
            "usage_probe.runtime_create_failed",
            format!("创建 JS 运行时失败: {e}"),
            format!("Failed to create JS runtime: {e}"),
        )
    })?;
    let context = Context::full(&runtime).map_err(|e| {
        AppError::localized(
            "usage_probe.context_create_failed",
            format!("创建 JS 上下文失败: {e}"),
            format!("Failed to create JS context: {e}"),
        )
    })?;

    context.with(|ctx| {
        let function_source = format!("(function(response) {{\n{extractor_code}\n}})");
        let extractor: Function = ctx.eval(function_source).map_err(|e| {
            AppError::localized(
                "usage_probe.extractor_parse_failed",
                format!("解析 probe extractor 失败: {e}"),
                format!("Failed to parse probe extractor: {e}"),
            )
        })?;
        let response_js: rquickjs::Value = ctx.json_parse(response_data).map_err(|e| {
            AppError::localized(
                "usage_probe.response_parse_failed",
                format!("解析 probe 响应 JSON 失败: {e}"),
                format!("Failed to parse probe response JSON: {e}"),
            )
        })?;
        let result_js: rquickjs::Value = extractor.call((response_js,)).map_err(|e| {
            AppError::localized(
                "usage_probe.extractor_exec_failed",
                format!("执行 probe extractor 失败: {e}"),
                format!("Failed to execute probe extractor: {e}"),
            )
        })?;
        let result_json: String = ctx
            .json_stringify(result_js)
            .map_err(|e| {
                AppError::localized(
                    "usage_probe.result_serialize_failed",
                    format!("序列化 probe 结果失败: {e}"),
                    format!("Failed to serialize probe result: {e}"),
                )
            })?
            .ok_or_else(|| {
                AppError::localized(
                    "usage_probe.serialize_none",
                    "probe 序列化返回 None",
                    "Probe serialization returned None",
                )
            })?
            .get()
            .map_err(|e| {
                AppError::localized(
                    "usage_probe.get_string_failed",
                    format!("获取 probe 结果字符串失败: {e}"),
                    format!("Failed to get probe result string: {e}"),
                )
            })?;

        serde_json::from_str(&result_json).map_err(|e| {
            AppError::localized(
                "usage_probe.json_parse_failed",
                format!("probe 结果 JSON 解析失败: {e}"),
                format!("Probe result JSON parse failed: {e}"),
            )
        })
    })
}

fn truncate_for_error(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        return sanitize_usage_error_message(text);
    }

    let mut cut = max_len;
    while !text.is_char_boundary(cut) {
        cut = cut.saturating_sub(1);
    }
    sanitize_usage_error_message(&format!("{}...", &text[..cut]))
}

fn is_loopback_host(url: &Url) -> bool {
    match url.host() {
        Some(Host::Domain(domain)) => domain.eq_ignore_ascii_case("localhost"),
        Some(Host::Ipv4(ip)) => ip.is_loopback(),
        Some(Host::Ipv6(ip)) => ip.is_loopback(),
        _ => false,
    }
}

fn sanitize_usage_error_message(message: &str) -> String {
    let message = message.trim();
    if message.is_empty() {
        return "用量异常".to_string();
    }

    let lower_message = message.to_ascii_lowercase();
    if [
        "authorization",
        "bearer",
        "api_key",
        "apikey",
        "api key",
        "api-key",
        "x-api-key",
        "access_token",
        "access token",
        "access-token",
    ]
    .iter()
    .any(|keyword| lower_message.contains(keyword))
    {
        return "探测异常".to_string();
    }

    message.to_string()
}

fn sanitize_probe_error_message(
    message: &str,
    secrets: ProbeSecretContext<'_>,
) -> String {
    let sanitized = sanitize_usage_error_message(message);
    if sanitized == "探测异常" {
        return sanitized;
    }

    let contains_secret = [Some(secrets.api_key), secrets.access_token]
        .into_iter()
        .flatten()
        .map(str::trim)
        .filter(|secret| secret.len() >= 6)
        .any(|secret| sanitized.contains(secret));

    if contains_secret {
        "探测异常".to_string()
    } else {
        sanitized
    }
}

fn apply_usage_value(
    accumulator: &mut ProbeAccumulator,
    value: Value,
    secrets: ProbeSecretContext<'_>,
) -> Result<(), AppError> {
    if value
        .get("success")
        .and_then(Value::as_bool)
        .is_some_and(|success| !success)
    {
        accumulator.usage_error = Some(sanitize_probe_error_message(
            value
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("用量异常"),
            secrets,
        ));
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
    secrets: ProbeSecretContext<'_>,
) -> Result<(), AppError> {
    match value.get("isValid") {
        Some(Value::Bool(false)) => {
            let message = sanitize_probe_error_message(
                value
                    .get("invalidMessage")
                    .and_then(Value::as_str)
                    .filter(|message| !message.trim().is_empty())
                    .unwrap_or("账号异常"),
                secrets,
            );
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
        apply_probe_value, execute_usage_probes, finalize_probe_result, has_enabled_probes,
        validate_probe_list, validate_probe_request_url, ProbeAccumulator,
    };
    use crate::provider::{UsageProbe, UsageProbeRequest, UsageProbeType};
    use axum::{
        extract::State,
        http::{header::LOCATION, HeaderMap, StatusCode},
        response::IntoResponse,
        routing::{get, post},
        Json, Router,
    };
    use serde_json::json;
    use std::sync::{Arc, Mutex};
    use tokio::net::TcpListener;

    #[derive(Clone, Default)]
    struct RequestLog(Arc<Mutex<Vec<String>>>);

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

    async fn test_server() -> (String, RequestLog) {
        async fn usage(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0.lock().expect("request log").push("usage".to_string());
            Json(json!({ "planName": "Pro", "remaining": 42.0, "unit": "credits" }))
        }

        async fn rate(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0.lock().expect("request log").push("rate".to_string());
            Json(json!({ "rate": 1.5, "rateLabel": "x1.5" }))
        }

        async fn rate_schema_error(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0
                .lock()
                .expect("request log")
                .push("rate-schema-error".to_string());
            Json(json!({ "rate": "fast" }))
        }

        async fn usage_failure(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0
                .lock()
                .expect("request log")
                .push("usage-failure".to_string());
            Json(json!({ "success": false, "error": "Bearer secret-token" }))
        }

        async fn usage_failure_with_raw_api_key(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0
                .lock()
                .expect("request log")
                .push("usage-failure-api-key".to_string());
            Json(json!({ "success": false, "error": "sk-live-secret-123" }))
        }

        async fn account_invalid_with_raw_token(State(log): State<RequestLog>) -> impl IntoResponse {
            log.0
                .lock()
                .expect("request log")
                .push("account-invalid-token".to_string());
            Json(json!({ "isValid": false, "invalidMessage": "acct-token-secret-456" }))
        }

        async fn echo_auth(
            State(log): State<RequestLog>,
            headers: HeaderMap,
            body: String,
        ) -> impl IntoResponse {
            log.0.lock().expect("request log").push(format!(
                "auth:{};body:{}",
                headers
                    .get("authorization")
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or(""),
                body
            ));
            Json(json!({ "planName": "Echo", "remaining": 7.0 }))
        }

        async fn redirect_302(
            State(log): State<RequestLog>,
            headers: HeaderMap,
            body: String,
        ) -> impl IntoResponse {
            log.0.lock().expect("request log").push(format!(
                "redirect-302 auth:{};body:{}",
                headers
                    .get("authorization")
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or(""),
                body
            ));
            (StatusCode::FOUND, [(LOCATION, "/redirect-target")], "")
        }

        async fn redirect_307(
            State(log): State<RequestLog>,
            headers: HeaderMap,
            body: String,
        ) -> impl IntoResponse {
            log.0.lock().expect("request log").push(format!(
                "redirect-307 auth:{};body:{}",
                headers
                    .get("authorization")
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or(""),
                body
            ));
            (
                StatusCode::TEMPORARY_REDIRECT,
                [(LOCATION, "/redirect-target")],
                "",
            )
        }

        async fn redirect_target(
            State(log): State<RequestLog>,
            headers: HeaderMap,
            body: String,
        ) -> impl IntoResponse {
            log.0.lock().expect("request log").push(format!(
                "redirect-target auth:{};body:{}",
                headers
                    .get("authorization")
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or(""),
                body
            ));
            Json(json!({ "rate": 9.9 }))
        }

        let log = RequestLog::default();
        let app = Router::new()
            .route("/usage", get(usage))
            .route("/rate", get(rate))
            .route("/rate-schema-error", get(rate_schema_error))
            .route("/usage-failure", get(usage_failure))
            .route("/usage-failure-api-key", get(usage_failure_with_raw_api_key))
            .route("/account-invalid-token", get(account_invalid_with_raw_token))
            .route("/echo-auth", post(echo_auth))
            .route("/redirect-302", post(redirect_302))
            .route("/redirect-307", post(redirect_307))
            .route("/redirect-target", post(redirect_target).get(redirect_target))
            .with_state(log.clone());
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let addr = listener.local_addr().expect("local addr");
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("serve test server");
        });

        (format!("http://{addr}"), log)
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
    fn usage_failure_sanitizes_sensitive_error_message() {
        let usage_probe = probe("usage-main", UsageProbeType::Usage, true);
        let mut accumulator = ProbeAccumulator::default();

        apply_probe_value(
            &mut accumulator,
            &usage_probe,
            json!({ "success": false, "error": "Bearer secret-token" }),
        )
        .expect("record usage failure");

        let result = finalize_probe_result(accumulator);
        let error = result.error.expect("usage error");

        assert_eq!(error, "探测异常");
        assert!(!error.contains("secret-token"));
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

    #[tokio::test]
    async fn execute_usage_probes_only_runs_enabled_probes() {
        let (base_url, log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage".to_string();
        usage.extractor = "return response".to_string();
        let mut disabled_rate = probe("rate-main", UsageProbeType::Rate, false);
        disabled_rate.request.url = "{{baseUrl}}/rate".to_string();
        disabled_rate.extractor = "return response".to_string();

        let result = execute_usage_probes(&[usage, disabled_rate], "", &base_url, None, None)
            .await
            .expect("execute probes");

        assert!(result.success);
        assert_eq!(result.data.expect("usage data").len(), 1);
        assert_eq!(*log.0.lock().expect("request log"), vec!["usage"]);
    }

    #[tokio::test]
    async fn rate_probe_schema_error_keeps_usage_success_and_records_probe_error() {
        let (base_url, _log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage".to_string();
        usage.extractor = "return response".to_string();
        let mut rate = probe("rate-main", UsageProbeType::Rate, true);
        rate.request.url = "{{baseUrl}}/rate-schema-error".to_string();
        rate.extractor = "return response".to_string();

        let result = execute_usage_probes(&[usage, rate], "", &base_url, None, None)
            .await
            .expect("execute probes");

        assert!(result.success);
        assert_eq!(result.rate, None);
        assert!(result
            .probe_errors
            .expect("probe errors")
            .get("rate-main")
            .expect("rate probe error")
            .contains("rate probe"));
    }

    #[tokio::test]
    async fn rate_probe_request_config_error_keeps_usage_success_and_records_probe_error() {
        let (base_url, _log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage".to_string();
        usage.extractor = "return response".to_string();
        let mut rate = probe("rate-main", UsageProbeType::Rate, true);
        rate.request.url = "http://example.com/rate".to_string();
        rate.extractor = "return response".to_string();

        let result = execute_usage_probes(&[usage, rate], "secret-token", &base_url, None, None)
            .await
            .expect("non-core probe config errors should not abort");

        assert!(result.success);
        assert_eq!(
            result.data.expect("usage data")[0].plan_name.as_deref(),
            Some("Pro")
        );
        let probe_errors = result.probe_errors.expect("probe errors");
        assert!(probe_errors.contains_key("rate-main"));
        assert!(!probe_errors["rate-main"].contains("secret-token"));
    }

    #[test]
    fn allows_https_probe_url_on_different_host_and_port() {
        validate_probe_request_url("https://metrics.example.net:8443/rate", "https://api.example.com")
            .expect("https probe URL may target a different metrics endpoint");
    }

    #[tokio::test]
    async fn usage_probe_failure_keeps_rate_and_marks_result_failed() {
        let (base_url, _log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage-failure".to_string();
        usage.extractor = "return response".to_string();
        let mut rate = probe("rate-main", UsageProbeType::Rate, true);
        rate.request.url = "{{baseUrl}}/rate".to_string();
        rate.extractor = "return response".to_string();

        let result = execute_usage_probes(&[usage, rate], "", &base_url, None, None)
            .await
            .expect("execute probes");

        assert!(!result.success);
        assert_eq!(result.error.as_deref(), Some("探测异常"));
        assert_eq!(result.rate, Some(1.5));
    }

    #[tokio::test]
    async fn usage_success_false_error_with_raw_api_key_is_sanitized() {
        let (base_url, _log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage-failure-api-key".to_string();
        usage.extractor = "return response".to_string();

        let result = execute_usage_probes(&[usage], "sk-live-secret-123", &base_url, None, None)
            .await
            .expect("execute probes");

        assert!(!result.success);
        assert_eq!(result.error.as_deref(), Some("探测异常"));
    }

    #[tokio::test]
    async fn account_invalid_message_with_raw_access_token_is_sanitized() {
        let (base_url, _log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage".to_string();
        usage.extractor = "return response".to_string();
        let mut account = probe("account-main", UsageProbeType::Account, true);
        account.request.url = "{{baseUrl}}/account-invalid-token".to_string();
        account.extractor = "return response".to_string();

        let result = execute_usage_probes(
            &[usage, account],
            "",
            &base_url,
            Some("acct-token-secret-456"),
            None,
        )
        .await
        .expect("execute probes");

        assert!(result.success);
        assert_eq!(
            result
                .probe_errors
                .expect("probe errors")
                .get("account-main")
                .map(String::as_str),
            Some("探测异常")
        );
    }

    #[tokio::test]
    async fn rejects_non_loopback_http_probe_url() {
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "http://example.com/usage".to_string();
        usage.extractor = "return response".to_string();

        let result =
            execute_usage_probes(&[usage], "secret-token", "https://api.example.com", None, None)
                .await
                .expect("usage probe config failures are represented as failed usage result");

        assert!(!result.success);
        let message = result.error.expect("usage error");
        assert!(message.contains("HTTPS") || message.contains("https"));
        assert!(!message.contains("secret-token"));
    }

    #[tokio::test]
    async fn replaces_probe_request_variables() {
        let (base_url, log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/echo-auth".to_string();
        usage.request.method = "POST".to_string();
        usage.request.headers.insert(
            "Authorization".to_string(),
            "Bearer {{accessToken}}".to_string(),
        );
        usage.request.body = Some("user={{userId}}&key={{apiKey}}".to_string());
        usage.extractor = "return response".to_string();

        let result = execute_usage_probes(
            &[usage],
            "api-key-1",
            &base_url,
            Some("token-1"),
            Some("user-1"),
        )
        .await
        .expect("execute probes");

        assert!(result.success);
        assert_eq!(
            *log.0.lock().expect("request log"),
            vec!["auth:Bearer token-1;body:user=user-1&key=api-key-1"]
        );
    }

    #[tokio::test]
    async fn non_core_probe_redirects_are_not_followed_or_leaked_to_target() {
        let (base_url, log) = test_server().await;
        let mut usage = probe("usage-main", UsageProbeType::Usage, true);
        usage.request.url = "{{baseUrl}}/usage".to_string();
        usage.extractor = "return response".to_string();

        let mut redirect_302 = probe("rate-302", UsageProbeType::Rate, true);
        redirect_302.request.url = "{{baseUrl}}/redirect-302".to_string();
        redirect_302.request.method = "POST".to_string();
        redirect_302
            .request
            .headers
            .insert("Authorization".to_string(), "Bearer {{accessToken}}".to_string());
        redirect_302.request.body = Some("key={{apiKey}}".to_string());
        redirect_302.extractor = "return response".to_string();

        let mut redirect_307 = probe("rate-307", UsageProbeType::Rate, true);
        redirect_307.request.url = "{{baseUrl}}/redirect-307".to_string();
        redirect_307.request.method = "POST".to_string();
        redirect_307
            .request
            .headers
            .insert("Authorization".to_string(), "Bearer {{accessToken}}".to_string());
        redirect_307.request.body = Some("key={{apiKey}}".to_string());
        redirect_307.extractor = "return response".to_string();

        let result = execute_usage_probes(
            &[usage, redirect_302, redirect_307],
            "api-key-redirect",
            &base_url,
            Some("token-redirect"),
            None,
        )
        .await
        .expect("execute probes");

        assert!(result.success);
        let probe_errors = result.probe_errors.expect("probe errors");
        assert!(probe_errors.contains_key("rate-302"));
        assert!(probe_errors.contains_key("rate-307"));

        let entries = log.0.lock().expect("request log").clone();
        assert_eq!(
            entries,
            vec![
                "usage",
                "redirect-302 auth:Bearer token-redirect;body:key=api-key-redirect",
                "redirect-307 auth:Bearer token-redirect;body:key=api-key-redirect",
            ]
        );
        assert!(!entries.iter().any(|entry| entry.contains("redirect-target")));
    }
}
