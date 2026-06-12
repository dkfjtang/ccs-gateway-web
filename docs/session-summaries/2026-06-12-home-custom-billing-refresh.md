## 2026-06-12 - 首页自定义计费刷新收口

### Key Information
- 首页自定义计费刷新行为已收口为：
  - 首次打开首页时，不自动全量刷新自定义计费。
  - 仅当前激活服务商允许按已配置 `autoQueryInterval` 做单个自动刷新。
  - 首页提供手动批量入口，用于刷新所有已启用 `meta.usage_script.enabled` 的供应商。
- 批量刷新入口已从列表内容区移到顶层 header 左侧开关区后面，不再单独占一行。
- 顶层按钮当前可见短文案为“刷新全部计费”，`aria-label` / `title` 仍保留完整语义“刷新全部自定义计费”。

### Important Information
- 关键实现文件：
  - `src/lib/query/queries.ts`
  - `src/components/UsageFooter.tsx`
  - `src/components/providers/ProviderCard.tsx`
  - `src/components/providers/ProviderList.tsx`
  - `src/App.tsx`
- 批量刷新语义已补齐：
  - 全成功：success toast
  - 部分成功：warning toast，带成功数 / 失败数 / 首个错误
  - 全失败：error toast，带失败数和错误
- Playwright 本机环境已补齐到本仓库本地验证目录：
  - `.run/playwright-smoke/node_modules`
  - 浏览器运行时已可被 Node REPL `import("playwright")` 使用

### Project Information
- 本次为了保证“只当前单个自动刷新”，移除了 `opencode/openclaw/hermes` 过去按 `isInConfig` 触发自动轮询的口径，统一收口为 `isCurrent`。
- 顶层按钮位置调整后，`ProviderList` 不再负责批量刷新入口；位置和行为测试转移到 `App` 级别。

### Verification
- 通过的测试命令：
  - `pnpm vitest run tests/components/useUsageQuery.mount-behavior.test.tsx tests/components/UsageFooter.test.tsx tests/components/ProviderList.test.tsx tests/integration/App.test.tsx`
- 结果：
  - 最终相关回归达到 `4` 个测试文件、`19` 个测试通过
- 本地页面验证：
  - `pnpm dev:web --host 127.0.0.1 --port 4173`
  - `http://127.0.0.1:4173/` 可访问
  - 使用提供的密码登录后，确认首页可见顶层按钮和供应商列表

### Review Conclusions
- 5 轮复审里，`project-assistant` / `review-assistant` 曾指出阻断：
  - 非当前服务商仍可能自动轮询
  - 该问题已修复并补测试
- 后续 2 轮调优复审结论：
  - 按钮位置和样式可过，无阻断问题
  - 非阻断建议主要是：动作按钮与周围开关的语义边界较近，后续若再压缩 header 可考虑加分组留白；测试仍可继续补隐藏/失败分支

### Follow-ups
- 若后续还要继续强化回归，可补：
  - 顶层按钮“无启用脚本时隐藏”的 UI 测试
  - 顶层按钮“部分失败 / 全失败”在 `App` 级别的测试
  - “页面首次进入不自动打 usage 请求，只有点顶栏按钮才批量触发”的更完整端到端语义测试

### Dropped Noise
- 未保留 PowerShell 启动命令中多次出现的变量插值报错原始日志；结论仅保留为“本地 Playwright 与本地 vite 页面最终已成功拉起”。

---

## 2026-06-12 - 继续归结：首屏单项刷新与使用统计 5s 收口

### Key Information
- 用户补充需求：
  - 首页首次打开仍不自动刷新 usage。
  - 当供应商从未刷新过、没有 usage cache 时，行内仍必须显示手动单项刷新按钮。
  - 使用统计页默认刷新频率从 `30s` 改为 `5s`。
