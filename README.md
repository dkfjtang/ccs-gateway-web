# CCS Gateway Web

`ccs-gateway-web` 是基于上游 CC Switch 生态改造的本地 Web 管理与模型代理网关，用于统一管理 Claude Code、Claude Desktop、Codex、Gemini、OpenCode、OpenClaw、Hermes 等工具的供应商配置、模型路由、故障转移、使用量统计与本地代理能力。

当前仓库的定位不是替代上游项目，而是在保留 CC Switch 核心能力的基础上，面向 OpenClaw / WSL / Docker / NGINX 的长期本地部署场景做定制增强。

## 项目来源

本项目从现在起以官方 CC Switch 主线为唯一跟踪上游，旧 Web fork 仅作为辅助参考：

- [farion1231/cc-switch](https://github.com/farion1231/cc-switch)：官方 CC Switch 主项目，是本仓库后续版本拉齐、差异比对和长期跟踪的主线来源，提供 Claude Code / Codex / Gemini 等多应用供应商切换、配置管理、代理、使用量统计、WebDAV 同步等核心能力。
- [cp-yu/cc-switch-web](https://github.com/cp-yu/cc-switch-web)：历史 Web fork 参考源，仅用于对照旧 `v3.15` Web 运行形态、迁移背景和可借鉴实现，不再作为版本跟踪上游。

本仓库继续保留对原项目能力和结构的尊重：上游的 Tauri 桌面代码、配置管理、代理转换、使用量统计、WebDAV 同步、Skills / MCP / Prompt 等能力仍是本项目的重要基础。

## 当前项目定位

当前 fork 主要服务于以下场景：

- 在本地或 WSL/Ubuntu 中长期运行一个 Web 版 CC Switch 管理端。
- 通过 Web UI 管理 Claude Code、Codex、Gemini、OpenCode、OpenClaw 等应用的供应商配置。
- 为 OpenClaw 提供 OpenAI-compatible 本地代理入口，例如 `http://127.0.0.1:15721/v1`。
- 通过 NGINX 暴露唯一 Web 管理入口，同时把模型代理端口限制在本机内部。
- 使用 Docker 方式部署，并通过持久化目录保留供应商配置、SQLite 数据库、Web Auth、备份与同步状态。
- 在保留上游能力的同时，逐步增强 Web runtime、生产部署、安全边界、OpenClaw 集成和本地运维体验。

## 核心能力

- **多应用配置管理**：管理 Claude Code、Claude Desktop、Codex、Gemini、OpenCode、OpenClaw、Hermes 等工具配置。
- **多供应商与模型路由**：维护供应商、模型、认证、模型映射、端点配置和故障转移队列。
- **本地模型代理**：提供 OpenAI-compatible 本地代理端口，供 OpenClaw 或其他本地客户端调用。
- **故障转移与熔断**：按供应商队列、健康状态和错误类型进行路由尝试与保护。
- **Usage / Cost 统计**：支持请求日志、使用量统计、价格配置、单价展示和多来源用量探测脚本。
- **WebDAV 云同步**：支持将数据库和 Skills 等配置快照同步到 WebDAV 服务，例如坚果云、Nextcloud、群晖等。
- **Web Auth**：Web 管理端支持登录鉴权，适合经 NGINX 暴露到局域网或受控网络。
- **Docker + NGINX 部署**：容器只绑定本机回环端口，外部访问统一通过 NGINX 入口。
- **OpenClaw 集成**：支持 OpenClaw 配置导入、模型供应商管理和本地代理链路验证。

## 与上游的主要差异

本仓库目前重点维护 Web runtime 和 OpenClaw 本地部署链路：

- GitHub Releases 侧重 Web 运行版本，而不是桌面端发布物。
- 保留 Tauri 桌面代码，但主要作为上游兼容和本地开发基础。
- 增加 `crates/server` / `crates/core` 的 Web Server 运行路径。
- 增加 Docker 生产部署文件和 NGINX 反代运行手册。
- 默认生产部署建议：
  - Web UI/API：`127.0.0.1:17666`
  - 模型代理：`127.0.0.1:15721`
  - 外部入口：`0.0.0.0:30033 -> 127.0.0.1:17666`
  - NGINX 运行在 WSL/Ubuntu 宿主机，不运行在 CCS 容器内。
- 加强 Web Auth、端口边界、容器持久化、OpenClaw smoke test 和运维 runbook。

更多生产部署细节见：[`docs/ccs-production-runbook.md`](docs/ccs-production-runbook.md)。

## 运行方式

### 本地 Web 运行

```bash
./start-web.sh
```

默认访问：

```text
http://127.0.0.1:17666
```

停止服务：

```bash
./stop-web.sh
```

运行时文件默认写入：

```text
.run/web/backend.log
.run/web/backend.pid
```

### 手动开发运行

```bash
pnpm install
pnpm dev:server
pnpm dev:web
```

### Web 构建

```bash
pnpm build
cargo build --release --manifest-path crates/server/Cargo.toml
./crates/server/target/release/cc-switch-web
```

### Docker 部署

```bash
docker compose -f docker-compose.ccs-web.yml build
docker compose -f docker-compose.ccs-web.yml up -d
```

### 本机 WSL 一键发布

本仓库提供本机 WSL Docker 发布脚本，用于构建、重建 `ccs-gateway-web` 容器并验证 Web UI/API、代理端口和前端构建一致性：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1
```

脚本会使用项目内 ignored 缓存目录加速重复构建，并把日志写入 ignored 的本地运行目录。不要把 `.run/` 下的运行证据提交到仓库。

建议生产形态：

- 容器发布端口只绑定本机：
  - `127.0.0.1:17666:17666`
  - `127.0.0.1:15721:15721`
- 外部只通过 NGINX 访问 Web UI/API。
- 不要把 `15721` 模型代理端口暴露到公网或局域网。
- 启用 `/root/.cc-switch/web-auth.json` 保护管理 UI/API。
- 持久化 `/root/.cc-switch`，可写挂载 `/root/.openclaw`，以便 OpenClaw/Caveman prompt 配置能够写回。

### NGINX 入口安装

WSL/Ubuntu 宿主机可以使用仓库模板安装 NGINX 入口：

```bash
sudo bash scripts/install-wsl-nginx-ccs.sh
```

该入口默认只代理 Web UI/API 到 `127.0.0.1:17666`，并包含隐藏文件探测拦截、安全响应头、连接/请求限制和 WebSocket 透传配置。不要通过 NGINX 暴露模型代理端口。

## 常用检查

```bash
# Web UI/API 健康检查
curl -fsS http://127.0.0.1:17666/health

# 本地模型代理状态
curl -fsS http://127.0.0.1:15721/status

# NGINX 外部入口健康检查
curl -fsS http://127.0.0.1:30033/health

# Web Auth 状态
curl -sS -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:17666/api/invoke \
  -d '{"command":"auth.status","payload":{}}'
```

未登录时，受保护的管理 API 应返回 `401 Unauthorized`。

更完整的 Docker/NGINX smoke test：

```bash
CCS_REQUIRE_NGINX=true ./scripts/ccs-prod-probe.sh
```

## 目录结构

```text
src/                 Web 前端代码（React / TypeScript / Vite）
src-tauri/           上游 Tauri 桌面端与核心后端代码
crates/core/         Web Server 与桌面端复用的核心封装
crates/server/       独立 Web Server 运行时
assets/              截图与静态资源
docs/                部署、运维、规格和补充文档
tests/               前端测试
skills/              Skills 相关资源
```

## 技术栈

- 前端：React 18、TypeScript、Vite、Tailwind CSS、TanStack Query
- 后端：Rust、Tauri 2、Axum、Tokio、Serde
- 数据：SQLite、JSON settings、WebDAV sync snapshot
- 代理：OpenAI-compatible proxy、Anthropic / OpenAI Responses / Gemini 等协议转换
- 部署：Docker、NGINX、WSL/Ubuntu、本地持久化目录

## 开发与验证

常用命令：

```bash
pnpm typecheck
pnpm test:unit
pnpm build
cargo test
cargo build --release --manifest-path crates/server/Cargo.toml
```

如果当前机器缺少 Rust / Node / pnpm 工具链，请不要把静态检查误认为完整测试通过。涉及代理、鉴权、WebDAV、配置保存和模型路由的改动，建议至少经过：

1. 单元测试或类型检查；
2. Web 构建；
3. 本地 Web/API smoke test；
4. OpenClaw 通过 `ccs/gpt-5.5` 的最后一跳验证。

## 安全说明

- Web 管理端暴露到局域网或外部网络前，必须启用 Web Auth。
- 不要提交 `/root/.cc-switch/web-auth-password.txt`、API Key、供应商 Token、WebDAV 密码等敏感信息。
- 生产部署中不要暴露 `15721` 模型代理端口。
- Docker 重建、迁移或清理前，先备份 `/root/.cc-switch` 和关键 OpenClaw 配置。
- WebDAV 同步会上传数据库和 Skills 快照，请确认远端目录和账号权限。
- 本仓库是公共仓库；文档和提交中只能使用 `<repo-root>`、`<wsl-distro>`、`<host>`、`<proxy-url>` 等占位符，不要写入本机路径、私有主机、真实运行日志、容器 ID、镜像 digest 或账号信息。

## 许可证

本项目沿用上游许可，详见 [`LICENSE`](LICENSE)。

## 致谢

感谢 [farion1231/cc-switch](https://github.com/farion1231/cc-switch) 原项目长期构建和维护的 CC Switch 能力体系，包括多应用供应商管理、代理转换、使用量统计、同步与桌面端体验。

感谢 [cp-yu/cc-switch-web](https://github.com/cp-yu/cc-switch-web) 对 Web 运行形态的探索和实现，为本仓库继续推进 Web Server、Docker 部署和 OpenClaw 集成提供了重要基础。

本项目能够继续演进，建立在官方 CC Switch 主线、历史 Web fork 参考及其贡献者工作的基础之上。谢谢你们的付出。
