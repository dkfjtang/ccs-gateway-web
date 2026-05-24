# CC-Switch WebSocket + JSON-RPC 架构设计文档

**版本**: 1.0
**日期**: 2025-12-03
**状态**: 设计文档
**前置文档**: [WEB_MIGRATION_ARCHITECTURE.md](./WEB_MIGRATION_ARCHITECTURE.md)

---

## 概述

本文档描述了 CC-Switch Web 模式的传输层升级方案：从 HTTP REST 迁移到 **WebSocket + JSON-RPC 2.0** 协议。

### 核心目标

1. **统一通信模型**: 单一 WebSocket 连接处理所有命令调用和事件推送
2. **语义对齐**: 让 Web 模式的通信语义与 Tauri IPC 保持一致
3. **实时推送**: 支持服务器主动推送事件，替代轮询
4. **最小改动**: 前端 API 保持不变 (`invoke`/`listen`)
5. **优雅降级**: 保持 HTTP 端点作为备用方案

### 为什么选择 WebSocket + JSON-RPC？

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **HTTP REST** | 简单、无状态、易调试 | 无实时推送，需轮询 | 当前方案 |
| **HTTP + SSE** | 简单、自动重连 | 单向推送，需双端点 | 折中方案 |
| **WebSocket + JSON-RPC** | 双向、低延迟、语义统一 | 连接管理复杂 | **推荐方案** ✓ |
| **gRPC-Web** | 类型安全、高性能 | 依赖重、工具链复杂 | 过度设计 |

**选择理由**:
- WebSocket 的双向通信天然匹配 Tauri IPC 的 `invoke`/`listen` 模型
- JSON-RPC 2.0 是成熟的标准协议，简单且易于调试
- 单一连接减少开销，适合实时交互场景

---

## 1. 整体架构

### 1.1 通信模型对比

#### Tauri IPC 模式
```
React Component
    ↓
invoke("get_providers", args)
    ↓
Tauri IPC Bridge (window.__TAURI__)
    ↓
Rust Command Handler
    ↓
Response
```

#### WebSocket + JSON-RPC 模式
```
React Component
    ↓
invoke("get_providers", args)
    ↓
WebSocket Transport
    ↓
JSON-RPC Request { method: "get_providers", params: args }
    ↓
Axum WebSocket Handler
    ↓
dispatch_command()
    ↓
JSON-RPC Response { result: data }
```

### 1.2 三层协议栈

```
┌─────────────────────────────────────────────────────────────┐
│              Application Layer (TypeScript)                 │
│  invoke("command", args) / listen("event", handler)        │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────┴──────────────────────────────────────────┐
│            JSON-RPC 2.0 Protocol Layer                      │
│  Request:  { jsonrpc, id, method, params }                 │
│  Response: { jsonrpc, id, result/error }                   │
│  Notify:   { jsonrpc, method, params }                     │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────┴──────────────────────────────────────────┐
│              Transport Layer (WebSocket)                    │
│  Full-duplex, persistent, binary/text frames              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. JSON-RPC 2.0 协议规范

### 2.1 命令调用 (Request/Response)

#### 2.1.1 请求格式

```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "method": "get_providers",
  "params": {
    "app": "claude"
  }
}
```

**字段说明**:
- `jsonrpc`: 固定为 `"2.0"`
- `id`: 请求唯一标识符（字符串或数字），用于匹配响应
- `method`: 命令名称，对应现有 Tauri 命令
- `params`: 命令参数（对象或数组），对应现有 `payload`

#### 2.1.2 成功响应

```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "result": [
    {
      "id": "uuid-1234",
      "name": "DeepSeek",
      "baseUrl": "https://api.deepseek.com"
    }
  ]
}
```

**字段说明**:
- `id`: 匹配请求的 `id`
- `result`: 命令执行结果（任意 JSON 值）

#### 2.1.3 错误响应

```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "error": {
    "code": -32001,
    "message": "Provider not found",
    "data": {
      "appError": "ProviderNotFound",
      "details": "No provider with id 'uuid-1234'"
    }
  }
}
```

**错误码规范**:
| 代码 | 含义 | 映射 |
|------|------|------|
| `-32700` | Parse error | JSON 解析失败 |
| `-32600` | Invalid Request | 请求格式错误 |
| `-32601` | Method not found | 未知命令 |
| `-32602` | Invalid params | 参数验证失败 |
| `-32603` | Internal error | 内部错误 |
| `-32001` | Application error | 业务逻辑错误（自定义） |

### 2.2 事件推送 (Notification)

#### 2.2.1 订阅事件

**请求** (客户端 → 服务器):
```json
{
  "jsonrpc": "2.0",
  "id": "sub-1",
  "method": "event.subscribe",
  "params": {
    "event": "provider_changed"
  }
}
```

**响应** (服务器 → 客户端):
```json
{
  "jsonrpc": "2.0",
  "id": "sub-1",
  "result": { "ok": true }
}
```

#### 2.2.2 取消订阅

```json
{
  "jsonrpc": "2.0",
  "id": "unsub-1",
  "method": "event.unsubscribe",
  "params": {
    "event": "provider_changed"
  }
}
```

#### 2.2.3 事件推送

**服务器推送** (无 `id` 字段):
```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "name": "provider_changed",
    "payload": {
      "app": "claude",
      "providerId": "uuid-1234",
      "action": "switched"
    }
  }
}
```

**特点**:
- 无 `id` 字段（符合 JSON-RPC notification 定义）
- `name`: 事件名称，对应 Tauri 事件
- `payload`: 事件数据（任意 JSON）

### 2.3 心跳保活 (可选)

**Ping** (客户端 → 服务器):
```json
{
  "jsonrpc": "2.0",
  "method": "ping"
}
```

**Pong** (服务器 → 客户端):
```json
{
  "jsonrpc": "2.0",
  "method": "pong"
}
```

或使用 WebSocket 原生 Ping/Pong 帧。

---

## 3. 后端实现 (Rust/Axum)

### 3.1 项目结构

```
crates/server/src/
├── main.rs              # 应用入口
├── api/
│   ├── mod.rs
│   ├── invoke.rs        # HTTP invoke 端点 (保留)
│   ├── ws.rs            # WebSocket 端点 (新增)
│   └── dispatch.rs      # 命令分发逻辑 (提取)
├── state.rs             # ServerState
├── events.rs            # 事件总线 (新增)
└── rpc/                 # JSON-RPC 类型定义 (新增)
    ├── mod.rs
    ├── request.rs
    ├── response.rs
    └── error.rs
