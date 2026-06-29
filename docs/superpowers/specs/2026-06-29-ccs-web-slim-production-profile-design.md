# ccs-web Slim Production Profile 设计

## 目标

为 `ccs-web` 增加一个面向生产上线的 slim 构建档位，在保留现有完整版本的前提下，产出更小、更少暴露面、更适合被上游业务系统集成的 Web/Proxy 运行件。

这个 slim 档位服务未来的生产链路：

`<client> -> <edge-or-app-entry> -> <ttflows> -> ccs-web slim -> <model-upstream>`

其中 `ttflows` 负责生产入口、用户、密钥、计费、审计、发布编排和运行治理；`ccs-web slim` 专注保留模型代理路由和 Web 管理面。

## 职责与术语边界

`ttflows` 是生产业务控制面：

- 终端用户体系、业务 API key、租户权限、账户余额和业务计费以 `ttflows` 为准。
- 用户级请求审计、对外错误归一化、生产发布编排、健康探测和回滚策略以 `ttflows` 为准。
- `ttflows` 只通过标准 OpenAI/Anthropic 兼容代理接口集成 `ccs-web slim`，不直接依赖 `ccs-web` 内部管理 API。

`ccs-web slim` 是 provider/router 管理面和 upstream 代理层：

- `ccs-web slim` 保留的 usage、pricing、request log 是 provider 成本、路由观测和管理面统计，不是生产用户业务计费的 source of truth。
- `ccs-web slim` 的 auth 只保护 Web 管理面和管理 API，不承担 `ttflows` 的终端用户身份、业务 key 或租户授权。
- `ccs-web slim` 不新增面向终端用户的账户体系，不把 `ttflows` 的业务计费、审计或错误合同下沉到 `ccs-web`。

术语必须保持明确：

- `Responses session stickiness` 是代理路由行为，必须保留。
- `session usage sync` 是 usage 页面相关的只读统计能力，必须保留到能支撑 usage 页面。
- `session manager` 是本地个人工作流能力，slim 档位确认裁剪。

## 保留范围

slim 档位必须保留：

- 代理核心路径：
  - `/v1/messages`
  - `/v1/chat/completions`
  - `/v1/responses`
  - `/v1/responses/compact`
  - 兼容的模型和健康检查接口
- Provider 管理：
  - provider 增删改查
  - 当前 provider 切换
  - provider 排序
  - provider live config 同步
  - provider 可用性检查
- 路由与韧性：
  - failover queue
  - circuit breaker
  - provider health
  - Responses session stickiness
  - 现有 429 同 provider/key 本地重试策略
- Web 管理面：
  - 管理面登录/会话保护
  - provider 管理页
  - proxy 管理页
  - failover/circuit breaker 配置页
  - 用量、计费、日志和统计页面
- Usage pipeline：
  - request log
  - usage summary
  - provider/model stats
  - pricing config
  - upstream usage query script
  - session usage sync 中与当前 Web 页面直接相关的只读展示能力
- 导入导出与备份：
  - 配置 SQL 导入导出
  - 数据库备份、恢复、重命名、删除
  - 生产可回滚所需的基础配置迁移能力
- 同步服务：
  - WebDAV 同步
  - S3 同步

## 第一轮裁剪范围

第一轮 slim 不改变代理行为，不裁剪 usage pipeline，不裁剪 WebDAV/S3 同步服务，重点裁剪已经确认不进入 slim 生产档位的桌面端、扩展生态和第三方本地工具配置管理能力。

确认裁剪项：

- 桌面 Tauri 专属能力：
  - tray
  - window state
  - auto launch
  - desktop updater
  - desktop deep link handling
  - desktop-only open terminal/open folder helpers
- 扩展生态管理：
  - skill repo 管理
  - skill 安装、更新、迁移、备份
  - unmanaged skill 扫描
  - skills.sh 搜索
  - MCP 服务器管理与跨应用同步
- 第三方本地工具配置管理：
  - Claude Desktop 直接配置修复类入口
  - Hermes 本地 dashboard 启动与 memory 配置管理
  - OpenClaw 本地 workspace/config/tools 管理
  - OpenCode/OMO 本地文件读取和禁用入口
- 本地个人工作流：
  - session manager 终端启动
  - workspace file editor
  - daily memory 文件管理
  - local directory picker
  - local env conflict repair
- 高敏感本地/扩展 token 捕获能力：
  - auth-vault token/cookie capture API
  - auth-vault token summary API

