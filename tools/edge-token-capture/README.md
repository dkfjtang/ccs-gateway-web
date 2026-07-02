# Edge 登录态令牌捕获工具

这个未打包 Edge 扩展用于读取当前活动页面的 `localStorage`、`sessionStorage` 和浏览器 Cookie，并识别疑似令牌或会话 Cookie。

## 在 Edge 中加载

1. 打开 `edge://extensions`
2. 开启 **开发人员模式**
3. 点击 **加载解压缩的扩展**
4. 选择目录：`tools/edge-token-capture`

## 使用

1. 确认 CCS Web 服务已经运行，默认地址是 `http://127.0.0.1:17666`。
2. 打开已经登录的目标站点。
3. 点击这个扩展。
4. 如端口不是 `17666`，在 **CCS 服务地址** 中修改地址和端口，例如 `http://127.0.0.1:17667`。如果 CCS Web 部署在非本机，请填写 HTTPS origin，例如 `https://ccs.example.com`，并先在同一 origin 的 CCS Web 中完成登录。
5. 远端 CCS Web 需要先在 **设置 → 高级 → Auth Vault 临时接收** 打开接收开关。接收窗口默认 5 分钟，成功接收一次后会自动关闭。
6. 点击 **读取并保存并同步**。
7. 确认候选认证值来源和脱敏预览。该动作会同时读取当前页面、保存到扩展本地认证库，并写入 CCS Web 后端的持久化认证库。
8. 重点查看输出里的 `selectedAuthToken`：用 `source`、`length`、`prefix16`、`suffix12` 和 `jwt.expiresAt` 对照浏览器 Network 面板里真实请求的 `Authorization: Bearer ...`，确认扩展选中的 `{{authToken}}` 是否就是你以前手工复制的那个值。
   这些字段仍属于认证调试信息，不要截图、提交或粘贴到公开 issue / 文档。

弹窗里不会展示完整认证值，只显示来源、长度和脱敏预览。最新读取结果和保存的认证值暂存在扩展自己的本地存储中。

同步路径固定为 `/api/auth-vault/tokens`，扩展只允许配置 CCS Web 服务 origin，不开放自定义 API 路径。非本地服务地址必须使用 `https://`，同步时会使用浏览器对该 origin 的正常登录 Cookie；如果扩展能读取 CCS 登录 Cookie，会同时通过 Auth Vault 专用同步头提交。本地回环地址仍使用扩展桥接的 `X-CCS-Session`。远端接收窗口关闭时，同步会被拒绝，需要手工打开后重试。

## 在脚本中使用

推荐优先使用固定占位符。Bearer 写法是：

```js
Authorization: "Bearer {{authToken}}";
```

Cookie 写法是：

```js
Cookie: "{{cookieHeader}}";
```

CCS 会按请求 URL 的 host 自动匹配保存的站点 JSON，只替换同站点的固定占位符。

兼容旧的命名占位符。如果扩展保存出的名称是 `example_com__auth_token`，Bearer 写法是：

```js
Authorization: "Bearer {{example_com__auth_token}}";
```

如果扩展保存出的名称是 `example_com__session`，Cookie 写法是：

```js
Cookie: "session={{example_com__session}}";
```