```

### 3.2 依赖添加

```toml
# crates/server/Cargo.toml
[dependencies]
axum = { version = "0.7", features = ["ws"] }
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.21"
futures = "0.3"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
cc-switch-core = { path = "../core" }
```

### 3.3 JSON-RPC 类型定义

**`crates/server/src/rpc/request.rs`**:
```rust
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub struct RpcRequest {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

impl RpcRequest {
    pub fn is_notification(&self) -> bool {
        self.id.is_none()
    }
}
```

**`crates/server/src/rpc/response.rs`**:
```rust
use serde::Serialize;
use serde_json::Value;
use super::error::RpcError;

#[derive(Debug, Serialize)]
pub struct RpcResponse {
    pub jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

impl RpcResponse {
    pub fn success(id: Value, result: Value) -> Self {
        Self {
            jsonrpc: "2.0",
            id: Some(id),
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, error: RpcError) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: None,
            error: Some(error),
        }
    }

    pub fn notification(method: &str, params: Value) -> Value {
        serde_json::json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        })
    }
}
```

**`crates/server/src/rpc/error.rs`**:
```rust
use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Serialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl RpcError {
    pub fn parse_error() -> Self {
        Self {
            code: -32700,
            message: "Parse error".into(),
            data: None,
        }
    }

    pub fn invalid_request(msg: impl Into<String>) -> Self {
        Self {
            code: -32600,
            message: msg.into(),
            data: None,
        }
    }

    pub fn method_not_found(method: &str) -> Self {
        Self {
            code: -32601,
            message: format!("Method not found: {}", method),
            data: None,
        }
    }

    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self {
            code: -32602,
            message: msg.into(),
            data: None,
        }
    }

    pub fn internal_error(msg: impl Into<String>) -> Self {
        Self {
            code: -32603,
            message: msg.into(),
            data: None,
        }
    }

    pub fn app_error(err: &crate::error::AppError) -> Self {
        Self {
            code: -32001,
            message: err.to_string(),
            data: Some(serde_json::json!({
                "appError": format!("{:?}", err)
            })),
        }
    }
}
```

### 3.4 事件总线

**`crates/server/src/events.rs`**:
```rust
use serde_json::Value;
use tokio::sync::broadcast;

#[derive(Clone, Debug)]
pub struct ServerEvent {
    pub name: String,
    pub payload: Value,
}

pub type EventSender = broadcast::Sender<ServerEvent>;
pub type EventReceiver = broadcast::Receiver<ServerEvent>;

pub fn create_event_bus(capacity: usize) -> EventSender {
    let (tx, _) = broadcast::channel(capacity);
    tx
}

// 使用示例：
// state.event_bus.send(ServerEvent {
//     name: "provider_changed".into(),
//     payload: serde_json::json!({ "providerId": id }),
// }).ok();
```

### 3.5 命令分发逻辑提取

**`crates/server/src/api/dispatch.rs`**:
```rust
use std::sync::Arc;
use serde_json::Value;
use cc_switch_core::CoreAppState;
use crate::error::AppError;

