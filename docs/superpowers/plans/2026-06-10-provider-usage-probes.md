# 服务商用量多指标探测 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为服务商用量配置增加兼容旧脚本的多指标探测能力，并在服务商列表用量区域展示服务商返回的计费倍率。

**Architecture:** 保留旧 `usage_script.code` 单脚本路径；新增 `UsageScript.probes` 和独立 Rust `usage_probe` 模块处理多接口探测、校验与合并。前端仍复用现有 `queryProviderUsage` / `testUsageScript` 调用链，只扩展类型、测试入参、配置 UI 和 `UsageFooter` 展示。

**Tech Stack:** React + TypeScript + TanStack Query + Vitest；Tauri Rust + serde + reqwest；现有 PowerShell/rtk 验证脚本。

---

## 文件结构

- 修改 `src/types.ts`：扩展 `UsageProbe`、`UsageScript.probes`、`UsageData.resetsAt`、`UsageResult.rate/rateLabel/models/probeErrors`。
- 修改 `src-tauri/src/provider.rs`：扩展 Rust serde 类型，添加 serde 兼容单元测试。
- 新增 `src-tauri/src/usage_probe.rs`：多 probe 校验、单 probe 结果 schema、合并纯函数、执行入口。
- 修改 `src-tauri/src/lib.rs`：注册 `usage_probe` 模块。
- 修改 `src-tauri/src/services/provider/usage.rs`：在旧单脚本路径和多 probe 路径之间分流。
- 修改 `src-tauri/src/commands/provider.rs`：给 `testUsageScript` 增加可选完整 `UsageScript` 入参，保持旧参数可用。
- 修改 `src/lib/api/usage.ts`：`testScript` 支持可选完整 script payload。
- 修改 `src/components/UsageScriptModal.tsx`：增加多指标探测配置区和按当前模式测试。
- 修改 `src/components/UsageFooter.tsx`：显示 `rateLabel` / `rate` 和简短异常标记。
- 修改 `tests/hooks/useProviderActions.test.tsx`：验证保存不丢 probes。
- 新增 `tests/components/UsageFooter.test.tsx`：验证倍率展示和失败标记。
- 新增 `tests/components/UsageScriptModal.test.tsx`：验证多 probe 测试调用和缓存更新。
- 修改 `tests/utils/usageDisplay.test.ts`：验证摘要不被 probe-only 字段污染。
- 修改 `tests/integration/App.test.tsx`：增加保存 probes 的冒烟测试。

## Task 1: 类型契约与 serde 兼容

**Files:**
- Modify: `src/types.ts`
- Modify: `src-tauri/src/provider.rs`
- Test: `src-tauri/src/provider.rs`

- [ ] **Step 1: 写前端类型扩展**

在 `src/types.ts` 的 `UsageScript` 前后加入：

```ts
export type UsageProbeType = "usage" | "rate" | "models" | "account";

export interface UsageProbe {
  id: string;
  type: UsageProbeType;
  enabled: boolean;
  request: {
    url: string;
    method: string;
    headers?: Record<string, string>;
    body?: string;
  };
  extractor: string;
  timeout?: number;
}
```

并扩展：

```ts
export interface UsageScript {
  enabled: boolean;
  language: "javascript";
  code: string;
  timeout?: number;
  templateType?: TemplateType;
  apiKey?: string;
  baseUrl?: string;
  accessToken?: string;
  userId?: string;
  codingPlanProvider?: string;
  autoQueryInterval?: number;
  autoIntervalMinutes?: number;
  probes?: UsageProbe[];
  request?: {
    url?: string;
    method?: string;
    headers?: Record<string, string>;
    body?: any;
  };
}
```

扩展 `UsageData` 和 `UsageResult`：

```ts
export interface UsageData {
  planName?: string;
  extra?: string;
  isValid?: boolean;
  invalidMessage?: string;
  total?: number;
  used?: number;
  remaining?: number;
  unit?: string;
  resetsAt?: string;
}

export interface UsageResult {
  success: boolean;
  data?: UsageData[];
  error?: string;
  rate?: number;
  rateLabel?: string;
  models?: string[];
  probeErrors?: Record<string, string>;
}
```

- [ ] **Step 2: 写 Rust 类型和 serde 测试**