确认裁剪项必须以 build profile 或 capability manifest 控制，不能从默认完整版本中直接删除。

## 明确不做

第一轮不做以下变更：

- 不改变 provider routing、failover、circuit breaker、429 重试分类或 Responses stickiness。
- 不删除计费、用量、统计、request log 或 pricing 相关代码。
- 不删除 WebDAV/S3 同步服务。
- 不重写代理转发核心。
- 不把 `ttflows` 的用户、密钥、计费或审计逻辑放进 `ccs-web`。
- 不改变现有完整版本的默认构建和发布路径。
- 不把本地发布证据、私有主机信息、机器路径或运行时日志写入 tracked 文档。
- 不把 auth-vault 或其它 token 捕获能力保留在 slim 生产档位。

## 架构方案

### 构建档位

新增一个显式 slim 档位：

- Cargo feature：`server-slim`
- Docker build arg：`CCS_WEB_PROFILE=slim`
- 镜像标签后缀：`ccs-web-slim`

默认构建继续产出完整 Web 版本。slim 构建只在显式指定 profile 时生效。

### Profile 来源

profile 必须有单一传播链：

1. 发布脚本参数 `-Profile full|slim` 是操作者入口，默认值必须是 `full`。
2. 发布脚本把 profile 传给 Docker build arg `CCS_WEB_PROFILE`。
3. Docker build arg 同步传给前端 `VITE_CCS_WEB_PROFILE` 和后端构建/运行 profile。
4. 构建产物必须通过 `build-info.json` 或等价接口暴露 profile，便于 smoke 和发布脚本断言。
5. 运行时环境变量只能用于断言或收紧 profile，不得把一个 slim 构建静默放宽为 full，也不得把默认 full 构建静默切成 slim。

未显式传入 `-Profile slim` 时，任何本地构建、Docker 构建、发布脚本和完整版本验证都必须保持 full 行为。

### 后端能力边界

后端应分为三层：

1. `proxy-core`：代理转发、provider router、failover、circuit breaker、usage logging。
2. `web-admin-core`：Web 管理面必需的 provider、proxy、usage、backup、auth、WebDAV/S3 sync API。
3. `non-production-admin`：skills、MCP、desktop helper、third-party local tool management、sessions、workspace、daily memory、local directory/env helper。

slim 档位编译或启动时启用前两层，禁用第三层。

如果短期无法一次性完成 Cargo feature 分层，可先用能力 manifest 在 `dispatch_command` 入口拒绝非 slim 能力，并在前端菜单层隐藏对应入口；后续再下沉为编译期裁剪。

`dispatch_command` 是 RPC capability gate 的第一落点，因为 HTTP `/api/invoke` 和 WebSocket `/api/ws` 都必须走同一 command 分类。禁用能力不能只在 `/api/invoke` 上处理。

### 前端能力边界

前端应读取 build-time capability manifest，并根据 profile 隐藏或禁用不在 slim 范围内的页面入口。

slim 前端应保留：

- providers
- proxy
- failover
- settings 中与 provider/proxy/usage/backup/auth 直接相关的部分
- usage dashboard
- request logs
- import/export
- WebDAV/S3 sync

slim 前端应隐藏：

- skills
- MCP
- local desktop helper 入口
- third-party local tool management 入口
- sessions
- workspace
- daily memory
- local directory/env helper 入口

隐藏入口不是安全边界；对应后端 API 也必须被 capability manifest 或 feature gate 拒绝。

前端还必须处理直接访问和残留状态：

- 如果 localStorage 记住了 disabled view，slim 启动时必须回落到安全的默认 view。
- 手动访问 disabled route/view 时必须回落、重定向或显示不可用状态，不能加载 disabled 组件。
- disabled 能力相关启动副作用不得执行，例如 skills migration 检查、本地 env conflict repair、workspace/session 初始化。
- toolbar action、settings tab、dialog launcher 和 deep-link/import 入口都必须受同一 capability 判断控制。

### TTFlows 集成边界

`ttflows` 作为生产消费者时，应通过标准 OpenAI/Anthropic 兼容代理接口访问 `ccs-web slim`。两者边界如下：

- `ttflows` 负责：
  - 用户体系
  - API key 发行与校验
  - 业务计费与账户余额
  - 请求审计
  - 上线编排、健康探测和回滚
  - 对外错误归一化
