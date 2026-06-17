## 2026-06-17 - CCS auth vault flow

### Key Information
- 目标改造成功闭环：Edge 扩展读取已登录站点的 `localStorage`、`sessionStorage` 和 Cookie，保存为站点 JSON，再同步到 CCS Web 后端持久化认证库。
- 扩展同步端点固定为 `/api/auth-vault/tokens`，仅允许配置 CCS 服务地址和端口。
- 运行态验证结果：`GET /api/auth-vault/tokens/summary` 在完成发布后返回 `401`，不再是 `404`，说明新后端路由已上线。
- usage 替换链新增固定占位符 `{{authToken}}` 和 `{{cookieHeader}}`，并保留旧命名占位符兼容。

### Important Information
- 新增后端文件：`crates/server/src/api/auth_vault.rs`
- 新增运行时替换文件：`src-tauri/src/usage_token_vault.rs`
- 已补测试：
  - 站点固定占位符同站点替换
  - 跨站不替换
  - 后端 summary 不回显明文 token / cookie
- 发布过程中遇到 WSL relay 活跃连接阻塞，先做 relay repair，再重新构建发布，最终成功。

### Project Information
- 当前本地发布目标仍是 `ccs-gateway-web` 的 WSL / Docker 发布链。
- 发布脚本对活跃 `wslrelay` 连接敏感，必要时需要先 repair，再重新发布。
- server 正式构建中应使用 `cc_switch_core::get_app_config_dir()`，不要在 `crates/server` 里直接引用 Tauri 主包的 `cc_switch`。

### Follow-ups
- Edge 扩展需要重新加载，确保 `cookies` 权限生效。
- 若后续继续扩展站点识别逻辑，优先保持 host 精确匹配，避免跨站串用。

### Dropped Noise
- 现场构建中的冗长 warning、relay 端口滚动日志、以及截图中的明文预览内容不保留。