pub async fn dispatch_command(
    state: &Arc<CoreAppState>,
    method: &str,
    params: &Value,
) -> Result<Value, AppError> {
    match method {
        // Provider commands
        "get_providers" => {
            let app: String = parse_param(params, "app")?;
            let providers = state.provider_service.get_providers(&app)?;
            Ok(serde_json::to_value(providers)?)
        }
        "add_provider" => {
            let app: String = parse_param(params, "app")?;
            let provider: Provider = serde_json::from_value(
                params.get("provider").cloned().ok_or(
                    AppError::InvalidInput("Missing 'provider'".into())
                )?
            )?;
            state.provider_service.add_provider(&app, provider)?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "switch_provider" => {
            let app: String = parse_param(params, "app")?;
            let provider_id: String = parse_param(params, "providerId")?;
            state.provider_service.switch_provider(&app, &provider_id)?;
            Ok(serde_json::json!({ "ok": true }))
        }

        // MCP commands
        "get_mcp_servers" => {
            let app: String = parse_param(params, "app")?;
            let servers = state.mcp_service.get_servers(&app)?;
            Ok(serde_json::to_value(servers)?)
        }

        // ... 其他命令

        _ => Err(AppError::InvalidInput(format!("Unknown command: {}", method)))
    }
}

fn parse_param<T: serde::de::DeserializeOwned>(
    params: &Value,
    key: &str,
) -> Result<T, AppError> {
    params
        .get(key)
        .ok_or_else(|| AppError::InvalidInput(format!("Missing parameter: {}", key)))?
        .clone()
        .try_into()
        .map_err(|_| AppError::InvalidInput(format!("Invalid parameter type: {}", key)))
}
```

### 3.6 WebSocket 端点实现

**`crates/server/src/api/ws.rs`**:
```rust
use std::collections::HashSet;
use std::sync::Arc;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::http::StatusCode;
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::Value;

use crate::rpc::{RpcRequest, RpcResponse, RpcError};
use crate::state::ServerState;
use crate::api::dispatch::dispatch_command;

#[derive(Deserialize)]
pub struct WsAuthQuery {
    auth: Option<String>,
}

pub async fn upgrade_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<ServerState>>,
    Query(query): Query<WsAuthQuery>,
) -> impl IntoResponse {
    // 验证 token
    if let Some(expected_token) = &state.auth_token {
        match query.auth.as_deref() {
            Some(token) if token == expected_token => {}
            _ => return StatusCode::UNAUTHORIZED.into_response(),
        }
    }

    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<ServerState>) {
    let (mut sender, mut receiver) = socket.split();
    let mut subscriptions: HashSet<String> = HashSet::new();

    // 事件推送任务
    let mut event_rx = state.event_bus.subscribe();
    let mut send_task = tokio::spawn(async move {
        while let Ok(event) = event_rx.recv().await {
            if subscriptions.contains(&event.name) {
                let notification = RpcResponse::notification(
                    "event",
                    serde_json::json!({
                        "name": event.name,
                        "payload": event.payload
                    })
                );
                let text = serde_json::to_string(&notification).unwrap();
                if sender.send(Message::Text(text)).await.is_err() {
                    break;
                }
            }
        }
    });

    // 消息接收任务
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if let Message::Text(text) = msg {
                let response = handle_message(&state, &mut subscriptions, &text).await;
                if let Some(resp_text) = response {
                    // 发送响应 (需要跨任务通信，这里简化处理)
                    // 实际实现需要使用 mpsc channel
                }
            }
        }
    });

    // 等待任意任务结束
    tokio::select! {
        _ = (&mut send_task) => recv_task.abort(),
        _ = (&mut recv_task) => send_task.abort(),
    }
}

async fn handle_message(
    state: &Arc<ServerState>,
    subscriptions: &mut HashSet<String>,
    text: &str,
) -> Option<String> {
    let request: RpcRequest = match serde_json::from_str(text) {
        Ok(req) => req,
        Err(_) => {
            let err = RpcResponse::error(None, RpcError::parse_error());
            return Some(serde_json::to_string(&err).unwrap());
        }
    };

    // Notification (无需响应)
    if request.is_notification() {
        handle_notification(&request);
        return None;
    }

    let id = request.id.clone().unwrap();

    // 系统命令
    let response = match request.method.as_str() {
        "event.subscribe" => {
            let event = request.params.get("event")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            subscriptions.insert(event.to_string());
            RpcResponse::success(id, serde_json::json!({ "ok": true }))
        }
        "event.unsubscribe" => {
            let event = request.params.get("event")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            subscriptions.remove(event);
            RpcResponse::success(id, serde_json::json!({ "ok": true }))
        }
        "ping" => {
            RpcResponse::success(id, serde_json::json!({ "pong": true }))
        }
        _ => {
            // 业务命令
            match dispatch_command(&state.core, &request.method, &request.params).await {
                Ok(result) => RpcResponse::success(id, result),
                Err(err) => RpcResponse::error(Some(id), RpcError::app_error(&err)),
            }
        }
    };

    Some(serde_json::to_string(&response).unwrap())
}

fn handle_notification(request: &RpcRequest) {
    match request.method.as_str() {
        "ping" => { /* 忽略或记录 */ }
        _ => {
            tracing::debug!("Received notification: {}", request.method);
        }
    }
}
```

**注意**: 上述代码为简化示例，实际实现需要使用 `tokio::sync::mpsc` 在接收和发送任务间传递消息。

### 3.7 路由注册

**`crates/server/src/main.rs`**:
```rust
use axum::{Router, routing::{get, post}};
use crate::api::{invoke, ws};
use crate::events::create_event_bus;