- `ccs-web slim` 负责：
  - upstream provider 配置
  - provider 路由
  - failover/circuit breaker
  - upstream 请求转发和响应流处理
  - 本地 usage/request log 观测

`ccs-web slim` 不应向终端用户暴露 `ccs` 内部错误、私有 provider 细节或本地运行路径。面向外部的错误归一化由 `ttflows` 兜底，`ccs-web slim` 仍需避免泄露敏感运行时信息。

## API 策略

新增一份 capability manifest，例如：

```json
{
  "profile": "slim",
  "enabledGroups": [
    "auth",
    "providers",
    "proxy",
    "failover",
    "usage",
    "logs",
    "settings-basic",
    "backup",
    "import-export",
    "sync"
  ],
  "disabledGroups": [
    "skills",
    "mcp",
    "desktop-helpers",
    "third-party-local-tools",
    "sessions",
    "workspace",
    "daily-memory",
    "local-env-helpers",
    "auth-vault"
  ]
}
```

### Capability 分类要求

实施前必须先完成阶段 0 能力矩阵，至少覆盖：

- RPC command 到 capability group 的完整映射。
- HTTP route 到 capability group 的完整映射。
- WebSocket command 到 capability group 的完整映射。
- 前端 view、settings tab、toolbar action、dialog launcher 到 capability group 的完整映射。
- retained/disabled Rust 模块和后续 Cargo feature 的映射。
- 每个 capability group 的测试用例。

所有已存在 command 和 route 必须被穷尽分类。新增 command 或 route 未分类时必须 fail closed，并通过测试阻止进入 slim。

### Route Gate

slim 第一阶段必须显式声明这些路由：

- `/health`：保留，可公开用于健康检查，不泄露私有配置。
- `/build-info.json`：保留，可公开或受控访问，但只能暴露 sanitized build metadata 和 profile。
- 静态 SPA：保留，但不能绕过后端 auth/capability gate。
- `/api/invoke`：保留，先做管理面 auth，再做 `dispatch_command` capability gate。
- `/api/ws`：保留，先做管理面 auth，再做每条 JSON-RPC command capability gate。
- `/api/import-config`：保留，必须要求管理面 auth，并保留大小限制和安全校验。
- `/api/export-config`：保留，必须要求管理面 auth。
- `/api/auth-vault/*`：slim 禁用，返回 `capability_disabled` 或等价 forbidden 响应。
- Proxy `/health`、`/status`、`/v1/messages`、`/v1/chat/completions`、`/v1/responses`、`/v1/responses/compact`：保留，作为 proxy-core 验收路径。

未知管理路由和未知 command 在 slim 中必须 fail closed。

### 禁用响应

HTTP `/api/invoke` 禁用能力返回稳定错误：

```json
{
  "error": "capability_disabled",
  "capability": "<capability-group>",
  "command": "<command-name>",
  "message": "This capability is disabled in the current ccs-web profile."
}
```

HTTP 状态必须使用 `403`，避免前端和集成方把它误判成服务不可用。当前错误包装如果只能返回 `400`，实施时必须先扩展错误类型或在 handler 中特判 capability error。

WebSocket JSON-RPC 禁用能力必须返回稳定 JSON-RPC error，包含 `capability_disabled` 和 capability group，不能静默断连或返回成功空值。

### Auth Gate

slim 生产档位必须 fail closed：

- 缺少或无效管理面 auth 配置时，不得把管理 API 当作可用生产服务启动。
- 允许本地开发或测试显式使用临时免 auth 模式，但必须通过明确的非生产 override，并且发布脚本、生产 runbook 和 slim 生产 smoke 不得使用该 override。
- 管理面 protected command、WebSocket、import/export、backup/restore、sync settings、usage/request log 都必须经过管理面 auth。
- 未认证访问 protected RPC 必须返回 `401`，禁用能力在认证通过后返回 `403 capability_disabled`。

## 发布与验证

第一轮实施完成后至少需要以下验证：

- 完整版本：
  - `cargo check` 或等价 Rust 检查通过。
  - Web build 通过。
  - 现有 provider/proxy/usage 相关测试通过。
  - 未传 profile 时 build-info、manifest、UI 和 command allowlist 均保持 full 行为。
