use std::sync::Arc;

use axum::{
    body::Body,
    extract::State,
    http::{header, Response, StatusCode},
    response::{Html, IntoResponse},
    routing::get,
    Json, Router,
};
use serde::Serialize;

use crate::{build_info::BuildInfo, profile::CcsWebProfile, state::ServerState};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StartupHealth {
    pub error: &'static str,
    pub supported_db_version: i32,
    pub found_db_version: i32,
    pub profile: CcsWebProfile,
}

impl StartupHealth {
    pub fn db_version_too_new(
        found_db_version: i32,
        supported_db_version: i32,
        profile: CcsWebProfile,
    ) -> Self {
        Self {
            error: "db_version_too_new",
            supported_db_version,
            found_db_version,
            profile,
        }
    }
}

#[derive(Clone)]
pub struct DegradedState {
    pub build_info: BuildInfo,
    pub health: StartupHealth,
}

pub async fn build_info_handler(State(state): State<Arc<ServerState>>) -> impl IntoResponse {
    (
        [(header::CACHE_CONTROL, "no-store")],
        Json(state.build_info.clone()),
    )
}

pub async fn degraded_build_info_handler(
    State(state): State<Arc<DegradedState>>,
) -> impl IntoResponse {
    (
        [(header::CACHE_CONTROL, "no-store")],
        Json(state.build_info.clone()),
    )
}

pub async fn health_handler() -> Html<&'static str> {
    Html(
        r#"<!DOCTYPE html>
<html>
<head>
    <title>CC-Switch Web</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #2563eb; }
        .info { background: #f1f5f9; padding: 20px; border-radius: 8px; }
        code { background: #e2e8f0; padding: 2px 6px; border-radius: 4px; }
        a { color: #2563eb; }
    </style>
</head>
<body>
    <h1>CC-Switch Web Server</h1>
    <div class="info">
        <p><strong>Status:</strong> Running</p>
        <p><strong>API Endpoints:</strong></p>
        <ul>
            <li>HTTP: <code>POST /api/invoke</code></li>
            <li>WebSocket: <code>GET /api/ws</code></li>
        </ul>
        <p><strong>Frontend:</strong> <a href="/">Open Web UI</a></p>
    </div>
</body>
</html>"#,
    )
}

pub async fn degraded_health_handler(State(state): State<Arc<DegradedState>>) -> impl IntoResponse {
    (StatusCode::SERVICE_UNAVAILABLE, Json(state.health.clone()))
}

async fn degraded_not_found_handler() -> impl IntoResponse {
    Response::builder()
        .status(StatusCode::NOT_FOUND)
        .body(Body::from("404 Not Found"))
        .unwrap()
}

pub fn degraded_app(build_info: BuildInfo, health: StartupHealth) -> Router {
    let state = Arc::new(DegradedState { build_info, health });
    Router::new()
        .route("/", get(degraded_health_handler))
        .route("/health", get(degraded_health_handler))
        .route("/build-info.json", get(degraded_build_info_handler))
        .fallback(degraded_not_found_handler)
        .with_state(state)
}
