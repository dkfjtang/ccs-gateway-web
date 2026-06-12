# 2026-06-12 - 本地 WSL ccs-web 发布缓存与自动发版归结

## 关键信息

- 本轮目标是优化本地 WSL `ccs-web` 一键发版效率，并保持本地 WSL 容器发布边界：只处理 `docker-compose.ccs-web.yml` 中的 `ccs-gateway-web` 服务，不触碰桌面版 CC Switch。
- 新增一键发布脚本：`scripts/publish-local-wsl-ccs-web.ps1`。
- 新增发布指纹脚本：`scripts/get-local-wsl-publish-fingerprint.ps1`。
- `Dockerfile.web` 已配合发布缓存调整，包含前端构建、Rust 构建缓存和 `frontend-dist` 导出 stage。
- 发布设计文档和执行计划已用中文落地：
  - `docs/superpowers/specs/2026-06-12-local-wsl-publish-cache-design.md`
  - `docs/superpowers/plans/2026-06-12-local-wsl-publish-cache.md`

## 重要决策

- 构建缓存默认放在 ignored 的 `.run/build-cache/` 下，避免把本机运行证据写入仓库。
- Docker BuildKit 使用本地 cache：`--cache-from/--cache-to type=local`。
- 前端一致性校验以 Docker `frontend-dist` stage 导出的快照为准，不再依赖 Windows 工作区里的 `dist`。
- served-build 校验同时比较入口 JS 与 CSS，避免只校验脚本导致样式构件漂移。
- 构建失败不允许 fallback 到旧镜像继续发布。
- `-SkipBuild` 只允许复用已存在且指纹匹配的 Docker 前端快照；快照缺失或过期时直接失败，不自动触发 buildx。
- 代理和镜像源 override 只允许命令级临时配置，脚本输出必须脱敏，不写入 tracked 配置。
- PowerShell 到 bash 的动态参数使用统一转义函数，避免路径、空格和特殊字符导致命令注入或解析错误。

## 验证结果

- 已完成一次本机自动发版验证。
- 验证覆盖：Docker 构建、容器重建、Web UI 健康检查、API health、代理端口连通性、served-build JS/CSS 一致性。
- 成功证据存放在 ignored 本地日志目录：`.run/local-wsl-publish/`。
- 公开归档不保存原始日志、容器 ID、本机代理端点、宿主路径或镜像 digest。

## 复审结论

- 已按审核视角修复 `-SkipBuild` 语义、bash 参数转义、指纹输入覆盖、Dockerfile syntax directive、代理/镜像输出脱敏、Docker 前端快照命名和文档同步问题。
- 后续再做 review 时，重点检查：
  - `-SkipBuild` 是否仍然不会隐式构建。
  - 指纹脚本是否覆盖所有会影响前端产物的输入。
  - 发布脚本输出是否不泄露本机代理、镜像源私密信息或容器运行细节。
  - Docker `frontend-dist` 快照与线上 served-build 校验是否仍保持一致。

## 后续事项

- 如果需要提交，只 stage 本轮相关文件，避免带入仓库中已有的无关修改。
- 如果外部镜像源限流，可以继续使用命令级镜像 override；不要把临时镜像源写入仓库配置。
- 如果后续继续优化发版速度，优先评估缓存命中率、Docker buildx builder 复用、pnpm store cache 和 cargo target cache，不改变本地 WSL 发布边界。

## 丢弃噪音

- 未保存原始发版日志、长命令输出、容器 ID、运行态私有路径、代理端点和本机环境细节。
- 未保存重复的中间状态更新和已被后续修复覆盖的临时失败细节。