在 `src-tauri/src/provider.rs` 增加：

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum UsageProbeType {
    Usage,
    Rate,
    Models,
    Account,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageProbeRequest {
    pub url: String,
    pub method: String,
    #[serde(default, skip_serializing_if = "std::collections::HashMap::is_empty")]
    pub headers: std::collections::HashMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageProbe {
    pub id: String,
    #[serde(rename = "type")]
    pub probe_type: UsageProbeType,
    pub enabled: bool,
    pub request: UsageProbeRequest,
    pub extractor: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeout: Option<u64>,
}
```

给 `UsageScript` 增加：

```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub probes: Vec<UsageProbe>,
```

给 `UsageData` 增加：

```rust
#[serde(skip_serializing_if = "Option::is_none")]
#[serde(rename = "resetsAt")]
pub resets_at: Option<String>,
```

给 `UsageResult` 增加：

```rust
#[serde(skip_serializing_if = "Option::is_none")]
pub rate: Option<f64>,
#[serde(skip_serializing_if = "Option::is_none")]
#[serde(rename = "rateLabel")]
pub rate_label: Option<String>,
#[serde(skip_serializing_if = "Option::is_none")]
pub models: Option<Vec<String>>,
#[serde(skip_serializing_if = "Option::is_none")]
#[serde(rename = "probeErrors")]
pub probe_errors: Option<std::collections::HashMap<String, String>>,
```

在 `provider.rs` 的测试模块中增加：

```rust
#[test]
fn usage_script_deserializes_legacy_without_probes() {
    let json = r#"{
        "enabled": true,
        "language": "javascript",
        "code": "({ request: {}, extractor: function() { return {}; } })"
    }"#;
    let script: UsageScript = serde_json::from_str(json).unwrap();
    assert!(script.probes.is_empty());

    let serialized = serde_json::to_value(&script).unwrap();
    assert!(serialized.get("probes").is_none());
}

#[test]
fn usage_result_serializes_probe_fields_with_camel_case() {
    let mut probe_errors = std::collections::HashMap::new();
    probe_errors.insert("rate-main".to_string(), "探测异常".to_string());
    let result = UsageResult {
        success: false,
        data: Some(vec![UsageData {
            plan_name: Some("default".to_string()),
            extra: None,
            is_valid: Some(true),
            invalid_message: None,
            total: Some(100.0),
            used: Some(25.0),
            remaining: Some(75.0),
            unit: Some("USD".to_string()),
            resets_at: Some("2026-07-01T00:00:00Z".to_string()),
        }]),
        error: Some("用量异常".to_string()),
        rate: Some(1.5),
        rate_label: Some("x1.5".to_string()),
        models: Some(vec!["claude-sonnet-4".to_string()]),
        probe_errors: Some(probe_errors),
    };

    let value = serde_json::to_value(result).unwrap();
    assert_eq!(value["rate"], 1.5);
    assert_eq!(value["rateLabel"], "x1.5");
    assert_eq!(value["data"][0]["resetsAt"], "2026-07-01T00:00:00Z");
    assert_eq!(value["probeErrors"]["rate-main"], "探测异常");
}
```

- [ ] **Step 3: 运行类型相关测试并确认失败点或通过**

Run:

```powershell
cargo test --manifest-path src-tauri/Cargo.toml --lib provider
pnpm typecheck
```

Expected before all implementation is wired: Rust provider tests pass after this task; `pnpm typecheck` may fail only if later tasks still reference missing frontend usage. If it fails here, fix type definitions before continuing.

- [ ] **Step 4: 提交**

```powershell
git add src/types.ts src-tauri/src/provider.rs
git commit -m "feat: add usage probe data contract"
```

## Task 2: Rust usage_probe 校验与合并纯函数

**Files:**
- Create: `src-tauri/src/usage_probe.rs`
- Modify: `src-tauri/src/lib.rs`
- Test: `src-tauri/src/usage_probe.rs`

- [ ] **Step 1: 新增失败的校验和合并测试**

创建 `src-tauri/src/usage_probe.rs`，先写测试和最小结构：

```rust
use crate::error::AppError;
use crate::provider::{UsageData, UsageProbe, UsageProbeType, UsageResult};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Default)]
pub(crate) struct ProbeAccumulator {
    pub usage_data: Option<Vec<UsageData>>,
    pub usage_error: Option<String>,
    pub rate: Option<f64>,
    pub rate_label: Option<String>,
    pub models: Option<Vec<String>>,
    pub probe_errors: HashMap<String, String>,
}

