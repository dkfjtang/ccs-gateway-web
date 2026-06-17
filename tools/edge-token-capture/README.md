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
4. 如端口不是 `17666`，在 **CCS 服务地址** 中修改地址和端口，例如 `http://127.0.0.1:17667`。
5. 点击 **读取并保存并同步**。
6. 确认候选认证值来源和脱敏预览。该动作会同时读取当前页面、保存到扩展本地认证库，并写入 CCS Web 后端的持久化认证库。

弹窗里不会展示完整认证值，只显示来源、长度和脱敏预览。最新读取结果和保存的认证值暂存在扩展自己的本地存储中。

同步路径固定为 `/api/auth-vault/tokens`，扩展只允许配置服务地址和端口，不开放自定义 API 路径。

## 在脚本中使用

推荐优先使用固定占位符。Bearer 写法是：

```js
Authorization: "Bearer {{authToken}}"
```

Cookie 写法是：

```js
Cookie: "{{cookieHeader}}"
```

CCS 会按请求 URL 的 host 自动匹配保存的站点 JSON，只替换同站点的固定占位符。

兼容旧的命名占位符。如果扩展保存出的名称是 `sub2_congmingai_com__auth_token`，Bearer 写法是：

```js
Authorization: "Bearer {{sub2_congmingai_com__auth_token}}"
```

如果扩展保存出的名称是 `sub2_congmingai_com__session`，Cookie 写法是：

```js
Cookie: "session={{sub2_congmingai_com__session}}"
```
