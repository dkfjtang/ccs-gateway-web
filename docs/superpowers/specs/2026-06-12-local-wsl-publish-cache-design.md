# 本机 WSL 发版缓存优化设计

## 目标

优化 `ccs-gateway-web` 的本机 WSL 发版流程，让重复发版，尤其是小改动后的增量发版更快，同时保持当前正确性门禁不变。优化必须限定在项目内的忽略目录，避免引入机器级全局构建污染。

## 范围

本设计覆盖：

- `scripts/publish-local-wsl-ccs-web.ps1`
- `Dockerfile.web`
- Docker 前端构建产物快照行为
- 本机 WSL 发版使用的项目内 Docker/BuildKit 缓存行为

本设计不覆盖：

- 全局 Docker daemon 配置
- 全局 pnpm/cargo 配置
- 从 `pnpm` 切换到 `yarn`
- 本机 WSL `ccs-gateway-web` 之外的生产发版流程

## 约束

- 缓存产物必须放在项目内、被忽略的路径下。
- 正常发版流程应尽量自动化，尽量少依赖操作者手工传参。
- 现有健康检查和 served-build 一致性校验必须保留。
- 缓存层必须可清理；删除缓存后应能安全回退到正确的冷构建。
- 本机 WSL 发版仍然只能面向 `docker-compose.ccs-web.yml`，不得影响桌面版 CC Switch 安装。

## 当前痛点

当前发版路径在重复本地发版时会重复做过多工作：

1. 前端依赖可能被重复下载或重复物化。
2. Rust 依赖和 release 构建结果在多次本地发版之间复用不足。
3. Docker 构建层没有显式把项目内缓存状态持久化到仓库目录下。
4. 旧脚本默认假设工作区 `dist` 已经是最新；一旦 `dist` 过期，就会在长时间构建后才在最后的 served-build 校验阶段失败。

## 期望结果

优化后应满足：

- 无源码变化的重复发版明显快于当前路径。
- 仅前端小改动时，不再重复下载依赖。
- 仅 Rust 小改动时，能够复用 cargo registry/git 缓存，以及尽可能多的增量或 release 构建结果。
- 发版脚本能够自动导出 Docker 前端构建产物快照，并用该快照做 served-build 一致性校验。
- 默认仍保留 Web/API/Proxy 健康检查和 served-build 一致性校验。

## 缓存布局

所有新增缓存统一放在：