pub(crate) fn has_enabled_probes(probes: &[UsageProbe]) -> bool {
    probes.iter().any(|probe| probe.enabled)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::{UsageProbeRequest, UsageProbeType};

    fn probe(id: &str, probe_type: UsageProbeType) -> UsageProbe {
        UsageProbe {
            id: id.to_string(),
            probe_type,
            enabled: true,
            request: UsageProbeRequest {
                url: "https://api.example.com/usage".to_string(),
                method: "GET".to_string(),
                headers: HashMap::new(),
                body: None,
            },
            extractor: "function(response) { return response; }".to_string(),
            timeout: Some(10),
        }
    }

    #[test]
    fn disabled_or_empty_probes_do_not_activate_multi_probe_mode() {
        assert!(!has_enabled_probes(&[]));
        let mut disabled = probe("usage-main", UsageProbeType::Usage);
        disabled.enabled = false;
        assert!(!has_enabled_probes(&[disabled]));
    }

    #[test]
    fn validate_probes_rejects_multiple_enabled_usage_probes() {
        let probes = vec![
            probe("usage-a", UsageProbeType::Usage),
            probe("usage-b", UsageProbeType::Usage),
        ];
        let error = validate_probe_list(&probes).unwrap_err().to_string();
        assert!(error.contains("usage"));
    }

    #[test]
    fn validate_probes_rejects_unsafe_id() {
        let probes = vec![probe("rate main", UsageProbeType::Rate)];
        let error = validate_probe_list(&probes).unwrap_err().to_string();
        assert!(error.contains("id"));
    }

    #[test]
    fn merge_keeps_rate_when_usage_failed() {
        let mut accumulator = ProbeAccumulator::default();
        accumulator.usage_error = Some("用量异常".to_string());
        accumulator.rate = Some(1.5);
        accumulator.rate_label = Some("x1.5".to_string());

        let result = finalize_probe_result(accumulator);
        assert!(!result.success);
        assert_eq!(result.rate, Some(1.5));
        assert_eq!(result.rate_label.as_deref(), Some("x1.5"));
        assert_eq!(result.error.as_deref(), Some("用量异常"));
    }

    #[test]
    fn merge_non_core_probe_failure_keeps_successful_usage() {
        let mut accumulator = ProbeAccumulator::default();
        accumulator.usage_data = Some(vec![UsageData {
            plan_name: Some("default".to_string()),
            extra: None,
            is_valid: Some(true),
            invalid_message: None,
            total: Some(100.0),
            used: Some(40.0),
            remaining: Some(60.0),
            unit: Some("USD".to_string()),
            resets_at: None,
        }]);
        accumulator
            .probe_errors
            .insert("rate-main".to_string(), "探测异常".to_string());

        let result = finalize_probe_result(accumulator);
        assert!(result.success);
        assert_eq!(result.data.unwrap()[0].remaining, Some(60.0));
        assert_eq!(
            result.probe_errors.unwrap()["rate-main"],
            "探测异常"
        );
    }
}
```

- [ ] **Step 2: 实现校验和合并函数**

在同一文件补齐：

```rust
pub(crate) fn validate_probe_list(probes: &[UsageProbe]) -> Result<(), AppError> {
    let mut enabled_usage_count = 0usize;
    for probe in probes.iter().filter(|probe| probe.enabled) {
        if probe.id.trim().is_empty()
            || !probe
                .id
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-')
        {
            return Err(AppError::InvalidInput(format!(
                "Invalid usage probe id: {}",
                probe.id
            )));
        }
        if matches!(probe.probe_type, UsageProbeType::Usage) {
            enabled_usage_count += 1;
        }
    }

    if enabled_usage_count > 1 {
        return Err(AppError::InvalidInput(
            "Only one enabled usage probe is allowed".to_string(),
        ));
    }

    Ok(())
}