#[tokio::main]
async fn main() {
    let core_state = CoreAppState::new().await.unwrap();
    let event_bus = create_event_bus(100);

    let server_state = Arc::new(ServerState {
        core: Arc::new(core_state),
        auth_token: std::env::var("CC_SWITCH_AUTH_TOKEN").ok(),
        event_bus,
    });

    let api_routes = Router::new()
        .route("/invoke", post(invoke::handler))  // HTTP 端点保留
        .route("/ws", get(ws::upgrade_handler))   // WebSocket 端点
        .with_state(server_state);

    let app = Router::new()
        .nest("/api", api_routes);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3160").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
```

---

## 4. 前端实现 (TypeScript/React)

### 4.1 WebSocket Transport

**`src/lib/transport/wsTransport.ts`**:
```typescript
import type { ApiTransport, UnlistenFn } from "./types";

// JSON-RPC 类型定义
interface RpcRequest {
  jsonrpc: "2.0";
  id?: string | number;
  method: string;
  params?: unknown;
}

interface RpcResponse {
  jsonrpc: "2.0";
  id?: string | number;
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
}

interface RpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
}

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
};

class JsonRpcWebSocketClient {
  private socket?: WebSocket;
  private nextId = 1;
  private pendingRequests = new Map<string, PendingRequest>();
  private eventHandlers = new Map<string, Set<(payload: unknown) => void>>();
  private connectPromise?: Promise<void>;
  private reconnectTimer?: number;
  private closedByUser = false;
  private reconnectDelay = 1000;
  private maxReconnectDelay = 30000;

  constructor(private url: string) {}

  async connect(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN) return;
    if (this.connectPromise) return this.connectPromise;

    this.connectPromise = new Promise<void>((resolve, reject) => {
      const socket = new WebSocket(this.url);
      this.socket = socket;

      socket.onopen = () => {
        console.log("[WS] Connected");
        this.reconnectDelay = 1000; // 重置延迟
        this.setupListeners(socket);
        resolve();
      };

      socket.onerror = (ev) => {
        console.error("[WS] Connection error", ev);
        reject(new Error("WebSocket connection failed"));
      };

      socket.onclose = () => {
        console.log("[WS] Connection closed");
        this.connectPromise = undefined;

        // 拒绝所有待处理请求
        for (const [id, pending] of this.pendingRequests) {
          pending.reject(new Error("Connection closed"));
        }
        this.pendingRequests.clear();

        // 自动重连
        if (!this.closedByUser) {
          this.scheduleReconnect();
        }
      };
    });

    return this.connectPromise;
  }

  private setupListeners(socket: WebSocket) {
    socket.onmessage = (ev) => {
      try {
        const msg: RpcResponse | RpcNotification = JSON.parse(ev.data);

        // 响应消息 (有 id)
        if ("id" in msg && msg.id !== undefined) {
          this.handleResponse(msg as RpcResponse);
          return;
        }

        // 通知消息 (无 id)
        if (msg.method === "event") {
          this.handleEvent(msg);
        }
      } catch (err) {
        console.error("[WS] Failed to parse message", err);
      }
    };
  }

  private handleResponse(response: RpcResponse) {
    const id = String(response.id);
    const pending = this.pendingRequests.get(id);
    if (!pending) return;

    this.pendingRequests.delete(id);

    if (response.error) {
      pending.reject(new Error(response.error.message));
    } else {
      pending.resolve(response.result);
    }
  }

  private handleEvent(notification: RpcNotification) {
    const params = notification.params as { name: string; payload: unknown };
    if (!params?.name) return;

    const handlers = this.eventHandlers.get(params.name);
    if (handlers) {
      handlers.forEach((handler) => {
        try {
          handler(params.payload);
        } catch (err) {
          console.error(`[WS] Event handler error for ${params.name}`, err);
        }
      });
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return;

    console.log(`[WS] Reconnecting in ${this.reconnectDelay}ms...`);
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = undefined;
      this.connect()
        .then(() => this.resubscribeEvents())
        .catch(() => {
          // 指数退避
          this.reconnectDelay = Math.min(
            this.reconnectDelay * 2,
            this.maxReconnectDelay
          );
        });
    }, this.reconnectDelay);
  }

  private async resubscribeEvents() {
    // 重连后重新订阅所有事件
    const events = Array.from(this.eventHandlers.keys());
    for (const event of events) {
      try {
        await this.sendRequest("event.subscribe", { event });
      } catch (err) {
        console.error(`[WS] Failed to resubscribe: ${event}`, err);
      }
    }
  }

  async sendRequest<T = unknown>(method: string, params?: unknown): Promise<T> {
    await this.connect();

    const id = String(this.nextId++);
    const request: RpcRequest = {
      jsonrpc: "2.0",
      id,
      method,
      params: params ?? {},
    };

    return new Promise<T>((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject } as PendingRequest);

      try {
        this.socket!.send(JSON.stringify(request));
      } catch (err) {
        this.pendingRequests.delete(id);
        reject(err);
      }
    });
  }

  async subscribe<T>(
    event: string,
    handler: (payload: T) => void
  ): Promise<UnlistenFn> {
    await this.connect();

    let handlers = this.eventHandlers.get(event);
    const isFirst = !handlers;

    if (!handlers) {
      handlers = new Set();
      this.eventHandlers.set(event, handlers);
    }

    handlers.add(handler as (payload: unknown) => void);

    // 只在第一个订阅者时发送 subscribe 请求
    if (isFirst) {
      try {
        await this.sendRequest("event.subscribe", { event });
      } catch (err) {
        handlers.delete(handler as (payload: unknown) => void);
        if (handlers.size === 0) {
          this.eventHandlers.delete(event);
        }
        throw err;
      }
    }

    // 返回取消订阅函数
    return async () => {
      const handlers = this.eventHandlers.get(event);
      if (!handlers) return;

      handlers.delete(handler as (payload: unknown) => void);

      if (handlers.size === 0) {
        this.eventHandlers.delete(event);
        try {
          await this.sendRequest("event.unsubscribe", { event });
        } catch (err) {
          console.error(`[WS] Failed to unsubscribe: ${event}`, err);
        }
      }
    };
  }

  close() {
    this.closedByUser = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }
    this.socket?.close();
  }
}

