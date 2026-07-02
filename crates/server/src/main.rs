use axum::{
    body::Body,
    extract::DefaultBodyLimit,
    http::{header, Response, StatusCode, Uri},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use rust_embed::RustEmbed;
use std::net::{IpAddr, SocketAddr, TcpListener as StdTcpListener};
use std::sync::Arc;
use std::time::Duration;
use tower_http::cors::{Any, CorsLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use cc_switch_server::{
    api::{
        auth_vault_routes, export_sql_download_handler, import_sql_upload_handler, invoke_handler,
        upgrade_handler, MAX_SQL_UPLOAD_BYTES,
    },
    app::{build_info_handler, degraded_app, health_handler},
    auth_config_for_profile,
    build_info::{build_info_from_assets, index_assets_from_html},
    create_event_bus, load_auth_config_result,
    profile::ProfileConfig,
    slim_no_auth_override_enabled, ServerState, SessionStore,
};

// 嵌入前端静态文件（构建时从 dist 目录读取）
#[derive(RustEmbed)]
#[folder = "../../dist/"]
struct Assets;

// 静态文件处理器
async fn static_handler(uri: Uri) -> impl IntoResponse {
    let path = uri.path().trim_start_matches('/');

    // 如果路径为空或者不包含扩展名，返回 index.html（SPA 路由支持）
    let path = if path.is_empty() || (!path.contains('.') && !path.starts_with("api/")) {
        "index.html"
    } else {
        path
    };

    match Assets::get(path) {
        Some(content) => {
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, mime.as_ref())
                .body(Body::from(content.data.into_owned()))
                .unwrap()
        }
        None => {
            // 对于 SPA，非 API 请求返回 index.html
            if !path.starts_with("api/") {
                if let Some(content) = Assets::get("index.html") {
                    return Response::builder()
                        .status(StatusCode::OK)
                        .header(header::CONTENT_TYPE, "text/html")
                        .body(Body::from(content.data.into_owned()))
                        .unwrap();
                }
            }
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::from("404 Not Found"))
                .unwrap()
        }
    }
}

async fn api_not_found_handler() -> impl IntoResponse {
    (
        StatusCode::NOT_FOUND,
        Json(serde_json::json!({
            "error": "api_route_not_found",
            "message": "Unknown API route."
        })),
    )
}

fn current_build_info(profile: &ProfileConfig) -> cc_switch_server::build_info::BuildInfo {
    let assets = Assets::get("index.html")
        .and_then(|content| String::from_utf8(content.data.into_owned()).ok())
        .map(|html| index_assets_from_html(&html))
        .unwrap_or_default();
    build_info_from_assets(profile, assets, env!("CARGO_PKG_VERSION"))
}

fn try_bind_listener(host: &str, port: u16) -> Option<StdTcpListener> {
    StdTcpListener::bind(format!("{}:{}", host, port)).ok()
}

/// 查找可用端口并直接保留监听器，避免“先探测再绑定”的竞争窗口。
fn find_available_listener(host: &str, start_port: u16) -> Option<(u16, StdTcpListener)> {
    for port in start_port..start_port.saturating_add(100) {
        if let Some(listener) = try_bind_listener(host, port) {
            return Some((port, listener));
        }
    }
    None
}

fn is_loopback_host(host: &str) -> bool {
    matches!(host, "localhost")
        || host
            .parse::<IpAddr>()
            .map(|addr| addr.is_loopback())
            .unwrap_or(false)
}

