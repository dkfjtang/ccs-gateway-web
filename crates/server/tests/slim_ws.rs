use std::net::SocketAddr;
use std::sync::Arc;

use axum::{routing::get, Router};
use cc_switch::{AppState, Database};
use cc_switch_core::CoreContext;
use cc_switch_server::{
    api::upgrade_handler, build_info::build_info_from_assets, create_event_bus,
    profile::ProfileConfig, AuthConfig, ServerState, SessionStore,
};
use futures::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, Message},
};

fn test_state(profile: &str, auth_enabled: bool) -> Arc<ServerState> {
    let db = Arc::new(Database::memory().expect("in-memory database"));
    let profile = ProfileConfig::from_env_value(Some(profile)).unwrap();
    let build_info = build_info_from_assets(&profile, Vec::new(), "test");
    Arc::new(ServerState {
        auth_token: None,
        event_bus: create_event_bus(8),
        core: CoreContext::from_app_state(AppState::new(db)),
        session_store: Arc::new(SessionStore::new()),
        auth_config: auth_enabled.then(|| AuthConfig {
            password_hash: "$2b$04$MJuc/Azj7j9Js28.20f31uIhhVpf8f1GqCdPbh3D5StxPf8/FxYSi"
                .to_string(),
        }),
        allow_extension_session_header: true,
        profile,
        build_info,
        auth_vault_receive_window: Default::default(),
    })
}

async fn spawn_ws_server(state: Arc<ServerState>) -> (SocketAddr, tokio::task::JoinHandle<()>) {
    let app = Router::new()
        .route("/api/ws", get(upgrade_handler))
        .with_state(state);
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind ws test");
    let addr = listener.local_addr().expect("local addr");
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("ws test server");
    });
    (addr, server)
}

#[tokio::test]
async fn unauthenticated_ws_upgrade_gets_401_before_capability_details() {
    let state = test_state("slim", true);
    let (addr, server) = spawn_ws_server(state).await;

    let err = connect_async(format!("ws://{addr}/api/ws"))
        .await
        .expect_err("unauthenticated ws should fail");
    let message = err.to_string();
    assert!(message.contains("401") || message.contains("HTTP error"));

    server.abort();
}

#[tokio::test]
async fn authenticated_disabled_ws_command_returns_jsonrpc_capability_error_and_keeps_socket_open()
{
    let state = test_state("slim", true);
    let token = state.session_store.create_session();
    let (addr, server) = spawn_ws_server(state).await;

    let mut request = format!("ws://{addr}/api/ws")
        .into_client_request()
        .expect("websocket request");
    request.headers_mut().insert(
        "Cookie",
        format!("cc-switch-session={token}")
            .parse()
            .expect("cookie header"),
    );
    let (mut ws, _) = connect_async(request).await.expect("connect websocket");

    ws.send(Message::Text(
        json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "get_installed_skills",
            "params": {}
        })
        .to_string(),
    ))
    .await
    .expect("send disabled command");

    let response = ws
        .next()
        .await
        .expect("disabled response")
        .expect("disabled message")
        .into_text()
        .expect("disabled text");
    let response: Value = serde_json::from_str(&response).expect("json response");
    assert_eq!(response["error"]["message"], "capability_disabled");
    assert_eq!(response["error"]["data"]["error"], "capability_disabled");
    assert_eq!(response["error"]["data"]["capability"], "skills");
    assert_eq!(response["error"]["data"]["command"], "get_installed_skills");

    ws.send(Message::Text(
        json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "ping",
            "params": {}
        })
        .to_string(),
    ))
    .await
    .expect("send ping");
    let ping = ws
        .next()
        .await
        .expect("ping response")
        .expect("ping message")
        .into_text()
        .expect("ping text");
    let ping: Value = serde_json::from_str(&ping).expect("json ping");
    assert_eq!(ping["result"], json!({"pong": true}));

    server.abort();
}