// 构建 WebSocket URL
function buildWsUrl(): string {
  const apiBase = import.meta.env.VITE_CC_SWITCH_API_BASE || "/api";
  const { protocol, host } = window.location;
  const wsProtocol = protocol === "https:" ? "wss:" : "ws:";
  const url = new URL(`${wsProtocol}//${host}${apiBase}/ws`);

  // 添加认证 token (如果存在)
  const token =
    import.meta.env.VITE_CC_SWITCH_AUTH_TOKEN ||
    localStorage.getItem("cc_switch_auth_token");
  if (token) {
    url.searchParams.set("auth", token);
  }

  return url.toString();
}

// 单例客户端
const wsClient = new JsonRpcWebSocketClient(buildWsUrl());

// 导出 Transport 实现
export const WebSocketTransport: ApiTransport = {
  mode: "ws",

  async invoke<T = unknown>(command: string, payload?: unknown): Promise<T> {
    return wsClient.sendRequest<T>(command, payload);
  },

  async listen<T = unknown>(
    event: string,
    handler: (payload: T) => void
  ): Promise<UnlistenFn> {
    return wsClient.subscribe<T>(event, handler);
  },

  debug(msg: string, data?: unknown) {
    if (import.meta.env.DEV) {
      console.debug(`[WebSocketTransport] ${msg}`, data ?? "");
    }
  },
};

// 清理函数 (页面卸载时调用)
if (typeof window !== "undefined") {
  window.addEventListener("beforeunload", () => {
    wsClient.close();
  });
}
```

### 4.2 类型定义更新

**`src/lib/transport/types.ts`**:
```typescript
export interface ApiTransport {
  mode: "tauri" | "http" | "ws"; // 新增 "ws"
  invoke<T = unknown>(command: string, payload?: unknown): Promise<T>;
  listen<T = unknown>(
    event: string,
    handler: (payload: T) => void
  ): Promise<UnlistenFn>;
  debug?: (msg: string, data?: unknown) => void;
}

export type UnlistenFn = () => void | Promise<void>;
```

### 4.3 Transport 检测逻辑

**`src/lib/transport/index.ts`**:
```typescript
import { TauriTransport } from "./tauriTransport";
import { HttpTransport } from "./httpTransport";
import { WebSocketTransport } from "./wsTransport";
import type { ApiTransport } from "./types";

function detectTransport(): ApiTransport {
  const mode = import.meta.env.VITE_CC_SWITCH_MODE;

  // 构建时强制指定模式
  if (mode === "ws" || mode === "websocket") {
    console.log("[Transport] Using WebSocket transport (build-time)");
    return WebSocketTransport;
  }
  if (mode === "http" || mode === "web") {
    console.log("[Transport] Using HTTP transport (build-time)");
    return HttpTransport;
  }
  if (mode === "tauri" || mode === "desktop") {
    console.log("[Transport] Using Tauri transport (build-time)");
    return TauriTransport;
  }

  // 运行时自动检测
  const isTauri = typeof window !== "undefined" && "__TAURI__" in window;
  if (isTauri) {
    console.log("[Transport] Using Tauri transport (runtime detection)");
    return TauriTransport;
  }

  // Web 模式默认使用 WebSocket
  console.log("[Transport] Using WebSocket transport (default web)");
  return WebSocketTransport;
}

const transport = detectTransport();

export const invoke = transport.invoke.bind(transport);
export const listen = transport.listen.bind(transport);
export const getTransportMode = () => transport.mode;
```

### 4.4 环境变量配置

**`.env.development`**:
```bash
VITE_CC_SWITCH_MODE=ws
VITE_CC_SWITCH_API_BASE=/api
```

**`.env.production`**:
```bash
VITE_CC_SWITCH_MODE=ws
VITE_CC_SWITCH_API_BASE=/api
```

---

## 5. 连接生命周期管理

### 5.1 连接建立流程

```
1. 页面加载
    ↓
2. 首次 invoke/listen 调用
    ↓
3. connect() - 懒连接
    ↓