- slim 版本：
  - slim Docker build 通过。
  - build-info 或等价接口显示 profile 为 `slim`。
  - `/health` 返回成功。
  - Web 管理页能加载。
  - provider CRUD 可用。
  - proxy status 可读。
  - `/v1/messages`、`/v1/chat/completions`、`/v1/responses`、`/v1/responses/compact` smoke 通过。
  - usage dashboard 和 request log 能读取。
  - pricing config、WebDAV/S3 管理入口和 sync command 可用。
  - 禁用能力的前端入口不可见，直接访问 disabled view 会回落或显示不可用。
  - 禁用能力的 HTTP RPC command 返回 `403 capability_disabled`。
  - 禁用能力的 WebSocket command 返回 JSON-RPC capability error。
  - `/api/auth-vault/*` 在 slim 下不可用。
  - slim 生产模式缺少 auth 配置时 fail closed。
- 回归保护：
  - 429 同 provider/key 本地重试测试继续通过。
  - Responses session stickiness 相关测试继续通过。
  - failover/circuit breaker 行为不因 slim profile 改变。

发布脚本应继续通过既有本地 WSL 发布入口执行，不新增平行的发布脚本。slim 参数应作为现有脚本的 profile 选项扩展。

### 测试矩阵

实施计划必须覆盖以下测试层：

| 层级 | 目的 |
| --- | --- |
| Rust unit | full/slim capability manifest、command 分组穷尽性、禁用 command 的 HTTP/WS 错误映射、auth fail-closed |
| Frontend unit | slim 下隐藏 disabled entry，保留 providers/proxy/usage/import-export/WebDAV/S3，残留 localStorage view 回落，disabled 副作用不执行 |
| Server/API | `/health`、`/build-info.json`、provider CRUD、proxy status、usage/request log、pricing、SQL import/export、WebDAV/S3 command |
| Proxy regression | `/v1/messages`、`/v1/chat/completions`、`/v1/responses`、`/v1/responses/compact`，429 retry，Responses stickiness，failover/circuit breaker |
| Publish smoke | `-Profile full` 默认行为、`-Profile slim` 构建/运行/日志/served-build/profile 断言 |
| Docs/security | tracked 文档、示例和 runbook 不包含私有主机、IP、本机路径、token、运行证据 |

空数据下 usage dashboard/request log 可以通过，但必须明确展示空态且 API 成功；provider CRUD 可以使用 stub provider 或测试 DB，不要求真实 upstream 凭据。

### 发布脚本与回滚合同

发布脚本扩展必须满足：

- 只扩展 `scripts/publish-local-wsl-ccs-web.ps1`，不新增平行发布脚本。
- 新增参数 `-Profile full|slim`，默认 `full`。
- `slim` 必须显式传入，不允许通过环境漂移隐式启用。
- 脚本必须把 profile 传入 Docker build arg、镜像 tag、运行环境和本地日志。
- 镜像 tag 必须不可覆盖，包含 profile 和版本/commit 标识；保留 previous slim 和 known-good full 回滚路径。
- 发布前记录 previous image/container/config backup；失败时明确回滚到 previous slim 或 known-good full。
- 本地 WSL compose 可用于本地验证，但生产发布不得直接复用本地 dirty compose；生产必须保留 inspect-derived runtime contract。
- 发布证据写入 ignored local 目录，tracked 文档只写 sanitized procedure。

生产运行合同 gate 必须验证：

- container name、command、restart policy、env、mount、network、port binding 与预期合同一致。
- Web 管理面 auth enabled，未认证 protected RPC 返回 `401`。
- 管理面和 proxy 暴露面只走受控入口；外部不可直连非预期端口。
- `ccs-prod-probe.sh` 或等价 probe 覆盖 Web `/health`、proxy `/status`、auth boundary、profile、proxy smoke、usage/request log。

### TTFlows 接入前置 Gate

阶段 3 进入生产流量前，TTFlows 侧必须先证明：

- 只通过 OpenAI/Anthropic 兼容接口访问 `ccs-web slim`。
- upstream health gating 已启用，`ccs-web` 整体不可用时才触发受控 fallback。
- 对外错误已归一化，不泄露 `ccs-web` 内部路径、provider 细节、上游私有错误或本地运行信息。
- 业务计费与审计记录以 `ttflows` 为 source of truth，并有成功请求、失败请求、超时/fallback 请求的记录一致性验证。
- TTFlows timeout、fallback、熔断边界不会绕过 `ccs-web` 的 provider routing 设计。

## 风险与缓解

