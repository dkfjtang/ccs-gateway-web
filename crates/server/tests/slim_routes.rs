use std::sync::Arc;

use axum::{
    body::{to_bytes, Body},
    extract::connect_info::ConnectInfo,
    http::{header, Request, StatusCode},
    routing::{get, post},
    Json, Router,
};
use cc_switch::{AppState, Database};
use cc_switch_core::CoreContext;
use cc_switch_server::{
    api::{
        auth_vault_routes, export_sql_download_handler, import_sql_upload_handler, invoke_handler,
        upgrade_handler,
    },
    build_info::build_info_from_assets,
    create_event_bus,
    profile::{CapabilityGroup, CcsWebProfile, ProfileConfig},
    AuthConfig, ServerState, SessionStore,
};
use serde_json::{json, Value};
use tower::util::ServiceExt;

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
    })
}

fn test_app(state: Arc<ServerState>) -> Router {
    let profile = state.profile.clone();
    Router::new()
        .route("/api/invoke", post(invoke_handler))
        .nest("/api/auth-vault", auth_vault_routes(&profile))
        .route("/api/ws", get(upgrade_handler))
        .route("/api/import-config", post(import_sql_upload_handler))
        .route("/api/export-config", get(export_sql_download_handler))
        .fallback(api_not_found_handler)
        .with_state(state)
}

async fn api_not_found_handler() -> impl axum::response::IntoResponse {
    (
        StatusCode::NOT_FOUND,
        Json(json!({
            "error": "api_route_not_found",
            "message": "Unknown API route."
        })),
    )
}

fn session_cookie(state: &ServerState) -> String {
    let token = state.session_store.create_session();
    format!("cc-switch-session={token}")
}

async fn body_json(response: axum::response::Response) -> Value {
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&body).expect("json body")
}

#[tokio::test]
async fn unauthenticated_invoke_gets_401_before_capability_details() {
    let state = test_state("slim", true);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/invoke")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({"command":"get_installed_skills","payload":{}}).to_string(),
                ))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let body = body_json(response).await;
    assert_ne!(body["error"], "capability_disabled");
}

#[tokio::test]
async fn authenticated_disabled_invoke_gets_403_capability_disabled() {
    let state = test_state("slim", true);
    let cookie = session_cookie(&state);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/invoke")
                .header(header::CONTENT_TYPE, "application/json")
                .header(header::COOKIE, cookie)
                .body(Body::from(
                    json!({"command":"get_installed_skills","payload":{}}).to_string(),
                ))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let body = body_json(response).await;
    assert_eq!(body["error"]["error"], "capability_disabled");
    assert_eq!(body["error"]["capability"], "skills");
    assert_eq!(body["error"]["command"], "get_installed_skills");
}

#[tokio::test]
async fn retained_invoke_command_is_not_blocked_by_slim_capability_gate() {
    let state = test_state("slim", true);
    let cookie = session_cookie(&state);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/invoke")
                .header(header::CONTENT_TYPE, "application/json")
                .header(header::COOKIE, cookie)
                .body(Body::from(
                    json!({"command":"ping","payload":{}}).to_string(),
                ))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["result"], json!({"pong": true}));
}

#[tokio::test]
async fn auth_vault_known_and_unknown_paths_are_403_in_slim() {
    for with_session in [false, true] {
        let state = test_state("slim", true);
        let cookie = with_session.then(|| session_cookie(&state));
        let app = test_app(state);

        for (method, path) in [
            ("POST", "/api/auth-vault/tokens"),
            ("GET", "/api/auth-vault/tokens/summary"),
            ("GET", "/api/auth-vault/anything-else"),
        ] {
            let mut request = Request::builder()
                .method(method)
                .uri(path)
                .header(header::CONTENT_TYPE, "application/json");
            if let Some(cookie) = &cookie {
                request = request.header(header::COOKIE, cookie);
            }
            if method == "POST" && path == "/api/auth-vault/tokens" {
                request = request.extension(ConnectInfo(
                    "127.0.0.1:12345"
                        .parse::<std::net::SocketAddr>()
                        .expect("loopback socket addr"),
                ));
            }
            let response = app
                .clone()
                .oneshot(
                    request
                        .body(Body::from(json!({}).to_string()))
                        .expect("request"),
                )
                .await
                .expect("response");

            assert_eq!(response.status(), StatusCode::FORBIDDEN, "{method} {path}");
            let body = body_json(response).await;
            assert_eq!(body["error"], "capability_disabled");
            assert_eq!(body["capability"], "auth-vault");
        }
    }
}

#[tokio::test]
async fn auth_vault_unknown_path_is_normal_404_in_full() {
    let state = test_state("full", true);
    let cookie = session_cookie(&state);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/auth-vault/anything-else")
                .header(header::COOKIE, cookie)
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let body = body_json(response).await;
    assert_eq!(body["error"], "api_route_not_found");
}

#[tokio::test]
async fn auth_vault_tokens_rejects_before_json_parsing_in_slim() {
    let state = test_state("slim", true);
    let cookie = session_cookie(&state);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/auth-vault/tokens")
                .header(header::CONTENT_TYPE, "application/json")
                .header(header::COOKIE, cookie)
                .extension(ConnectInfo(
                    "127.0.0.1:12345"
                        .parse::<std::net::SocketAddr>()
                        .expect("loopback socket addr"),
                ))
                .body(Body::from("{not-json"))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let body = body_json(response).await;
    assert_eq!(body["error"], "capability_disabled");
    assert_eq!(body["capability"], "auth-vault");
}

#[tokio::test]
async fn unknown_api_route_does_not_fall_through_to_spa() {
    let state = test_state("slim", true);
    let cookie = session_cookie(&state);
    let app = test_app(state);

    let response = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/nonexistent-management-route")
                .header(header::COOKIE, cookie)
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert_ne!(
        response
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok()),
        Some("text/html")
    );
    let body = body_json(response).await;
    assert_eq!(body["error"], "api_route_not_found");
}

#[test]
fn build_info_exposes_sanitized_profile_and_capabilities() {
    let slim = ProfileConfig::from_env_value(Some("slim")).unwrap();
    let full = ProfileConfig::from_env_value(Some("full")).unwrap();

    let slim_info = build_info_from_assets(
        &slim,
        vec!["assets/index-BTaiIF1Z.js".to_string()],
        "fallback",
    );
    let full_info = build_info_from_assets(&full, Vec::new(), "fallback");
    let slim_json = serde_json::to_string(&slim_info).expect("slim build info json");

    assert_eq!(slim_info.profile, CcsWebProfile::Slim);
    assert_eq!(full_info.profile, CcsWebProfile::Full);
    assert_eq!(slim_info.build_id, "assets/index-BTaiIF1Z.js");
    assert_eq!(full_info.build_id, "fallback");
    assert!(slim_info
        .capabilities
        .disabled_groups
        .contains(&CapabilityGroup::AuthVault));
    assert!(slim_info
        .capabilities
        .enabled_groups
        .contains(&CapabilityGroup::Providers));
    assert!(!slim_json.contains(":\\"));
    assert!(!slim_json.contains("/home/"));
    assert!(!slim_json.contains("/Users/"));
}