`<repo-root>\.run\build-cache\`

子目录包括：

- `frontend-dist`
- `docker`
- `meta`

用途：

- `frontend-dist`：从 Docker `frontend-dist` stage 导出的前端产物快照，用于 served-build 校验
- `docker`：BuildKit 本地 cache import/export 目录，包含 Dockerfile 内 pnpm/cargo cache mount 的可复用状态
- `meta`：构建指纹和脚本元数据

这些目录都只是加速层，不是发版产物，也不是事实来源。

## 构建策略

### 1. 前端依赖缓存

继续使用 `pnpm`。

前端构建应在 Docker 前端 stage 内执行，并通过 BuildKit cache mount 复用 pnpm store，避免重复构建时继续下载依赖。发布校验使用 Docker 导出的 `frontend-dist` 快照，不依赖 Windows 工作区的 `node_modules` 或 `dist`。

### 2. Rust 依赖与构建缓存

Rust 构建步骤应使用以下 cache mount：

- cargo registry
- cargo git
- cargo target

目标不是追求所有容器生命周期下的完美增量语义，而是让本机重复发版场景有稳定、可见的缓存收益。

### 3. Docker 构建缓存

本机 WSL 发版应显式使用以 `.run/build-cache/docker` 为根的 BuildKit 本地缓存 import/export。这样缓存可见、可清理，而不是只依赖 Docker 自己不透明的内部缓存。

### 4. 自动管理 Docker 前端产物快照

发版脚本不应再依赖操作者手工先执行 `pnpm build:web`，也不应依赖工作区 `dist` 的新旧状态。

脚本应改为：

- 判断前端输入是否变化
- 有变化时在 Docker 构建后导出 `frontend-dist` 快照
- 无变化且快照存在时跳过快照导出

现有 served-build 一致性校验继续作为最后一道正确性门禁。

## 脚本行为

正常执行 `publish-local-wsl-ccs-web.ps1` 时应：

1. 确保所有缓存目录存在。
2. 计算或读取前端输入指纹。
3. 判断 Docker 前端产物快照是否需要刷新。
4. 使用项目内缓存目录执行 Docker 构建。
5. 在需要时导出 Docker `frontend-dist` stage 到项目内快照目录。
6. 重建并启动目标容器。
7. 执行 Web/API/Proxy 健康检查。
8. 校验服务端前端资源与 Docker 导出的前端快照一致。
9. 将本地日志和元数据写入被忽略的 `.run` 路径。

## 操作入口

默认流程应自动完成。

现有开关继续保留：

- `-SkipBuild`
- `-NoStart`
- `-SkipHealthCheck`

建议新增：

- `-NoCache`：用于排查缓存问题时强制冷构建
- `-SkipFrontendBuild`：只有在操作者明确知道 Docker 前端快照已经最新时才跳过自动快照刷新

`-SkipBuild` 不应隐式触发 Docker 构建或前端快照刷新；如果快照缺失或过期，应直接失败并提示去掉 `-SkipBuild` 后重跑。

默认路径不应依赖这些开关。

## Dockerfile 调整原则

`Dockerfile.web` 应在不改变最终运行语义的前提下提升缓存命中率：

- 保留多阶段结构
- 保留 lockfile 优先的依赖安装顺序
- 为 pnpm 和 cargo 增加 BuildKit cache mount
- 尽可能减少源码小改动导致的不必要缓存失效

本设计不要求重写整个 Dockerfile，只要求通过合理的层次拆分和 cache mount 提升重复本地发版速度。

## 指纹规则

前端是否需要重建，应基于前端相关输入的稳定 hash/fingerprint 判断，至少包括：

- `src/**`
- `package.json`
- `pnpm-lock.yaml`
- `pnpm-workspace.yaml`
- `vite.config.ts`
- `tailwind.config.cjs`
- 其他直接影响前端产物的项目内配置文件

指纹文件放在 `.run/build-cache/meta` 下。

规则：

- 指纹变化时，必须刷新 Docker 前端产物快照
- 指纹未变化且 `frontend-dist/index.html` 存在时，可复用已有快照

## 失败模型

优化后的流程必须以安全失败为原则：

- 缓存目录缺失：重建后继续
- 缓存被删或过期：回退到冷构建，但结果仍正确
- BuildKit 缓存不支持或配置异常：要么给出明确错误，要么安全回退到普通构建
- 前端快照过期：发版前自动刷新
- served/snapshot mismatch：仍然让发版失败，不能掩盖问题

## 验证计划

实现后至少要证明：

1. 空缓存下冷发版仍然成功。
2. 无相关源码变化时，第二次发版更快且健康检查继续通过。
3. 前端小改动不会重复下载依赖。
4. Rust 小改动能够复用 cargo 缓存，减少重复下载。
5. Docker 前端产物快照能消除之前那种“Windows 本地 dist 与容器内前端产物不一致”的常规操作失败。
6. `-NoCache` 能用于强制冷构建排障。

## 风险

- 指纹范围过宽会导致不必要的前端快照刷新。
- 指纹范围过窄会让旧前端快照被误复用，不过 served-build 校验仍是最后兜底。
- cache mount 虽然能提速，但也会增加脚本复杂度，因此路径必须显式且易清理。
- Rust release 构建缓存需要谨慎设计，确保能提速，但不会变成“只在这台机器上偶然可用”的黑盒行为。

## 建议

先实现项目内统一缓存路径、Docker 前端产物快照管理、以及 BuildKit/cargo/pnpm 缓存接入。不要一开始就加入更激进的“完全跳过 docker build”启发式，等缓存命中行为稳定且可度量后再考虑进一步激进优化。