fn allow_extension_session_header(host: &str) -> bool {
    if let Ok(value) = std::env::var("CC_SWITCH_ALLOW_EXTENSION_SESSION_HEADER") {
        return value == "1" || value.eq_ignore_ascii_case("true");
    }

    is_loopback_host(host)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_id_from_index_html_uses_main_assets() {
        let html = r#"<!doctype html>
<script type="module" crossorigin src="./assets/index-BTaiIF1Z.js"></script>
<link rel="stylesheet" crossorigin href="./assets/index-CY8IdWrI.css">
<script type="module" crossorigin src="./assets/vendor-react.js"></script>"#;

        let build_id = cc_switch_server::build_info::build_id_from_index_html(html);

        assert_eq!(
            build_id,
            "assets/index-BTaiIF1Z.js,assets/index-CY8IdWrI.css"
        );
    }
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "cc_switch_server=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Create event bus
    let event_bus = create_event_bus(100);

    let profile = ProfileConfig::from_env().unwrap_or_else(|err| {
        tracing::error!(error = %err, "Invalid ccs-web profile");
        std::process::exit(1);
    });

    // Load auth configuration. Full keeps the legacy "missing auth means disabled"
    // behavior; slim production fails closed unless explicitly overridden for local tests.
    let auth_config = auth_config_for_profile(
        &profile,
        load_auth_config_result(),
        slim_no_auth_override_enabled(),
    )
    .unwrap_or_else(|err| {
        tracing::error!(
            profile = ?profile.profile,
            reason = ?err.reason,
            "Web authentication configuration rejected for the active ccs-web profile"
        );
        std::process::exit(1);
    });
    if auth_config.is_some() {
        tracing::info!("Web authentication enabled");
    } else {
        tracing::info!("Web authentication disabled (no config found)");
    }

    // Create session store
    let session_store = Arc::new(SessionStore::new());

    // Get host from environment or use default
    let host = std::env::var("CC_SWITCH_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let is_loopback = is_loopback_host(&host);
    let allow_extension_session_header = allow_extension_session_header(&host);

    // Spawn session cleanup task (runs every hour)
    let cleanup_store = Arc::clone(&session_store);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(3600));
        loop {
            interval.tick().await;
            cleanup_store.cleanup_expired();
            tracing::debug!("Session cleanup completed");
        }
    });

    // Create server state
    let auth_token = std::env::var("CC_SWITCH_AUTH_TOKEN").ok();
    let build_info = current_build_info(&profile);
    let state = match ServerState::new(
        auth_token,
        event_bus,
        session_store,
        auth_config,
        allow_extension_session_header,
        profile.clone(),
        build_info,
    ) {
        Ok(state) => state,
        Err(cc_switch_core::AppError::DatabaseVersionTooNew {
            found_version,
            supported_version,
        }) => {
            tracing::error!(
                found_version,
                supported_version,
                profile = ?profile.profile,
                "Database schema is newer than this ccs-web build; starting degraded health server"
            );
            start_server(
                &host,
                is_loopback,
                degraded_app(
                    current_build_info(&profile),
                    cc_switch_server::StartupHealth::db_version_too_new(
                        found_version,
                        supported_version,
                        profile.profile,
                    ),
                ),
                false,
                None,
            )
            .await;
            return;
        }
        Err(err) => {
            tracing::error!(error = %err, "Failed to initialize cc-switch core context");
            std::process::exit(1);
        }
    };

    let auto_start_proxy = std::env::var("CC_SWITCH_START_PROXY")
        .map(|v| v != "0" && v.to_lowercase() != "false")
        .unwrap_or(false);
    if auto_start_proxy {
        let proxy_state = state.clone();
        tokio::spawn(async move {
            match proxy_state.core.app_state().proxy_service.start().await {
                Ok(info) => tracing::info!(
                    address = %info.address,
                    port = info.port,
                    "Local proxy auto-started"
                ),
                Err(err) => tracing::error!(error = %err, "Failed to auto-start local proxy"),
            }
        });
    }

    // CORS configuration
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any)
        .allow_private_network(true);

    // Build API routes
    let api_routes = Router::new()
        .route("/invoke", post(invoke_handler))
        .nest("/auth-vault", auth_vault_routes(&profile))
        .route("/ws", get(upgrade_handler))
        .route("/import-config", post(import_sql_upload_handler))
        .route("/export-config", get(export_sql_download_handler))
        .fallback(api_not_found_handler)
        .layer(DefaultBodyLimit::max(MAX_SQL_UPLOAD_BYTES))
        .with_state(state.clone());

    // Check if frontend assets are embedded
    let has_frontend = Assets::get("index.html").is_some();

    let app = if has_frontend {
        tracing::info!("Frontend assets embedded, serving SPA");
        Router::new()
            .nest("/api", api_routes)
            .route("/build-info.json", get(build_info_handler))
            .route("/health", get(health_handler))
            .fallback(static_handler)
            .with_state(state.clone())
            .layer(cors)
    } else {
        tracing::warn!("No frontend assets found, running in API-only mode");
        tracing::warn!("Build frontend first: pnpm build:web");
        Router::new()
            .route("/", get(health_handler))
            .route("/health", get(health_handler))
            .route("/build-info.json", get(build_info_handler))
            .nest("/api", api_routes)
            .with_state(state.clone())
            .layer(cors)
    };

    start_server(&host, is_loopback, app, has_frontend, Some(state)).await;
}

