use std::sync::Arc;

use axum::{
    body::to_bytes,
    body::Body,
    http::{header::CONTENT_TYPE, Request, StatusCode},
    routing::post,
    Router,
};
use cc_switch::{AppState, ClaudeDesktopMode, Database, Provider, ProviderMeta};
use cc_switch_core::CoreContext;
use cc_switch_server::{
    api::import_sql_upload_handler,
    build_info::build_info_from_assets,
    create_event_bus,
    profile::{CcsWebProfile, ProfileConfig},
    AuthConfig, ServerState, SessionStore,
};
use serde_json::{json, Value};
use tower::util::ServiceExt;

fn test_build_info(profile: &ProfileConfig) -> cc_switch_server::build_info::BuildInfo {
    build_info_from_assets(profile, Vec::new(), "test")
}

fn multipart_sql_body(boundary: &str, sql: &str) -> String {
    format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"config.sql\"\r\nContent-Type: application/sql\r\n\r\n{sql}\r\n--{boundary}--\r\n"
    )
}

#[tokio::test]
async fn unauthenticated_sql_upload_is_rejected_when_web_auth_is_enabled() {
    let db = Arc::new(Database::memory().expect("in-memory database"));
    let profile = ProfileConfig::default();
    let state = Arc::new(ServerState {
        auth_token: None,
        event_bus: create_event_bus(8),
        core: CoreContext::from_app_state(AppState::new(db)),
        session_store: Arc::new(SessionStore::new()),
        auth_config: Some(AuthConfig {
            password_hash: "test-hash".to_string(),
        }),
        allow_extension_session_header: true,
        build_info: test_build_info(&profile),
        profile,
        auth_vault_receive_window: Default::default(),
    });

    let app = Router::new()
        .route("/api/import-config", post(import_sql_upload_handler))
        .with_state(state);

    let boundary = "X-BOUNDARY";
    let body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"config.sql\"\r\nContent-Type: application/sql\r\n\r\n-- CC Switch SQLite 导出\nSELECT 1;\r\n--{boundary}--\r\n"
    );

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/import-config")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn invalid_sql_upload_does_not_pollute_existing_database() {
    let db = Arc::new(Database::memory().expect("in-memory database"));
    let before = db.export_sql_string().expect("export before");
    let profile = ProfileConfig::default();
    let state = Arc::new(ServerState {
        auth_token: None,
        event_bus: create_event_bus(8),
        core: CoreContext::from_app_state(AppState::new(db.clone())),
        session_store: Arc::new(SessionStore::new()),
        auth_config: None,
        allow_extension_session_header: true,
        build_info: test_build_info(&profile),
        profile,
        auth_vault_receive_window: Default::default(),
    });

    let app = Router::new()
        .route("/api/import-config", post(import_sql_upload_handler))
        .with_state(state);

    let boundary = "X-BOUNDARY";
    let body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"config.sql\"\r\nContent-Type: application/sql\r\n\r\n-- CC Switch SQLite 导出\nTHIS IS NOT VALID SQL;\r\n--{boundary}--\r\n"
    );

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/import-config")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let after = db.export_sql_string().expect("export after");
    assert_eq!(
        before, after,
        "failed upload should not mutate existing data"
    );
}

#[tokio::test]
async fn slim_sql_upload_skips_disabled_live_sync_warning() {
    let source_db = Database::memory().expect("source database");
    let mut provider = Provider::with_id(
        "desktop-provider".to_string(),
        "Claude Desktop Provider".to_string(),
        json!({
            "baseUrl": "https://example.com/v1",
            "apiKey": "test-key",
            "models": [
                { "id": "claude-sonnet-4", "name": "Claude Sonnet 4" }
            ]
        }),
        Some("https://example.com".to_string()),
    );
    provider.meta = Some(ProviderMeta {
        claude_desktop_mode: Some(ClaudeDesktopMode::Direct),
        ..ProviderMeta::default()
    });
    source_db
        .save_provider("claude-desktop", &provider)
        .expect("save claude desktop provider");
    source_db
        .set_current_provider("claude-desktop", &provider.id)
        .expect("set claude desktop current provider");
    let sql = source_db.export_sql_string().expect("export source sql");

    let target_db = Arc::new(Database::memory().expect("target database"));
    let profile = ProfileConfig {
        profile: CcsWebProfile::Slim,
    };
    let state = Arc::new(ServerState {
        auth_token: None,
        event_bus: create_event_bus(8),
        core: CoreContext::from_app_state(AppState::new(target_db.clone())),
        session_store: Arc::new(SessionStore::new()),
        auth_config: None,
        allow_extension_session_header: true,
        build_info: test_build_info(&profile),
        profile,
        auth_vault_receive_window: Default::default(),
    });

    let app = Router::new()
        .route("/api/import-config", post(import_sql_upload_handler))
        .with_state(state);

    let boundary = "X-BOUNDARY";
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/import-config")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(multipart_sql_body(boundary, &sql)))
                .expect("request"),
        )
        .await
        .expect("response");

    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("response body");
    let value: Value = serde_json::from_slice(&body).expect("json response");
    assert_eq!(value["success"], json!(true));
    assert!(
        value.get("warning").is_none(),
        "slim upload import should not warn about disabled live sync: {value}"
    );
    assert!(
        target_db
            .get_provider_by_id(&provider.id, "claude-desktop")
            .expect("query imported provider")
            .is_some(),
        "import should still preserve claude desktop provider data"
    );
}