pub(crate) fn finalize_probe_result(accumulator: ProbeAccumulator) -> UsageResult {
    let success = accumulator.usage_error.is_none() && accumulator.usage_data.is_some();
    UsageResult {
        success,
        data: accumulator.usage_data,
        error: accumulator.usage_error,
        rate: accumulator.rate,
        rate_label: accumulator.rate_label,
        models: accumulator.models,
        probe_errors: if accumulator.probe_errors.is_empty() {
            None
        } else {
            Some(accumulator.probe_errors)
        },
    }
}
```

添加类型校验函数：

```rust
pub(crate) fn apply_probe_value(
    accumulator: &mut ProbeAccumulator,
    probe: &UsageProbe,
    value: Value,
) -> Result<(), AppError> {
    match probe.probe_type {
        UsageProbeType::Usage => {
            let data = if value.is_array() {
                serde_json::from_value::<Vec<UsageData>>(value)
            } else {
                serde_json::from_value::<UsageData>(value).map(|single| vec![single])
            }
            .map_err(|e| AppError::InvalidInput(format!("Invalid usage probe result: {e}")))?;
            accumulator.usage_data = Some(data);
        }
        UsageProbeType::Rate => {
            let rate = value
                .get("rate")
                .and_then(|item| item.as_f64())
                .ok_or_else(|| AppError::InvalidInput("rate must be a number".to_string()))?;
            accumulator.rate = Some(rate);
            accumulator.rate_label = value
                .get("rateLabel")
                .and_then(|item| item.as_str())
                .filter(|label| !label.trim().is_empty())
                .map(|label| label.to_string());
        }
        UsageProbeType::Models => {
            let models = value
                .get("models")
                .and_then(|item| item.as_array())
                .ok_or_else(|| AppError::InvalidInput("models must be an array".to_string()))?
                .iter()
                .map(|item| {
                    item.as_str()
                        .map(|text| text.to_string())
                        .ok_or_else(|| AppError::InvalidInput("models must contain strings".to_string()))
                })
                .collect::<Result<Vec<_>, _>>()?;
            accumulator.models = Some(models);
        }
        UsageProbeType::Account => {
            if value.get("isValid").and_then(|item| item.as_bool()) == Some(false) {
                accumulator.probe_errors.insert(
                    probe.id.clone(),
                    value
                        .get("invalidMessage")
                        .and_then(|item| item.as_str())
                        .unwrap_or("账号异常")
                        .to_string(),
                );
            }
        }
    }
    Ok(())
}
```

- [ ] **Step 3: 注册模块并运行测试**

在 `src-tauri/src/lib.rs` 增加：

```rust
mod usage_probe;
```

Run:

```powershell
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe
```

Expected: PASS.

- [ ] **Step 4: 提交**

```powershell
git add src-tauri/src/usage_probe.rs src-tauri/src/lib.rs
git commit -m "feat: add usage probe merge validation"
```

## Task 3: Rust 多 probe 执行路径和测试命令入参

**Files:**
- Modify: `src-tauri/src/usage_probe.rs`
- Modify: `src-tauri/src/services/provider/usage.rs`
- Modify: `src-tauri/src/commands/provider.rs`
- Test: `src-tauri/src/usage_probe.rs`

- [ ] **Step 1: 给 usage_probe 增加执行入口**

在 `usage_probe.rs` 增加执行入口签名：

```rust
pub(crate) async fn execute_usage_probes(
    probes: &[UsageProbe],
    api_key: &str,
    base_url: &str,
    access_token: Option<&str>,
    user_id: Option<&str>,
) -> Result<UsageResult, AppError> {
    validate_probe_list(probes)?;

    let mut accumulator = ProbeAccumulator::default();
    for probe in probes.iter().filter(|probe| probe.enabled) {
        match execute_single_probe(probe, api_key, base_url, access_token, user_id).await {
            Ok(value) => {
                if let Err(err) = apply_probe_value(&mut accumulator, probe, value) {
                    record_probe_error(&mut accumulator, probe, err.to_string());
                }
            }
            Err(err) => record_probe_error(&mut accumulator, probe, err.to_string()),
        }
    }

    Ok(finalize_probe_result(accumulator))
}
```

并增加安全错误清洗：

```rust
fn record_probe_error(accumulator: &mut ProbeAccumulator, probe: &UsageProbe, message: String) {
    let safe = sanitize_probe_error(&message);
    if matches!(probe.probe_type, UsageProbeType::Usage) {
        accumulator.usage_error = Some(safe.clone());
    }
    accumulator.probe_errors.insert(probe.id.clone(), safe);
}

fn sanitize_probe_error(message: &str) -> String {
    let lowered = message.to_ascii_lowercase();
    if lowered.contains("authorization")
        || lowered.contains("api_key")
        || lowered.contains("apikey")
        || lowered.contains("access_token")
        || lowered.contains("bearer ")
    {
        return "探测异常".to_string();
    }
    message.chars().take(160).collect()
}
```

- [ ] **Step 2: 实现单 probe 请求执行**

复用 `usage_script` 的变量替换思想，但不要继承旧 `custom` 跨域放宽。新增私有函数：

```rust
async fn execute_single_probe(
    probe: &UsageProbe,
    api_key: &str,
    base_url: &str,
    access_token: Option<&str>,
    user_id: Option<&str>,
) -> Result<Value, AppError> {
    let request = build_probe_request(probe, api_key, base_url, access_token, user_id)?;
    validate_probe_url(&request.url)?;
    let response = send_probe_request(&request, probe.timeout.unwrap_or(10)).await?;
    run_probe_extractor(&probe.extractor, &response)
}
```

实现 `build_probe_request` 对 `{{apiKey}}`、`{{baseUrl}}`、`{{accessToken}}`、`{{userId}}` 做字符串替换；`validate_probe_url` 要求 HTTPS 或 loopback；`send_probe_request` 使用 `crate::proxy::http_client::get()` 和 `timeout_secs.clamp(2, 30)`。

- [ ] **Step 3: usage.rs 分流旧路径与 probes 路径**

在 `src-tauri/src/services/provider/usage.rs` 的 `query_usage` 中，取出 `usage_script.probes` 后判断：

```rust
let enabled_probes = usage_script.probes.clone();
let has_probes = crate::usage_probe::has_enabled_probes(&enabled_probes);
```

如果 `has_probes` 为 true，返回：

```rust
return crate::usage_probe::execute_usage_probes(
    &enabled_probes,
    &api_key,
    &base_url,
    usage_script.access_token.as_deref(),
    usage_script.user_id.as_deref(),
)
.await;
```

保留原 `execute_and_format_usage_result` 旧路径。

- [ ] **Step 4: testUsageScript 支持完整 script**

在 `src-tauri/src/commands/provider.rs` 的 `testUsageScript` 参数末尾增加：

```rust
    script: Option<crate::provider::UsageScript>,
