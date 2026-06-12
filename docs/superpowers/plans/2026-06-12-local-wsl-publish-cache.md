# 本机 WSL 发版缓存优化实施计划

> **面向执行型智能体：** 实施本计划时，必须配套使用 `superpowers:subagent-driven-development`（优先）或 `superpowers:executing-plans`，按任务逐项推进。步骤使用 `- [ ]` 勾选格式追踪。

**目标：** 为 `ccs-gateway-web` 的本机 WSL 重复发版提速，引入项目内 Docker/BuildKit 缓存和 Docker 前端产物快照管理，同时不削弱当前健康检查和 served-build 一致性校验。

**架构思路：** 保留现有 `publish-local-wsl-ccs-web.ps1` 入口脚本和多阶段 `Dockerfile.web`，在 `.run/build-cache` 下增加统一缓存根目录，让脚本自动管理前端输入指纹，并把 Docker / BuildKit 与容器内 `cargo` / `pnpm` 的缓存挂接到当前构建路径中。前端一致性校验以 Docker `frontend-dist` stage 导出的快照为基准，避免依赖 Windows 工作区 `dist`。必须保留冷构建的正确性，且所有缓存状态都应可随时丢弃。

**技术栈：** PowerShell 5.1、WSL bash、Docker BuildKit、docker compose、pnpm 9、Vite、Rust/Cargo

---

## 文件映射

- 修改：`scripts/publish-local-wsl-ccs-web.ps1`
  - 增加缓存目录初始化、前端指纹计算、Docker 前端快照刷新决策、BuildKit 缓存构建入口，以及可选的 `-NoCache` / `-SkipFrontendBuild`。
- 修改：`Dockerfile.web`
  - 为 `pnpm` 和 `cargo` 增加 BuildKit cache mount，在保持最终镜像行为不变的前提下减少重复下载和重复构建。
- 修改：`.gitignore`
  - 如果当前忽略规则不足，确保新的 `.run/build-cache/**` 元数据和缓存目录保持忽略状态。
- 新建：`scripts/get-local-wsl-publish-fingerprint.ps1`
  - 计算本地 `dist` 是否需要重建所需的稳定前端指纹。
- 测试 / 验证命令：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro>`
  - 重复执行发版脚本，验证热缓存路径行为

### 任务 1：新增前端指纹工具

**文件：**
- 新建：`scripts/get-local-wsl-publish-fingerprint.ps1`
- 测试：手工执行命令

- [ ] **步骤 1：编写工具脚本**

创建 `scripts/get-local-wsl-publish-fingerprint.ps1`，要求：

- 接收 `-ProjectRoot`
- 枚举前端相关输入：
  - `src`
  - `package.json`
  - `pnpm-lock.yaml`
  - `pnpm-workspace.yaml`
  - `vite.config.ts`
  - `tailwind.config.cjs`
  - `postcss.config.cjs`
  - `tsconfig.json`
  - `tsconfig.node.json`
- 基于相对路径 + 文件字节内容计算一个稳定的 SHA-256 字符串
- 只向标准输出打印最终指纹

应使用 PowerShell 对真实文件内容做哈希；缺失的可选文件应被安全跳过。

- [ ] **步骤 2：执行工具脚本**

运行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\get-local-wsl-publish-fingerprint.ps1 -ProjectRoot .
```

预期：

- 退出码为 `0`
- 输出一个非空、类似 SHA-256 的指纹字符串

- [ ] **步骤 3：提交工具脚本**

```powershell
git add scripts/get-local-wsl-publish-fingerprint.ps1
git commit -m "feat: add local publish frontend fingerprint utility"
```

### 任务 2：显式化本机构建缓存路径

**文件：**
- 修改：`scripts/publish-local-wsl-ccs-web.ps1`
- 修改：`.gitignore`

- [ ] **步骤 1：增加缓存路径常量和目录创建逻辑**

在 `scripts/publish-local-wsl-ccs-web.ps1` 中新增函数或变量，用于管理：

- `.run/build-cache`
- `.run/build-cache/frontend-dist`
- `.run/build-cache/docker`
- `.run/build-cache/meta`

这些路径都必须解析在项目根目录下，并像现有 `.run` 日志目录护栏一样做边界校验。

- [ ] **步骤 2：必要时更新忽略规则**

确认 `.gitignore` 已忽略：

```gitignore
.run/build-cache/
```

如果已有更宽泛的 `.run/` 忽略规则，则确认无需新增重复或冲突模式。

- [ ] **步骤 3：执行聚焦冒烟检查**

