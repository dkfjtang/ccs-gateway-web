# 服务商用量多指标探测设计

## 摘要

在每个模型服务商的用量配置中增加轻量的多探测能力。一个服务商可以通过多个不同接口分别获取用量、计费倍率、模型列表和账号状态，再把这些探测结果合并到现有服务商用量展示中。

首版只采集和展示结构化探测指标。不实现自动切换服务商、动态路由、价格历史、模型配置同步或倍率趋势。

## 目标

- 旧的单脚本用量配置无需迁移，继续可用。
- 一个服务商可以在同一用量配置下定义多个启用的探测项。
- 支持用量、计费倍率、模型列表、账号状态分别来自不同接口。
- 在现有“已用”用量值附近展示服务商接口返回的计费倍率。
- 为后续自动切换服务商保留结构化字段。
- 保持补丁小而集中，便于后续 CCS 升级版本快速重放。

## 非目标

- 不实现自动切换服务商。
- 不根据探测到的模型列表更新服务商模型配置。
- 不增加倍率历史、趋势图或价格表管理。
- 不修改生产 overlay、发布脚本、路由逻辑或故障转移逻辑。
- 不替换现有 `usage_script.code` 单脚本路径。

## 当前代码上下文

当前实现是单一用量脚本契约：

- `src/types.ts` 定义前端 `UsageScript`、`UsageData`、`UsageResult`。
- `src-tauri/src/provider.rs` 定义 Rust serde 对应结构。
- `src-tauri/src/usage_script.rs` 执行 JavaScript 的 request/extractor 脚本，并校验旧返回字段。
- `src-tauri/src/services/provider/usage.rs` 分发已保存的用量查询和测试查询。
- `src/components/UsageScriptModal.tsx` 负责配置和测试用量脚本。
- `src/components/UsageFooter.tsx` 在服务商卡片上渲染用量值。
- `src/components/providers/ProviderCard.tsx` 承载 `UsageFooter` 和多套餐展开逻辑。

## 数据契约

### UsageScript

在现有 `UsageScript` 上新增可选字段 `probes`。旧配置没有 `probes`，或 `probes` 是空数组时，行为必须与现在完全一致。

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
  request?: {
    url?: string;
    method?: string;
    headers?: Record<string, string>;
    body?: any;
  };
  probes?: UsageProbe[];
}
```

### UsageProbe

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

校验规则：

- `id` 必填、稳定，只允许字母、数字、`_`、`-` 等安全标识字符。
- `type` 必须是 `usage`、`rate`、`models`、`account` 之一。
- 首版最多允许一个启用的 `usage` 探测项。
- 未知 probe type 返回明确校验错误。
- `probes: undefined` 和 `probes: []` 等价于旧的单脚本模式。

### UsageData

`UsageData` 只保留单个套餐或 tier 的用量数据。新增字段也仅限套餐级字段。

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
```

### UsageResult

查询级别的探测指标放到 `UsageResult` 顶层，不塞进第一条 `UsageData`。