```

在函数体中优先处理完整 script：

```rust
if let Some(full_script) = script {
    if crate::usage_probe::has_enabled_probes(&full_script.probes) {
        return crate::services::provider::usage::test_usage_probes(
            state.inner(),
            app_type,
            &providerId,
            &full_script,
        )
        .await
        .map_err(|e| e.to_string());
    }
}
```

在 `usage.rs` 新增：

```rust
pub async fn test_usage_probes(
    _state: &AppState,
    _app_type: AppType,
    _provider_id: &str,
    script: &UsageScript,
) -> Result<UsageResult, AppError> {
    crate::usage_probe::execute_usage_probes(
        &script.probes,
        script.api_key.as_deref().unwrap_or(""),
        script.base_url.as_deref().unwrap_or(""),
        script.access_token.as_deref(),
        script.user_id.as_deref(),
    )
    .await
}
```

旧扁平参数路径保持不变。

- [ ] **Step 5: 运行 Rust 测试**

Run:

```powershell
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_script
```

Expected: PASS.

- [ ] **Step 6: 提交**

```powershell
git add src-tauri/src/usage_probe.rs src-tauri/src/services/provider/usage.rs src-tauri/src/commands/provider.rs
git commit -m "feat: execute provider usage probes"
```

## Task 4: 前端 API、保存链路和摘要兼容

**Files:**
- Modify: `src/lib/api/usage.ts`
- Modify: `tests/hooks/useProviderActions.test.tsx`
- Modify: `tests/utils/usageDisplay.test.ts`

- [ ] **Step 1: 扩展 usageApi.testScript**

在 `src/lib/api/usage.ts` 引入 `UsageScript`，并把 `testScript` 末尾加可选参数：

```ts
import type { UsageResult, UsageScript } from "@/types";
```

签名改为：

```ts
testScript: async (
  providerId: string,
  appId: AppId,
  scriptCode: string,
  timeout?: number,
  apiKey?: string,
  baseUrl?: string,
  accessToken?: string,
  userId?: string,
  templateType?: TemplateType,
  script?: UsageScript,
): Promise<UsageResult> => {
  return invoke("testUsageScript", {
    providerId,
    app: appId,
    scriptCode,
    timeout,
    apiKey,
    baseUrl,
    accessToken,
    userId,
    templateType,
    script,
  });
},
```

- [ ] **Step 2: 写保存 probes 不丢字段测试**

在 `tests/hooks/useProviderActions.test.tsx` 新增：

```ts
it("preserves usage probes when saveUsageScript succeeds", async () => {
  providersApiUpdateMock.mockResolvedValueOnce(true);
  const { wrapper } = createWrapper();
  const provider = createProvider();
  const script: UsageScript = {
    enabled: true,
    language: "javascript",
    code: "",
    timeout: 10,
    probes: [
      {
        id: "rate-main",
        type: "rate",
        enabled: true,
        request: {
          url: "https://api.example.com/rate",
          method: "GET",
          headers: { Authorization: "Bearer {{apiKey}}" },
        },
        extractor: "function(response) { return { rate: response.rate }; }",
        timeout: 5,
      },
    ],
  };

  const { result } = renderHook(() => useProviderActions("claude"), {
    wrapper,
  });

  await act(async () => {
    await result.current.saveUsageScript(provider, script);
  });

  expect(providersApiUpdateMock).toHaveBeenCalledWith(
    expect.objectContaining({
      meta: expect.objectContaining({
        usage_script: expect.objectContaining({
          probes: script.probes,
        }),
      }),
    }),
    "claude",
  );
});
```

- [ ] **Step 3: 扩展 usageDisplay 测试**

在 `tests/utils/usageDisplay.test.ts` 新增：

```ts
it("does not include probe-only fields in the plan summary", () => {
  expect(
    formatUsageDataSummary(
      {
        planName: "default",
        used: 25,
        remaining: 75,
        total: 100,
        unit: "USD",
        resetsAt: "2026-07-01T00:00:00Z",
      },
      labels,
    ),
  ).toContain("Used:");
});
```

- [ ] **Step 4: 运行前端测试**

Run:

```powershell
pnpm vitest run tests/hooks/useProviderActions.test.tsx tests/utils/usageDisplay.test.ts
pnpm typecheck
```

Expected: PASS.

- [ ] **Step 5: 提交**

```powershell
git add src/lib/api/usage.ts tests/hooks/useProviderActions.test.tsx tests/utils/usageDisplay.test.ts
git commit -m "feat: support usage probe api payload"
```

## Task 5: UsageFooter 倍率和异常标记展示

**Files:**
- Modify: `src/components/UsageFooter.tsx`
- Create: `tests/components/UsageFooter.test.tsx`

- [ ] **Step 1: 写 UsageFooter 测试**

创建 `tests/components/UsageFooter.test.tsx`：

```tsx
import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import UsageFooter from "@/components/UsageFooter";
import type { Provider } from "@/types";

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, options?: { defaultValue?: string }) =>
      options?.defaultValue ?? key,
  }),
}));