4. WebSocket 握手 (携带 auth token)
    ↓
5. onopen - 连接建立
    ↓
6. 发送待处理请求
```

### 5.2 重连策略

**指数退避算法**:
```
尝试 1: 1s 后重连
尝试 2: 2s 后重连
尝试 3: 4s 后重连
...
最大延迟: 30s
```

**重连时恢复状态**:
1. 自动重新订阅所有事件 (`event.subscribe`)
2. 待处理请求已被拒绝，由调用方决定是否重试
3. UI 层通过 React Query 的 `refetchOnReconnect` 自动刷新数据

### 5.3 心跳保活

**客户端实现** (可选):
```typescript
class JsonRpcWebSocketClient {
  private heartbeatTimer?: number;
  private readonly heartbeatInterval = 30000; // 30s

  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = window.setInterval(() => {
      this.sendRequest("ping").catch(() => {
        // Ping 失败，触发重连
        this.socket?.close();
      });
    }, this.heartbeatInterval);
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = undefined;
    }
  }
}
```

### 5.4 认证流程

```
1. 客户端构建 WebSocket URL
    ↓
2. 添加 query 参数: ?auth=<token>
    ↓
3. 服务器验证 token
    ↓
4. 验证失败: 返回 401 Unauthorized
5. 验证成功: 升级为 WebSocket
```

**Token 存储位置**:
- 环境变量: `VITE_CC_SWITCH_AUTH_TOKEN` (开发环境)
- LocalStorage: `cc_switch_auth_token` (运行时动态获取)

---

## 6. 实施步骤

### Phase 1: 后端基础架构 (1-2 天)

- [ ] 定义 JSON-RPC 类型 (`rpc/` 模块)
- [ ] 实现事件总线 (`events.rs`)
- [ ] 提取命令分发逻辑 (`api/dispatch.rs`)
- [ ] 实现基础 WebSocket 端点 (`api/ws.rs`)
- [ ] 测试基本命令调用 (使用 `wscat` 工具)

### Phase 2: 前端 WebSocket Transport (1-2 天)

- [ ] 实现 `JsonRpcWebSocketClient` 类
- [ ] 实现 `WebSocketTransport`
- [ ] 更新 `detectTransport` 逻辑
- [ ] 添加开发环境配置
- [ ] 测试 `invoke` 调用

### Phase 3: 事件推送功能 (1 天)

- [ ] 后端实现 `event.subscribe`/`unsubscribe`
- [ ] 前端实现 `listen` 方法
- [ ] 实现订阅管理（单事件多监听器合并）
- [ ] 测试事件推送和取消订阅

### Phase 4: 重连与容错 (1 天)

- [ ] 实现自动重连逻辑
- [ ] 实现指数退避
- [ ] 实现事件重新订阅
- [ ] 测试断线重连场景

### Phase 5: 完善与优化 (1-2 天)

- [ ] 实现心跳保活
- [ ] 改进错误处理
- [ ] 添加详细日志
- [ ] 性能测试和优化
- [ ] 编写单元测试

### Phase 6: 迁移现有命令 (2-3 天)

- [ ] 迁移 Provider 相关命令 (10+)
- [ ] 迁移 MCP 相关命令 (7)
- [ ] 迁移 Settings 相关命令 (5)
- [ ] 迁移其他核心命令
- [ ] 端到端测试

---

## 7. 测试计划

### 7.1 单元测试

**后端**:
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_dispatch_get_providers() {
        let state = create_test_state().await;
        let params = serde_json::json!({ "app": "claude" });
        let result = dispatch_command(&state, "get_providers", &params).await;
        assert!(result.is_ok());
    }

    #[test]
    fn test_rpc_request_parsing() {
        let json = r#"{"jsonrpc":"2.0","id":1,"method":"test","params":{}}"#;
        let req: RpcRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.method, "test");
    }
}
```

**前端**:
```typescript
describe("JsonRpcWebSocketClient", () => {
  it("should send request and receive response", async () => {
    const client = new JsonRpcWebSocketClient("ws://localhost:3160/api/ws");
    const result = await client.sendRequest("get_providers", { app: "claude" });
    expect(result).toBeDefined();
  });

  it("should handle connection errors", async () => {
    const client = new JsonRpcWebSocketClient("ws://invalid:9999/ws");
    await expect(client.connect()).rejects.toThrow();
  });
});
```

### 7.2 集成测试

**使用 `wscat` 手动测试**:
```bash
# 安装 wscat
npm install -g wscat

# 连接 WebSocket
wscat -c ws://localhost:3160/api/ws

# 发送命令
> {"jsonrpc":"2.0","id":1,"method":"get_providers","params":{"app":"claude"}}

# 订阅事件
> {"jsonrpc":"2.0","id":2,"method":"event.subscribe","params":{"event":"provider_changed"}}

# 触发事件 (在另一个会话中切换 provider)
```

### 7.3 E2E 测试

使用 Playwright:
```typescript
test("WebSocket command invocation", async ({ page }) => {
  await page.goto("http://localhost:3160");

  // 等待 WebSocket 连接建立
  await page.waitForFunction(() => window.__WS_CONNECTED === true);

  // 测试切换 provider
  await page.click('[data-testid="provider-switch-button"]');
  await page.waitForSelector('[data-testid="provider-active"]');
});
```