async fn start_server(
    host: &str,
    is_loopback: bool,
    app: Router,
    has_frontend: bool,
    state: Option<Arc<ServerState>>,
) {
    let degraded = state.is_none();

    // Get port from environment or use default
    let requested_port: u16 = std::env::var("CC_SWITCH_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(17666);

    // Check if auto-port selection is enabled (default: true)
    let auto_port = std::env::var("CC_SWITCH_AUTO_PORT")
        .map(|v| v != "0" && v.to_lowercase() != "false")
        .unwrap_or(true);

    let allow_auto_port = is_loopback && auto_port;

    // Find available port
    let (port, std_listener) = if let Some(listener) = try_bind_listener(&host, requested_port) {
        (requested_port, listener)
    } else if allow_auto_port {
        eprintln!();
        eprintln!("⚠️  Port {} is already in use", requested_port);
        match find_available_listener(&host, requested_port + 1) {
            Some((port, listener)) => {
                eprintln!("   Automatically using port {} instead", port);
                eprintln!("   To disable auto-port: CC_SWITCH_AUTO_PORT=false");
                eprintln!();
                (port, listener)
            }
            None => {
                eprintln!("❌ Error: Could not find an available port");
                eprintln!(
                    "   Tried ports {} to {}",
                    requested_port,
                    requested_port + 100
                );
                eprintln!();
                eprintln!("   Solutions:");
                eprintln!(
                    "   1. Stop the process using port {}: lsof -ti:{} | xargs kill",
                    requested_port, requested_port
                );
                eprintln!("   2. Use a different port: CC_SWITCH_PORT=8080 ./cc-switch-web");
                eprintln!();
                std::process::exit(1);
            }
        }
    } else {
        eprintln!();
        eprintln!(
            "❌ Error: Port {} is already in use on {}",
            requested_port, host
        );
        if !is_loopback {
            eprintln!(
                "   Remote-access mode requires a stable host/port and will not auto-switch ports."
            );
        }
        eprintln!();
        eprintln!("   Solutions:");
        eprintln!("   1. Stop the process using this port:");
        eprintln!("      lsof -ti:{} | xargs kill", requested_port);
        eprintln!();
        eprintln!("   2. Use a different port:");
        eprintln!("      CC_SWITCH_PORT=8080 ./cc-switch-web");
        if is_loopback {
            eprintln!();
            eprintln!("   3. Enable auto-port selection:");
            eprintln!("      CC_SWITCH_AUTO_PORT=true ./cc-switch-web");
        }
        eprintln!();
        std::process::exit(1);
    };

    let addr = format!("{}:{}", host, port);

    println!();
    println!("╔════════════════════════════════════════════════════╗");
    println!("║           CC-Switch Web Server v0.1.0              ║");
    println!("╠════════════════════════════════════════════════════╣");
    if degraded {
        println!("║  🩺 Health:    http://{}:{}/health{:11}║", host, port, "");
        println!(
            "║  ℹ️  Build info: http://{}:{}/build-info.json{:3}║",
            host, port, ""
        );
    } else {
        if has_frontend {
            println!("║  🌐 Web UI:    http://{}:{:<21}║", host, port);
        }
        println!("║  📡 API:       http://{}:{}/api{:14}║", host, port, "");
        println!("║  🔌 WebSocket: ws://{}:{}/api/ws{:11}║", host, port, "");
    }
    println!("╠════════════════════════════════════════════════════╣");
    if !degraded && !is_loopback {
        println!("║  🔒 Auth:      Enable ~/.cc-switch/web-auth.json   ║");
        println!("║  📥 SQL Upload: POST /api/import-config            ║");
        println!("║  📤 SQL Export: GET  /api/export-config            ║");
        println!("╠════════════════════════════════════════════════════╣");
    }
    if degraded {
        println!("║  ⚠️  Degraded mode: DB schema is too new           ║");
        println!("║     Only health/build-info endpoints are served    ║");
        println!("╠════════════════════════════════════════════════════╣");
    }
    println!("║  Press Ctrl+C to stop                              ║");
    println!("╚════════════════════════════════════════════════════╝");
    println!();

    if !degraded && !is_loopback {
        tracing::info!("Remote access enabled on http://{}", addr);
        if let Some(state) = &state {
            if state.auth_config.is_some() {
                tracing::info!("Authenticated SQL upload available at /api/import-config");
                tracing::info!("Authenticated SQL export available at /api/export-config");
            } else {
                tracing::warn!("Remote access is enabled without web-auth.json; authenticated upload protection is disabled");
            }
        }
    }

    if degraded {
        tracing::warn!(
            "Starting CC-Switch server in degraded health-only mode on {}",
            addr
        );
    } else {
        tracing::info!("Starting CC-Switch server on {}", addr);
    }

    if let Err(e) = std_listener.set_nonblocking(true) {
        eprintln!("❌ Failed to configure listener for {}: {}", addr, e);
        std::process::exit(1);
    }

    let listener = match tokio::net::TcpListener::from_std(std_listener) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("❌ Failed to attach listener to {}: {}", addr, e);
            std::process::exit(1);
        }
    };

    if let Err(e) = axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    {
        eprintln!("❌ Server error: {}", e);
        std::process::exit(1);
    }
}