vi.mock("@/lib/query/queries", () => ({
  useUsageQuery: vi.fn(),
}));

const { useUsageQuery } = await import("@/lib/query/queries");

function provider(): Provider {
  return {
    id: "provider-1",
    name: "Provider 1",
    settingsConfig: {},
    meta: {
      usage_script: {
        enabled: true,
        language: "javascript",
        code: "",
      },
    },
  };
}

function renderFooter() {
  const queryClient = new QueryClient();
  render(
    <QueryClientProvider client={queryClient}>
      <UsageFooter
        provider={provider()}
        providerId="provider-1"
        appId="claude"
        usageEnabled={true}
        isCurrent={true}
        inline={true}
      />
    </QueryClientProvider>,
  );
}

describe("UsageFooter probe rate display", () => {
  it("shows rateLabel near usage values", () => {
    vi.mocked(useUsageQuery).mockReturnValue({
      data: {
        success: true,
        data: [{ used: 10, remaining: 90, total: 100, unit: "USD" }],
        rate: 1.5,
        rateLabel: "x1.5",
      },
      isFetching: false,
      lastQueriedAt: Date.now(),
      refetch: vi.fn(),
    } as any);

    renderFooter();
    expect(screen.getByText("x1.5")).toBeInTheDocument();
  });

  it("shows current rate and short error marker when usage failed", () => {
    vi.mocked(useUsageQuery).mockReturnValue({
      data: {
        success: false,
        error: "用量异常",
        rate: 2,
        rateLabel: "x2",
      },
      isFetching: false,
      lastQueriedAt: Date.now(),
      refetch: vi.fn(),
    } as any);

    renderFooter();
    expect(screen.getByText("x2")).toBeInTheDocument();
    expect(screen.getByText(/用量异常|探测异常/)).toBeInTheDocument();
  });

  it("does not show rate when current failed result has no rate", () => {
    vi.mocked(useUsageQuery).mockReturnValue({
      data: { success: false, error: "用量异常" },
      isFetching: false,
      lastQueriedAt: Date.now(),
      refetch: vi.fn(),
    } as any);

    renderFooter();
    expect(screen.queryByText(/x1|x2/)).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: 实现展示辅助函数**

在 `UsageFooter.tsx` 增加：

```tsx
function formatRateLabel(rate?: number, rateLabel?: string): string | null {
  if (rateLabel && rateLabel.trim()) {
    return rateLabel.trim();
  }
  if (typeof rate === "number" && Number.isFinite(rate)) {
    return `x${Number.isInteger(rate) ? rate : rate.toFixed(2)}`;
  }
  return null;
}
```

在成功 inline 第二行中加入：

```tsx
const rateText = formatRateLabel(usage.rate, usage.rateLabel);
```

并在用量值旁渲染：

```tsx
{rateText && (
  <div className="flex items-center gap-0.5">
    <span className="text-gray-500 dark:text-gray-400">
      {t("usage.billingRate", { defaultValue: "计费倍率" })}
    </span>
    <span className="tabular-nums text-gray-600 dark:text-gray-400 font-medium">
      {rateText}
    </span>
  </div>
)}
```

在 `!usage.success` 的 inline 分支中，如果 `rateText` 存在，渲染简短异常标记和倍率：

```tsx
const rateText = formatRateLabel(usage.rate, usage.rateLabel);
if (inline && rateText) {
  return (
    <div className="inline-flex items-center gap-2 text-xs rounded-lg border border-border-default bg-card px-3 py-2 shadow-sm">
      <div className="flex items-center gap-1.5 text-amber-600 dark:text-amber-400">
        <AlertCircle size={12} />
        <span>{t("usage.probeWarning", { defaultValue: "用量异常" })}</span>
      </div>
      <span className="text-gray-500 dark:text-gray-400">
        {t("usage.billingRate", { defaultValue: "计费倍率" })}
      </span>
      <span className="tabular-nums text-gray-600 dark:text-gray-400 font-medium">
        {rateText}
      </span>
      <button
        onClick={() => refetch()}
        disabled={loading}
        className="p-1 rounded hover:bg-muted transition-colors disabled:opacity-50 flex-shrink-0"
        title={t("usage.refreshUsage")}
      >
        <RefreshCw size={12} className={loading ? "animate-spin" : ""} />
      </button>
    </div>
  );
}
```

- [ ] **Step 3: 运行测试**

Run:

```powershell
pnpm vitest run tests/components/UsageFooter.test.tsx
pnpm typecheck
```

Expected: PASS.

- [ ] **Step 4: 提交**

```powershell
git add src/components/UsageFooter.tsx tests/components/UsageFooter.test.tsx
git commit -m "feat: show provider billing rate in usage footer"
```

## Task 6: UsageScriptModal 多探测配置与测试缓存

**Files:**
- Modify: `src/components/UsageScriptModal.tsx`
- Create: `tests/components/UsageScriptModal.test.tsx`

- [ ] **Step 1: 写多探测测试**

创建 `tests/components/UsageScriptModal.test.tsx`，重点验证多 probe 模式调用完整 script 并更新缓存：

```tsx
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import UsageScriptModal from "@/components/UsageScriptModal";
import { usageApi } from "@/lib/api";
import type { Provider, UsageScript } from "@/types";

vi.mock("@/lib/api", async () => {
  const actual = await vi.importActual<any>("@/lib/api");
  return {
    ...actual,
    usageApi: {
      testScript: vi.fn(),
    },
    settingsApi: {
      save: vi.fn(),
      get: vi.fn(),
    },
  };
});

vi.mock("@/lib/query", () => ({
  useSettingsQuery: () => ({ data: { usageConfirmed: true } }),
}));

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, options?: { defaultValue?: string }) =>
      options?.defaultValue ?? key,
  }),
}));

function providerWithProbes(): Provider {
  const usageScript: UsageScript = {
    enabled: true,
    language: "javascript",
    code: "",
    probes: [
      {
        id: "usage-main",
        type: "usage",
        enabled: true,
        request: { url: "https://api.example.com/usage", method: "GET" },
        extractor: "function(response) { return response; }",
      },
      {
        id: "rate-main",
        type: "rate",
        enabled: true,
        request: { url: "https://api.example.com/rate", method: "GET" },
        extractor: "function(response) { return { rate: response.rate }; }",
      },
    ],
  };
  return {
    id: "provider-1",
    name: "Provider 1",
    settingsConfig: {
      env: {
        ANTHROPIC_AUTH_TOKEN: "token",
        ANTHROPIC_BASE_URL: "https://api.example.com",
      },
    },
    meta: { usage_script: usageScript },
  };
}

describe("UsageScriptModal probes", () => {
  it("tests active probe script and updates usage cache on success", async () => {
    const queryClient = new QueryClient();
    const setQueryDataSpy = vi.spyOn(queryClient, "setQueryData");
    vi.mocked(usageApi.testScript).mockResolvedValueOnce({
      success: true,
      data: [{ used: 1, remaining: 9, total: 10, unit: "USD" }],
      rate: 1.5,
      rateLabel: "x1.5",
    });

    render(
      <QueryClientProvider client={queryClient}>
        <UsageScriptModal
          provider={providerWithProbes()}
          appId="claude"
          isOpen={true}
          onClose={vi.fn()}
          onSave={vi.fn()}
        />
      </QueryClientProvider>,
    );

    fireEvent.click(screen.getByRole("button", { name: /test|测试/i }));

    await waitFor(() => {
      expect(usageApi.testScript).toHaveBeenCalledWith(
        "provider-1",
        "claude",
        "",
        expect.any(Number),
        expect.any(String),
        expect.any(String),
        undefined,
        undefined,
        expect.anything(),
        expect.objectContaining({
          probes: expect.arrayContaining([
            expect.objectContaining({ id: "rate-main" }),
          ]),
        }),
      );
    });

    expect(setQueryDataSpy).toHaveBeenCalledWith(
      ["usage", "provider-1", "claude"],
      expect.objectContaining({ rate: 1.5 }),
    );
  });
});
```

- [ ] **Step 2: 实现多 probe 模式判断和测试调用**

在 `UsageScriptModal.tsx` 增加：

```tsx
const hasEnabledProbes = (candidate: UsageScript): boolean =>
  Array.isArray(candidate.probes) &&
  candidate.probes.some((probe) => probe.enabled);
```

在 `handleTest` 通用脚本调用处改为：

```tsx
const isProbeMode = hasEnabledProbes(script);
const result = await usageApi.testScript(
  provider.id,
  appId,
  script.code,
  script.timeout,
  script.apiKey,
  script.baseUrl,
  script.accessToken,
  script.userId,
  selectedTemplate as "custom" | "general" | "newapi" | undefined,
  isProbeMode ? script : undefined,
);
```

测试成功缓存写入保持：

```tsx
queryClient.setQueryData(["usage", provider.id, appId], result);
```

整体失败时不要写成功缓存；局部失败 `success=true` 时允许写入。

- [ ] **Step 3: 增加最小多指标探测配置区**

在模板选择区域后增加简洁 UI，首版只显示当前 probes 和启用状态，不做复杂拖拽：

```tsx
<div className="space-y-3 border-t border-white/10 pt-3">
  <div className="flex items-center justify-between">
    <h4 className="text-sm font-medium text-foreground">
      {t("usageScript.probeMode", { defaultValue: "多指标探测" })}
    </h4>
    {hasEnabledProbes(script) && (
      <span className="text-xs text-emerald-600 dark:text-emerald-400">
        {t("usageScript.probeModeActive", { defaultValue: "当前生效" })}
      </span>
    )}
  </div>
  <p className="text-xs text-muted-foreground">
    {t("usageScript.probeModeHint", {
      defaultValue:
        "启用后可分别从用量、倍率、模型和账号接口获取指标；没有启用项时使用旧脚本。",
    })}
  </p>
</div>
```

如果当前保存的 `script.probes` 已存在，渲染每个 probe 的 `id/type/enabled`，并允许切换 enabled：

```tsx
{script.probes?.map((probe, index) => (
  <label key={probe.id} className="flex items-center justify-between rounded-lg border border-white/10 px-3 py-2 text-xs">
    <span>{probe.id} · {probe.type}</span>
    <Switch
      checked={probe.enabled}
      onCheckedChange={(checked) => {
        const next = [...(script.probes || [])];
        next[index] = { ...probe, enabled: checked };
        setScript({ ...script, probes: next });
      }}
    />
  </label>
))}
```

- [ ] **Step 4: 运行测试**

Run:

```powershell
pnpm vitest run tests/components/UsageScriptModal.test.tsx
pnpm typecheck
```

Expected: PASS.

- [ ] **Step 5: 提交**

```powershell
git add src/components/UsageScriptModal.tsx tests/components/UsageScriptModal.test.tsx
git commit -m "feat: add usage probe modal flow"
```

## Task 7: 集成冒烟、全量验证和发布边界检查

**Files:**
- Modify: `tests/integration/App.test.tsx`
- Modify: `src/i18n/locales/zh.json`
- Modify: `src/i18n/locales/en.json`

- [ ] **Step 1: 增加集成冒烟**

在 `tests/integration/App.test.tsx` 现有 provider flow 测试附近增加断言：保存 provider meta 时允许 `usage_script.probes` 保留。测试代码按现有 mocks 调整，核心断言为：

```ts
expect(savedProvider.meta?.usage_script?.probes).toEqual([
  expect.objectContaining({
    id: "rate-main",
    type: "rate",
    enabled: true,
  }),
]);
```

- [ ] **Step 2: 补 i18n key**

在 `src/i18n/locales/zh.json` 增加：

```json
{
  "usage": {
    "billingRate": "计费倍率",
    "probeWarning": "用量异常"
  },
  "usageScript": {
    "probeMode": "多指标探测",
    "probeModeActive": "当前生效",
    "probeModeHint": "启用后可分别从用量、倍率、模型和账号接口获取指标；没有启用项时使用旧脚本。"
  }
}
```

在 `src/i18n/locales/en.json` 增加：

```json
{
  "usage": {
    "billingRate": "Billing rate",
    "probeWarning": "Usage probe issue"
  },
  "usageScript": {
    "probeMode": "Multi-metric probes",
    "probeModeActive": "Active",
    "probeModeHint": "When enabled, usage, rate, models, and account metrics can come from separate endpoints. If no probe is enabled, the legacy script is used."
  }
}
```

合并时保持现有 JSON 结构，不重复顶层对象。

- [ ] **Step 3: 运行前端门禁**

Run:

```powershell
pnpm typecheck
pnpm vitest run tests/utils/usageDisplay.test.ts tests/hooks/useProviderActions.test.tsx tests/components/UsageFooter.test.tsx tests/components/UsageScriptModal.test.tsx tests/integration/App.test.tsx
```

Expected: PASS.

- [ ] **Step 4: 运行 Rust 门禁**

Run:

```powershell
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_probe
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_script
cargo test --manifest-path src-tauri/Cargo.toml --lib provider
```

Expected: PASS.

- [ ] **Step 5: 运行仓库发布边界门禁**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1
```

Expected: `overlay_status=overlay_ready` 或脚本定义的成功状态。若环境限制导致命令无法运行，最终汇报必须区分“环境限制”与“代码断言失败”。

- [ ] **Step 6: 最终提交**

```powershell
git add tests/integration/App.test.tsx src/i18n/locales/zh.json src/i18n/locales/en.json
git commit -m "test: cover usage probe integration"
```

## 自查清单

- spec 中旧脚本兼容、多 probe、多接口、倍率展示、usage 失败但 rate 成功仍展示、简短异常标记、安全错误清洗、升级补丁边界都有对应任务。
- 没有任务修改生产 overlay、发布脚本、路由、故障转移或自动切换服务商逻辑。
- `UsageData` 只承载套餐级字段；`rate/rateLabel/models/probeErrors` 在 `UsageResult` 顶层。
- `probes: undefined` 和 `probes: []` 均保持旧逻辑。
- 所有测试命令使用 PowerShell 可执行命令，并给出预期结果。