### 7.4 压力测试

**测试目标**:
- 1000 个并发 WebSocket 连接
- 每秒 100 次命令调用
- 事件推送延迟 < 100ms

**工具**: 使用 `k6` 或自定义 Rust 脚本

---

## 8. 性能优化

### 8.1 消息批处理

对于频繁的事件推送，可以批量发送：
```rust
let mut batch = Vec::new();
while let Ok(event) = event_rx.try_recv() {
    if subscriptions.contains(&event.name) {
        batch.push(event);
    }
    if batch.len() >= 10 {
        break;
    }
}

if !batch.is_empty() {
    let notification = RpcResponse::notification("events", json!(batch));
    // 发送批量通知
}
```

### 8.2 连接复用

- 单例 WebSocket 连接，避免多个组件创建多个连接
- 请求管道化 (pipelining)，无需等待上一个响应即可发送下一个请求

### 8.3 二进制协议 (可选)

对于大量数据传输，可以使用 MessagePack 替代 JSON：
```typescript
// 发送
const binary = msgpack.encode(request);
socket.send(binary);

// 接收
const request = msgpack.decode(new Uint8Array(ev.data));
```

---

## 9. 兼容性与降级

### 9.1 浏览器支持

WebSocket 支持情况:
- Chrome/Edge: ✅ 全版本
- Firefox: ✅ 全版本
- Safari: ✅ iOS 4.2+
- IE: ⚠️ IE 10+

### 9.2 降级策略

```typescript
function detectTransport(): ApiTransport {
  const mode = import.meta.env.VITE_CC_SWITCH_MODE;

  if (mode === "http") {
    return HttpTransport; // 强制 HTTP
  }

  // 检查 WebSocket 支持
  if (typeof WebSocket === "undefined") {
    console.warn("[Transport] WebSocket not supported, falling back to HTTP");
    return HttpTransport;
  }

  return WebSocketTransport;
}
```

### 9.3 功能检测

前端可以动态检测是否支持事件推送：
```typescript
export function supportsRealtimeEvents(): boolean {
  const transport = getTransport();
  return transport.mode === "ws" || transport.mode === "tauri";
}

// UI 中使用
{supportsRealtimeEvents() ? (
  <span>实时同步</span>
) : (
  <span>手动刷新</span>
)}
```

---

## 10. 安全性考虑

### 10.1 认证增强

**双重认证**:
1. WebSocket 握手时验证 token (Query 参数)
2. 首次消息验证 (可选):
```json
{
  "jsonrpc": "2.0",
  "id": "auth-1",
  "method": "auth.login",
  "params": {
    "token": "<token>"
  }
}
```

### 10.2 防止跨站 WebSocket 劫持

```rust
use axum::http::HeaderMap;

pub async fn upgrade_handler(
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<Arc<ServerState>>,
) -> impl IntoResponse {
    // 验证 Origin
    if let Some(origin) = headers.get("origin") {
        let allowed = vec!["http://localhost:3160", "https://your-domain.com"];
        if !allowed.contains(&origin.to_str().unwrap_or("")) {
            return StatusCode::FORBIDDEN.into_response();
        }
    }

    // ... 继续处理
}
```

### 10.3 速率限制

```rust
use std::sync::RwLock;
use std::collections::HashMap;
use std::time::{Instant, Duration};

struct RateLimiter {
    requests: RwLock<HashMap<String, Vec<Instant>>>,
    max_per_minute: usize,
}

impl RateLimiter {
    fn check(&self, conn_id: &str) -> bool {
        let mut map = self.requests.write().unwrap();
        let now = Instant::now();
        let entry = map.entry(conn_id.to_string()).or_default();

        // 清理过期记录
        entry.retain(|&t| now.duration_since(t) < Duration::from_secs(60));

        if entry.len() >= self.max_per_minute {
            return false; // 超过限制
        }

        entry.push(now);
        true
    }
}
```

---

## 11. 监控与调试

### 11.1 日志记录

**后端**:
```rust
tracing::info!(
    command = %method,
    conn_id = %conn_id,
    duration_ms = %elapsed.as_millis(),
    "Command executed"
);
```

**前端**:
```typescript
const debugLog = {
  sent: (id: string, method: string) => {
    console.debug(`[WS → Server] ${method} (id: ${id})`);
  },
  received: (id: string, success: boolean) => {
    console.debug(`[WS ← Server] Response (id: ${id}, ok: ${success})`);
  },
  event: (name: string) => {
    console.debug(`[WS ← Server] Event: ${name}`);
  },
};
```

### 11.2 性能指标

收集关键指标:
```typescript
class PerformanceMonitor {
  trackCommand(method: string, duration: number) {
    // 发送到监控系统
    if (duration > 1000) {
      console.warn(`Slow command: ${method} took ${duration}ms`);
    }
  }

  trackReconnect(count: number, totalDowntime: number) {
    // 记录重连次数和总停机时间
  }
}
```