运行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro> -NoStart -SkipHealthCheck
```

预期：

- 退出码为 `0`
- 在 `.run/build-cache` 下创建缓存目录
- 不启动或重建容器运行状态

- [ ] **步骤 4：提交缓存路径初始化**

```powershell
git add scripts/publish-local-wsl-ccs-web.ps1 .gitignore
git commit -m "feat: add project-local cache directories for WSL publish"
```

### 任务 3：增加 Docker 前端产物快照自动刷新逻辑

**文件：**
- 修改：`scripts/publish-local-wsl-ccs-web.ps1`
- 复用：`scripts/get-local-wsl-publish-fingerprint.ps1`

- [ ] **步骤 1：新增脚本参数**

新增：

- `-SkipFrontendBuild`
- `-NoCache`

`-SkipFrontendBuild` 只应在显式传入时跳过自动 Docker 前端快照刷新。`-NoCache` 用于在后续构建路径中关闭缓存辅助行为。

- [ ] **步骤 2：持久化并比较指纹元数据**

将上一次成功的前端指纹保存到：

```text
.run/build-cache/meta/frontend-dist.fingerprint
```

在执行 Docker 构建前，计算当前指纹；满足以下任一条件时，标记 Docker 前端快照需要刷新：

- 指纹发生变化
- `.run/build-cache/frontend-dist/index.html` 缺失
- 未显式跳过前端构建，且指纹元数据缺失

Docker 构建成功并导出 `frontend-dist` 快照后，覆盖写入最新指纹元数据。

- [ ] **步骤 3：导出 Docker 前端产物快照**

当需要刷新时，执行 Docker `frontend-dist` target 导出，把快照写入：

```text
.run/build-cache/frontend-dist
```

served-build 校验必须用该快照和实际 Web 响应比较入口 JS/CSS。

- [ ] **步骤 4：验证“刷新 / 不刷新”行为**

连续运行两次：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro> -NoStart -SkipHealthCheck
```

预期：

- 第一次会生成元数据，并在需要时导出 Docker 前端快照
- 第二次检测到前端输入未变化，跳过快照导出

`-SkipBuild` 只应用于镜像和前端快照都已经新鲜的检查路径；如果快照缺失或过期，脚本应直接失败，而不是暗中触发 Docker 构建。

- [ ] **步骤 5：提交自动前端快照管理**

```powershell
git add scripts/publish-local-wsl-ccs-web.ps1
git commit -m "feat: auto-manage Docker frontend snapshot for WSL publish"
```

### 任务 4：为 Dockerfile 增加 BuildKit 友好的缓存支持

**文件：**
- 修改：`Dockerfile.web`

- [ ] **步骤 1：补齐 cache mount 所需的 syntax / build 特性**

保留 `# syntax=docker/dockerfile:1`，或仅在目标环境确实需要时升级为兼容 BuildKit cache mount 的语法声明。

- [ ] **步骤 2：增加 pnpm cache mount**

更新前端阶段的 `pnpm install --frozen-lockfile`，让其使用 pnpm store 对应的 cache mount。

- [ ] **步骤 3：增加 cargo cache mount**

更新 Rust 构建步骤，增加以下 cache mount：

- cargo registry
- cargo git
- cargo target

同时确保 release 二进制的输出路径保持不变。

- [ ] **步骤 4：执行一次构建验证**

运行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro> -NoStart -SkipHealthCheck
```

预期：

- 镜像构建成功
- cache mount 语法被正确接受
- 本步骤不要求容器健康检查

- [ ] **步骤 5：提交 Dockerfile 缓存改动**

```powershell
git add Dockerfile.web
git commit -m "feat: add build cache mounts for local WSL publish"
```

### 任务 5：让 Docker 构建走项目内缓存路径

**文件：**
- 修改：`scripts/publish-local-wsl-ccs-web.ps1`

- [ ] **步骤 1：增加 BuildKit 缓存路径转换**

将 `.run/build-cache/docker` 转换成适合 WSL / Docker / BuildKit 使用的路径。

- [ ] **步骤 2：更新构建调用路径**

把当前普通构建调用替换为带缓存感知的构建路径，要求：

- 优先使用 BuildKit
- 使用 `.run/build-cache/docker` 下的本地 cache import / export
- 在传入 `-NoCache` 时走强制冷构建路径

如果完整接入 `docker buildx build` 对现有 compose 流程过于侵入，则实现一个和当前服务 / 镜像流程兼容、且最小可靠的缓存方案。

- [ ] **步骤 3：验证热缓存行为**

连续运行两次：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro> -NoStart -SkipHealthCheck
```

预期：

- 两次都成功
- 第二次比第一次复用更多缓存工作

- [ ] **步骤 4：提交缓存感知的构建调用**

```powershell
git add scripts/publish-local-wsl-ccs-web.ps1
git commit -m "feat: use project-local docker cache for WSL publish"
```

### 任务 6：端到端发版验证

**文件：**
- 如有需要再修改：`scripts/publish-local-wsl-ccs-web.ps1`

- [ ] **步骤 1：执行一次完整的冷路径发版验证**

如果可行，清理这次新增的项目内缓存目录，或直接使用 `-NoCache`，然后运行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro> -NoCache
```

预期：

- 镜像构建成功
- 容器成功启动
- Web / API / Proxy 健康检查通过
- served build 与 Docker 前端快照一致

- [ ] **步骤 2：执行一次完整的热缓存发版验证**

运行：

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-local-wsl-ccs-web.ps1 -Distro <wsl-distro>
```

预期：

- 发版再次成功
- 健康检查继续通过
- served build 与 Docker 前端快照一致
- 热路径在日志中可观察到更快或更明显的缓存复用

- [ ] **步骤 3：复核 diff 和受影响文件**

运行：

```powershell
rtk git diff -- scripts/publish-local-wsl-ccs-web.ps1 Dockerfile.web .gitignore scripts/get-local-wsl-publish-fingerprint.ps1
rtk git status --short
```

预期：

- 只有预期文件发生改动
- 没有缓存产物或运行日志被纳入暂存区

- [ ] **步骤 4：提交经验证的发版优化**

```powershell
git add scripts/publish-local-wsl-ccs-web.ps1 Dockerfile.web .gitignore scripts/get-local-wsl-publish-fingerprint.ps1
git commit -m "feat: speed up local WSL publish with project-local caches"
```
