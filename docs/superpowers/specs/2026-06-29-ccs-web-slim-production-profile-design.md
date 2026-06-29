# ccs-web Slim Production Profile 设计

## 目标

为 `ccs-web` 增加一个面向生产上线的 slim 构建档位，在保留现有完整版本的前提下，产出更小、更少暴露面、更适合被上游业务系统集成的 Web/Proxy 运行件。

这个 slim 档位服务未来的生产链路：

`<client> -> <edge-or-app-entry> -> <ttflows> -> ccs-web slim -> <model-upstream>`

其中 `ttflows` 负责生产入口、用户、密钥、计费、审计、发布编排和运行治理；`ccs-web slim` 专注保留模型代理路由和 Web 管理面。

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
  - 基础登录/会话保护
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

## 架构方案

### 构建档位

新增一个显式 slim 档位，例如：

- Cargo feature：`server-slim`
- Docker build arg：`CCS_WEB_PROFILE=slim`
- 镜像标签后缀：`ccs-web-slim`

默认构建继续产出完整 Web 版本。slim 构建只在显式指定 profile 时生效。

### 后端能力边界

后端应分为三层：

1. `proxy-core`：代理转发、provider router、failover、circuit breaker、usage logging。
2. `web-admin-core`：Web 管理面必需的 provider、proxy、usage、backup、auth、WebDAV/S3 sync API。
3. `non-production-admin`：skills、MCP、desktop helper、third-party local tool management、sessions、workspace、daily memory、local directory/env helper。

slim 档位编译或启动时启用前两层，禁用第三层。

如果短期无法一次性完成 Cargo feature 分层，可先用能力 manifest 在 `/invoke` dispatch 层拒绝非 slim 能力，并在前端菜单层隐藏对应入口；后续再下沉为编译期裁剪。

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
    "local-env-helpers"
  ]
}
```

`/invoke` dispatch 必须先检查 command 所属 group。禁用能力返回稳定错误：

```json
{
  "error": "capability_disabled",
  "message": "This capability is disabled in the current ccs-web profile."
}
```

HTTP 状态建议使用 `403`，避免前端和集成方把它误判成服务不可用。

## 发布与验证

第一轮实施完成后至少需要以下验证：

- 完整版本：
  - `cargo check` 或等价 Rust 检查通过。
  - Web build 通过。
  - 现有 provider/proxy/usage 相关测试通过。
- slim 版本：
  - slim Docker build 通过。
  - `/health` 返回成功。
  - Web 管理页能加载。
  - provider CRUD 可用。
  - proxy status 可读。
  - `/v1/messages`、`/v1/chat/completions`、`/v1/responses` smoke 通过。
  - usage dashboard 和 request log 能读取。
  - 禁用能力的前端入口不可见。
  - 禁用能力的后端 command 返回 `capability_disabled`。
- 回归保护：
  - 429 同 provider/key 本地重试测试继续通过。
  - Responses session stickiness 相关测试继续通过。
  - failover/circuit breaker 行为不因 slim profile 改变。

发布脚本应继续通过既有本地 WSL 发布入口执行，不新增平行的发布脚本。slim 参数应作为现有脚本的 profile 选项扩展。

## 风险与缓解

- 风险：前端隐藏了入口，但后端 API 仍可调用。
  - 缓解：后端 dispatch 必须做 capability gate。
- 风险：Cargo feature 切分过大，影响上游合并。
  - 缓解：第一轮先使用 manifest + dispatch gate，随后逐步下沉到编译期裁剪。
- 风险：误裁剪 usage 或 provider 依赖。
  - 缓解：第一轮明确保留 usage pipeline，并把 provider/proxy/usage 作为验收主路径。
- 风险：同步服务被误归类为本地非生产能力。
  - 缓解：第一轮明确保留 WebDAV/S3 同步服务，并把 sync API 放入 enabled group。
- 风险：TTFlows 和 ccs-web 职责再次重叠。
  - 缓解：`ttflows` 只集成代理接口和健康探测，不接管 ccs-web 内部 provider 路由。
- 风险：生产运行合同漂移。
  - 缓解：slim profile 是新增档位，完整 profile 仍为默认；发布时验证端口、挂载、健康检查、认证和回滚链路。

## 分阶段实施

### 阶段 1：能力清单与运行时 gate

- 建立 command 到 capability group 的映射。
- 新增 profile/capability manifest。
- `/invoke` dispatch 增加 capability gate。
- 前端读取 manifest 并隐藏 disabled group 入口。
- 前端保留 sync 入口，并隐藏 non-production-admin 入口。
- Docker 支持显式 slim profile 参数。

### 阶段 2：构建期裁剪

- 将 extension-admin 相关代码逐步移动到可选 feature。
- slim server build 禁用 extension-admin feature。
- 保留完整版本默认行为。
- 增加 slim 专用测试和 smoke 脚本。

### 阶段 3：TTFlows 生产接入

- 在 `ttflows` 侧配置 `ccs-web slim` upstream。
- 增加健康检查、错误归一化和回滚策略。
- 建立生产发布 runbook，引用 slim 镜像与验证链路。

## 验收标准

设计完成后，实施方案必须满足：

- slim 是显式 opt-in，不影响默认完整版本。
- 保留 A+B 范围和 usage pipeline。
- 保留 WebDAV/S3 同步服务。
- 本地个人工作流在 slim 档位中确认裁剪。
- 禁用能力在前端不可见，在后端不可调用。
- 代理行为与完整版本一致。
- TTFlows 集成边界清晰，不把 TTFlows 业务职责放进 ccs-web。
- 生产文档不包含本机路径、私有主机、真实 IP、私有日志或运行时证据。