- 风险：前端隐藏了入口，但后端 API 仍可调用。
  - 缓解：后端 `dispatch_command`、HTTP route、WebSocket command 都必须做 capability gate，未知项 fail closed。
- 风险：生产 slim 管理面 auth fail-open。
  - 缓解：slim 生产模式缺少或无效 auth 配置时 fail closed；本地免 auth 只能显式非生产 override。
- 风险：auth-vault 继续暴露 token/cookie 捕获能力。
  - 缓解：auth-vault 加入 disabled group，slim 下 route 级禁用并测试。
- 风险：Cargo feature 切分过大，影响上游合并。
  - 缓解：第一轮先使用 manifest + runtime gate，随后按 `src-tauri` 非生产模块 -> `cc-switch-core` re-export/API -> `cc-switch-server` feature 的顺序下沉到编译期裁剪。
- 风险：误裁剪 usage 或 provider 依赖。
  - 缓解：第一轮明确保留 usage pipeline，并把 provider/proxy/usage 作为验收主路径。
- 风险：同步服务被误归类为本地非生产能力。
  - 缓解：第一轮明确保留 WebDAV/S3 同步服务，并把 sync API 放入 enabled group。
- 风险：TTFlows 和 ccs-web 职责再次重叠。
  - 缓解：`ttflows` 只集成代理接口和健康探测，不接管 ccs-web 内部 provider 路由。
- 风险：生产运行合同漂移。
  - 缓解：slim profile 是新增档位，完整 profile 仍为默认；发布时验证端口、挂载、健康检查、认证和回滚链路。

## 分阶段实施

### 阶段 0：能力矩阵与合同冻结

- 建立 command、HTTP route、WebSocket command、frontend view、settings tab、toolbar action、dialog launcher 到 capability group 的矩阵。
- 标记每项为 retained、disabled 或 full-only，并写明测试用例。
- 明确 profile source of truth、build-info profile 断言、auth fail-closed 规则、auth-vault 禁用规则。
- 明确 session usage sync、Responses session stickiness、session manager 三者边界。
- 明确发布脚本 `-Profile full|slim`、镜像 tag、日志、回滚和生产 runtime contract gate。

### 阶段 1：能力清单与运行时 gate

- 新增 profile/capability manifest。
- `dispatch_command` 增加 capability gate，覆盖 HTTP `/api/invoke` 和 WebSocket `/api/ws`。
- HTTP route gate 覆盖 `/api/auth-vault/*`、`/api/import-config`、`/api/export-config` 等直接路由。
- auth gate 在 slim 生产模式下 fail closed。
- 前端读取 manifest 并隐藏 disabled group 入口。
- 前端保留 sync 入口，并隐藏 non-production-admin 入口。
- 前端处理直接访问 disabled view、localStorage 残留和 disabled 启动副作用。
- Docker 支持显式 slim profile 参数。

### 阶段 2：构建期裁剪

- 按 `src-tauri` 非生产模块、`cc-switch-core` re-export/API、`cc-switch-server` feature 的顺序移动到可选 feature。
- slim server build 禁用 non-production-admin feature。
- 保留完整版本默认行为。
- 增加 slim 专用测试和 smoke 脚本。

### 阶段 3：TTFlows 生产接入

- 本 repo 交付 slim 镜像合同、健康检查、错误泄露约束、发布/回滚 runbook 和 TTFlows 接入说明。
- TTFlows 侧改动作为外部依赖，不阻塞本 repo slim profile 基础交付。
- 进入生产流量前必须通过 TTFlows 接入前置 gate。

## 验收标准

设计完成后，实施方案必须满足：

- slim 是显式 opt-in，不影响默认完整版本。
- 保留 A+B 范围和 usage pipeline。
- 保留 WebDAV/S3 同步服务。
- 本地个人工作流在 slim 档位中确认裁剪。
- 禁用能力在前端不可见，直接访问不可用，在 HTTP/WS/RPC 后端不可调用。
- auth-vault 在 slim 下禁用。
- slim 生产模式 auth fail-closed。
- 所有 command/route/view 均被 capability matrix 分类，未知项 fail closed。
- 发布脚本 profile、build-info profile、镜像 tag 和回滚合同可验证。
- 代理行为与完整版本一致。
- TTFlows 集成边界清晰，不把 TTFlows 业务职责放进 ccs-web。
- 生产文档不包含本机路径、私有主机、真实 IP、私有日志或运行时证据。
