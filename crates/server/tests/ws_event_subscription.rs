use std::net::SocketAddr;
use std::sync::Arc;

use axum::{routing::get, Router};
use cc_switch::{AppState, Database};
use cc_switch_core::CoreContext;
use cc_switch_server::{
    api::upgrade_handler, build_info::build_info_from_assets, create_event_bus,
    profile::ProfileConfig, AuthConfig, ServerEvent, ServerState, SessionStore,
};
use futures::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio_tungstenite::{connect_async, tungstenite::Message};

fn test_state() -> (Arc<ServerState>, cc_switch_server::EventSender) {
    let event_bus = create_event_bus(8);
    let db = Arc::new(Database::memory().expect("in-memory database"));
    let profile = ProfileConfig::default();
    let build_info = build_info_from_assets(&profile, Vec::new(), "test");
    let state = Arc::new(ServerState {
        auth_token: None,
        event_bus: event_bus.clone(),
        core: CoreContext::from_app_state(AppState::new(db)),
        session_store: Arc::new(SessionStore::new()),
        auth_config: None::<AuthConfig>,
        allow_extension_session_header: true,
        profile,
        build_info,
    });

    (state, event_bus)
}

#[tokio::test]
async fn websocket_event_subscription_receives_matching_events() {
    let (state, event_bus) = test_state();
    let app = Router::new()
        .route("/api/ws", get(upgrade_handler))
        .with_state(state);

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind ws test");
    let addr: SocketAddr = listener.local_addr().expect("local addr");
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("ws test server");
    });

    let (mut ws, _) = connect_async(format!("ws://{addr}/api/ws"))
        .await
        .expect("connect websocket");

    ws.send(Message::Text(
        json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "event.subscribe",
            "params": { "event": "settings.changed" }
        })
        .to_string(),
    ))
    .await
    .expect("send subscription");

    let subscribe_response = ws
        .next()
        .await
        .expect("subscription response")
        .expect("subscription message")
        .into_text()
        .expect("subscription text");
    let subscribe_json: Value = serde_json::from_str(&subscribe_response).expect("json response");
    assert_eq!(subscribe_json["result"], json!({ "ok": true }));

    event_bus
        .send(ServerEvent {
            name: "settings.changed".to_string(),
            payload: json!({ "source": "test" }),
        })
        .expect("send event");

    let event_response = tokio::time::timeout(std::time::Duration::from_secs(2), ws.next())
        .await
        .expect("event notification timeout")
        .expect("event notification")
        .expect("event message")
        .into_text()
        .expect("event text");
    let event_json: Value = serde_json::from_str(&event_response).expect("json event");
    assert_eq!(event_json["method"], "event");
    assert_eq!(event_json["params"]["name"], "settings.changed");
    assert_eq!(event_json["params"]["payload"], json!({ "source": "test" }));

    server.abort();
}