### 11.3 Chrome DevTools 调试

在 Chrome 中查看 WebSocket 连接:
```
1. F12 打开开发者工具
2. Network 标签
3. 筛选 WS (WebSocket)
4. 点击连接查看消息
```

---

## 12. 迁移指南

### 12.1 从 HTTP 迁移到 WebSocket

**现有 HTTP 代码**:
```typescript
import { invoke } from "@/lib/transport";

const providers = await invoke<Provider[]>("get_providers", { app: "claude" });
```

**迁移后** (无需修改):
```typescript
import { invoke } from "@/lib/transport"; // 相同导入

const providers = await invoke<Provider[]>("get_providers", { app: "claude" });
```

**唯一改动**: 设置环境变量 `VITE_CC_SWITCH_MODE=ws`

### 12.2 添加实时事件监听

**之前** (HTTP 模式，需要轮询):
```typescript
useEffect(() => {
  const timer = setInterval(() => {
    refetch(); // React Query 手动刷新
  }, 5000);
  return () => clearInterval(timer);
}, []);
```

**之后** (WebSocket 模式，实时推送):
```typescript
import { listen } from "@/lib/transport";

useEffect(() => {
  const unlisten = listen<ProviderChangedEvent>("provider_changed", (event) => {
    queryClient.invalidateQueries(["providers"]);
  });

  return () => {
    unlisten();
  };
}, []);
```

### 12.3 渐进式部署

1. **Phase 1**: 保留 HTTP 端点，添加 WebSocket 端点（共存）
2. **Phase 2**: 前端通过 Feature Flag 切换传输层
3. **Phase 3**: 监控 WebSocket 稳定性
4. **Phase 4**: 逐步将流量切换到 WebSocket
5. **Phase 5**: 移除 HTTP 端点（可选）

**Feature Flag 示例**:
```typescript
const USE_WEBSOCKET = import.meta.env.VITE_ENABLE_WS === "true";

const transport = USE_WEBSOCKET ? WebSocketTransport : HttpTransport;
```

---

## 13. 故障排查

### 13.1 常见问题

| 问题 | 症状 | 解决方案 |
|------|------|----------|
| 连接立即关闭 | `onclose` 立即触发 | 检查认证 token 是否正确 |
| 请求超时 | `invoke` 永不返回 | 检查后端是否响应，查看 `pending` 队列 |
| 事件收不到 | `listen` 回调未触发 | 检查是否成功订阅，后端是否推送 |
| 频繁重连 | 日志显示反复重连 | 检查网络状态，增加重连延迟 |

### 13.2 调试清单

**后端**:
```bash
# 启用详细日志
RUST_LOG=debug cargo run

# 检查 WebSocket 连接数
ss -tn | grep 3160

# 监控事件总线
# 在代码中添加日志: tracing::debug!("Event sent: {:?}", event);
```

**前端**:
```typescript
// 启用 Transport 调试日志
localStorage.setItem("debug_transport", "true");

// 检查 WebSocket 状态
console.log(window.__wsClient?.socket?.readyState);
// 0: CONNECTING, 1: OPEN, 2: CLOSING, 3: CLOSED

// 查看待处理请求
console.log(window.__wsClient?.pendingRequests.size);
```

---

## 14. 总结

### 14.1 关键收益

1. **实时性**: 事件推送延迟从秒级 (轮询) 降至毫秒级
2. **简洁性**: 单一连接替代多个 HTTP 请求
3. **一致性**: Web 模式与 Tauri 模式行为统一
4. **可扩展性**: 易于添加新命令和事件

### 14.2 技术债务

1. **重连逻辑复杂**: 需要维护状态机和订阅恢复
2. **调试难度**: 相比 HTTP 的请求/响应，WebSocket 消息流更难追踪
3. **兼容性**: 老旧浏览器需要降级方案

### 14.3 后续优化方向

- [ ] 实现消息压缩 (deflate)
- [ ] 支持二进制协议 (MessagePack)
- [ ] 添加请求取消机制 (AbortController)
- [ ] 实现服务端负载均衡 (Sticky Sessions)
- [ ] 添加端到端加密 (E2EE) 选项

---

## 附录

### A. JSON-RPC 2.0 规范

参考: https://www.jsonrpc.org/specification

### B. WebSocket 协议

参考: RFC 6455 - https://tools.ietf.org/html/rfc6455

### C. 相关代码位置

| 组件 | 路径 |
|------|------|
| WebSocket Transport | `src/lib/transport/wsTransport.ts` |
| WebSocket Handler | `crates/server/src/api/ws.rs` |
| RPC 类型定义 | `crates/server/src/rpc/` |
| 事件总线 | `crates/server/src/events.rs` |
| 命令分发 | `crates/server/src/api/dispatch.rs` |

### D. 开发工具推荐

- **wscat**: WebSocket 命令行客户端
- **Postman**: 支持 WebSocket 测试
- **Chrome DevTools**: 网络标签查看 WS 消息
- **websocat**: 高级 WebSocket 调试工具

---

**文档修订历史**:
- v1.0 (2025-12-03): 初始版本，完整架构设计