```ts
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

这样可以避免“第一条套餐隐式代表全局状态”的契约，也能保持多套餐展示逻辑清晰。

## 合并规则

探测结果按字段归属合并：

- `usage` 负责 `data`，包括 `used`、`remaining`、`total`、`unit`、`planName`、`resetsAt` 和套餐级有效性字段。
- `rate` 负责 `rate` 和 `rateLabel`。
- `models` 负责 `models`。
- `account` 负责账号级有效性和安全错误摘要，不覆盖套餐级用量结果。

如果某个探测项返回了不属于自己归属范围的字段，合并输出时忽略这些字段。开发调试阶段可以记录日志，但不能让不同探测项互相覆盖核心字段。

失败语义：

- 旧单脚本模式保持现有行为。
- 多探测模式下，`usage` 探测失败时返回 `success=false`，但不得丢弃已成功的 `rate`、`models`、`account` 探测结果。
- `rate`、`models`、`account` 失败但 `usage` 成功时，返回 `success=true`，保留用量数据，并把安全错误摘要写入 `probeErrors[probe.id]`。
- 非核心探测失败不得覆盖成功的用量字段。
- 整体测试失败时，不得把旧缓存和新字段混合写成假成功状态。

## 安全规则

多探测执行不能继承旧 `custom` 模板的宽松跨域语义。

- 探测请求复用现有全局 HTTP client 和超时 clamp。
- 探测请求默认只允许 HTTPS；开发场景允许 localhost / loopback。
- 不因为旧 `templateType` 是 `custom` 就隐式允许任意跨域访问。
- 如果未来需要跨域逃生口，必须是每个 probe 显式配置，并且默认预置项不暴露给普通用户。
- 写入 `probeErrors` 的错误信息不得包含 API key、access token、Authorization header 或请求体。
- probe 结果校验必须独立于旧 `usage_script.validate_result`，这样可以校验新字段类型，同时不破坏旧脚本兼容。

## 执行流程

1. 读取 provider 和已保存的 `usage_script`。
2. 如果用量查询未启用，保持现有 disabled 行为。
3. 如果 `usage_script.probes` 没有启用项，执行旧单脚本路径。
4. 如果存在启用 probe，先校验 probe 列表。
5. 首版按顺序逐个执行启用的 probe，保持失败顺序确定，便于测试和排障。
6. 按 probe type schema 校验每个探测结果。
7. 按合并规则合并为一个 `UsageResult`。
8. 通过现有前端查询路径返回结果。

实现时新增独立模块，例如 `src-tauri/src/usage_probe.rs`，负责 probe 执行、校验和合并。`src-tauri/src/services/provider/usage.rs` 只负责在旧路径和多 probe 路径之间分流。

## UI 设计

### UsageScriptModal

保留现有脚本编辑器和模板。在此基础上增加清晰标注的“多指标探测”区域。

规则：

- 只要至少一个 probe 启用，页面明确显示当前生效的是多探测模式。
- 旧脚本编辑区保留，用于兼容和迁移，但测试和保存时必须清楚当前生效模式。
- 测试按钮执行当前生效模式。
- 多探测测试结果展示每个 probe 的成功/失败状态，并展示清洗后的 `probeErrors`。
- probe 配置尽量复用现有供应商凭证变量，例如 `{{apiKey}}`、`{{baseUrl}}`、`{{accessToken}}`、`{{userId}}`。

### UsageFooter

倍率只在 `UsageFooter` 渲染，不把新字段理解逻辑扩散到 `ProviderCard`。

- 服务商卡片内联视图：当 `usage.rate` 或 `usage.rateLabel` 存在时，在现有“已用”附近显示 `计费倍率 x1.5`。
- 如果有 `rateLabel`，优先显示 `rateLabel`，否则格式化 `rate`。
- 没有倍率时不显示占位。
- `success=false` 但当前结果里包含成功探测到的 `rate` 或 `rateLabel` 时，仍显示当前计费倍率，并在用量区域显示简短异常标记，例如 `用量异常` 或 `探测异常`。不能显示旧的或缓存残留的倍率文本。
- 多套餐展开视图：可以在头部显示查询级计费倍率；不要让用户误解为每个套餐都有独立倍率。
- 模型列表不在服务商卡片铺开。首版只在测试结果或详情里显示简要数量，例如 `模型 12 个`。

## 兼容策略

- 旧单脚本配置无需迁移。
- `probes: undefined` 和 `probes: []` 都走旧路径。
- `github_copilot`、`token_plan`、`balance` 等现有特殊模板继续保持原处理方式，不能被 probes 误接管。
- 旧脚本返回的 `UsageData.extra` 继续支持。
- 前端继续调用 `queryProviderUsage` 和 `testUsageScript`。为了测试 probes，`testUsageScript` 可以新增一个可选的完整 `UsageScript` 参数，同时保留现有扁平参数。

## 升级补丁边界

补丁应尽量集中，便于后续升级重放：

- `src/types.ts`：仅扩展类型。
- `src-tauri/src/provider.rs`：扩展 serde 类型和兼容性测试。
- `src-tauri/src/usage_probe.rs`：新增 probe 执行、校验和合并模块。
- `src-tauri/src/lib.rs`：注册新模块。
- `src-tauri/src/services/provider/usage.rs`：旧路径和 probe 路径分流。
- `src-tauri/src/commands/provider.rs`：最小化扩展 `testUsageScript` 入参。
- `src/lib/api/usage.ts`：兼容可选完整脚本测试参数。
- `src/components/UsageScriptModal.tsx`：新增 probe 配置和当前模式测试行为。
- `src/components/UsageFooter.tsx`：新增计费倍率展示。
- 对应测试：格式化、保存流程、合并语义和兼容性。

避免修改路由、故障转移、代理选择、overlay 脚本、生产发布脚本或服务商切换逻辑。

## 验收标准

- 旧 provider 没有 `probes` 字段时，查询和展示与原行为一致。
- `probes: []` 与没有 `probes` 行为一致。
- 只有至少一个 probe 启用时才进入多探测模式。
- 一个启用的 `usage` probe 加成功的 `rate`、`models`、`account` probe，返回 `success=true`，包含用量数据和顶层 `rate`、`models`、账号状态字段。
- `rate`、`models`、`account` 失败不阻断成功用量展示。
- `usage` probe 失败返回 `success=false` 和安全错误信息；如果 `rate` probe 成功，列表页仍显示当前计费倍率，并显示简短异常标记。
- 服务商卡片在“已用”附近展示计费倍率。
- 无倍率、当前查询失败或没有结果时，不显示 `undefined`、空占位或旧倍率残留。
- 配置/测试结果区域展示的 probe 错误不得泄露凭证。
- 探测到的模型列表只是展示快照，不更新 provider 模型配置。
- i18n 至少补齐中文和英文：probe 类型名、计费倍率、部分探测失败、模型数量、账号状态。

## 测试计划

必补 Rust 测试：

- `UsageScript` 旧配置无 `probes` 时 serde 兼容。
- `probes: []` 等价于旧模式。
- `UsageProbe` 校验拒绝未知类型、空 id、不安全 id 和多个启用的 `usage` probe。
- probe 结果校验拒绝非数字 `rate`、非法模型数组和格式错误的 `probeErrors`。
- 合并测试覆盖所有 probe 成功、非核心 probe 失败、核心 usage 失败。
- 旧 `usage_script` 的单对象和数组返回继续保持原行为。

必补前端测试：

- `UsageFooter` 优先展示 `rateLabel`，其次展示格式化 `rate`，无倍率时不显示占位。
- `UsageFooter` 在 `success=false` 但当前结果包含 `rate` 或 `rateLabel` 时展示当前倍率和简短异常标记；没有当前倍率时不展示旧倍率。
- `usageDisplay` 摘要默认忽略 probe-only 字段，除非后续明确设计要展示。
- `saveUsageScript` 保存时保留 `probes`，不丢 `request`、`extractor`、`timeout`。
- `UsageScriptModal` 在多探测模式下测试时传完整 script，并且只在成功结果下更新 `["usage", provider.id, appId]` 缓存。
- App/provider 流程冒烟测试确认新 `probes` 元数据可保存，且不破坏旧服务商操作。

建议验证命令：

```powershell
pnpm typecheck
pnpm vitest run tests/utils/usageDisplay.test.ts tests/hooks/useProviderActions.test.tsx tests/integration/App.test.tsx
pnpm vitest run tests/components/UsageScriptModal.test.tsx tests/components/UsageFooter.test.tsx
cargo test --manifest-path src-tauri/Cargo.toml --lib usage_script
cargo test --manifest-path src-tauri/Cargo.toml --lib provider::tests
cargo test --manifest-path src-tauri/Cargo.toml
```

发布准备时，本仓库已有 overlay 门禁仍保持独立执行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-local-overlays.ps1
```

## 待确认决策

- 账号级有效性后续是否升级为顶层 `UsageResult.account` 对象。首版保持最小字段，避免扩大 UI 范围。