- `UsageFooter` 已调整为：`usageEnabled=true` 但 `usage` 尚不存在时，不再返回空，而是显示“从未更新”和单项刷新按钮；按钮点击 `stopPropagation()` 后调用当前 provider/app 的 `refetch()`。
- `UsageDashboard` 默认 `refreshIntervalMs` 改为 `5000`，并通过 props 下传到统计面板。
- `src/lib/query/usage.ts` 的统计查询默认轮询间隔同步改为 `5000ms`。
- `ProviderCard` 只读 usage cache 判断多套餐，不再传 `autoQueryInterval`；自动刷新职责由 `UsageFooter` 统一承担，避免同一当前供应商出现双 interval。

### Important Information
- 本轮涉及的关键实现/测试文件：
  - `src/components/UsageFooter.tsx`
  - `src/components/providers/ProviderCard.tsx`
  - `src/components/providers/ProviderList.tsx`
  - `src/components/usage/UsageDashboard.tsx`
  - `src/lib/query/queries.ts`
  - `src/lib/query/usage.ts`
  - `tests/components/UsageFooter.test.tsx`
  - `tests/components/UsageDashboard.test.tsx`
  - `tests/components/ProviderCard.test.tsx`
  - `tests/components/useUsageQuery.mount-behavior.test.tsx`
  - `tests/components/ProviderList.test.tsx`
  - `tests/integration/App.test.tsx`
- TypeScript 阻断已收口：
  - `UsageFooter` 移除未使用的 `isInConfig` 解构。
  - `ProviderList` 补齐 `toast` import。
  - `ProviderList.test.tsx` 移除未使用 import，并清理 mock 状态。
- `UsageDashboard.test.tsx` 后续补强：不只断言按钮显示 `5s`，还记录并断言各统计面板收到 `refreshIntervalMs: 5000`。

### Review Conclusions
- 第 1 轮子 agent `review-assistant`：条件通过，但指出 Major：
  - `ProviderCard` 和 `UsageFooter` 对同一当前供应商各自调用 `useUsageQuery` 并创建自动刷新 interval，可能导致重复 usage probe。
  - 已修复：`ProviderCard` 只读 cache，不再传 `autoQueryInterval`。
- 第 2 轮子 agent `test-assistant`：条件通过，但指出测试缺口：
  - `UsageDashboard.test.tsx` 只验证 `5s` 文案，未验证 `refreshIntervalMs=5000` 下传。
  - 已补强 props 下传断言。
- 第 3 轮子 agent `ops-assistant`：通过。
  - 不需要触碰发布脚本、Docker、生产配置或 docs。
  - 未发现本次 usage 相关 diff 泄露本机路径、真实 host/IP、账号、容器证据或代理信息。
  - 5s 统计页轮询有一定运行压力但可接受；统计 query 默认不后台轮询，UI 可切换关闭或更低频。

### Verification
- 通过的最终验证命令：
  - `tsc --noEmit`
  - `vitest run tests/components/UsageDashboard.test.tsx tests/components/ProviderCard.test.tsx tests/components/UsageFooter.test.tsx tests/components/useUsageQuery.mount-behavior.test.tsx tests/components/ProviderList.test.tsx tests/integration/App.test.tsx`
  - `git diff --check`
- 最终结果：
  - `6` 个测试文件、`26` 个测试通过。
  - `tests/integration/App.test.tsx` 中的 `broken config` stderr 为测试用例模拟失败路径，测试通过。

### Follow-ups
- 发布或 staging 前注意当前工作区仍存在大量其它未提交改动；只纳入本次 usage 相关文件，避免混入 Docker/docs/scripts 等无关运行证据。
- 如进入本地 WSL 发布前，建议按项目边界使用 `scripts/publish-local-wsl-ccs-web.ps1`，并做一次使用统计页停留 smoke，观察 5s 统计接口无错误和无明显卡顿。

### Dropped Noise
- 未保留子 agent 并发限制失败的原始通知，只保留结论：最初并发/串行尝试因账户限制失败，后续真实完成了 3 轮有效子 agent review。
- 未保留长篇 Vitest stack trace；只保留通过文件数、测试数和与本次需求相关的失败原因/修复结论。
