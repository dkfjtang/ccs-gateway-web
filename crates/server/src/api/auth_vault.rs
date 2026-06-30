use axum::{
    extract::{connect_info::ConnectInfo, DefaultBodyLimit, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, net::SocketAddr, path::PathBuf, sync::Arc};

use crate::{
    api::session_auth::{has_valid_session, has_valid_session_from_header, is_loopback_peer},
    profile::{CapabilityGroup, ProfileConfig},
    state::ServerState,
};

#[derive(Debug, Deserialize)]
pub struct AuthVaultRequest {
    #[serde(default)]
    sites: HashMap<String, AuthSiteEntry>,
    #[serde(default, rename = "tokenVault")]
    token_vault: HashMap<String, AuthVaultEntry>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct AuthSiteEntry {
    origin: String,
    host: String,
    url: Option<String>,
    #[serde(rename = "capturedAt")]
    captured_at: Option<String>,
    #[serde(rename = "authToken")]
    auth_token: Option<String>,
    #[serde(rename = "authTokenSource")]
    auth_token_source: Option<String>,
    #[serde(rename = "authTokenPreview")]
    auth_token_preview: Option<String>,
    #[serde(rename = "cookieHeader")]
    cookie_header: Option<String>,
    #[serde(rename = "cookieNames", default)]
    cookie_names: Vec<String>,
    #[serde(rename = "cookieHeaderPreview")]
    cookie_header_preview: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct AuthVaultEntry {
    origin: Option<String>,
    url: Option<String>,
    #[serde(rename = "capturedAt")]
    captured_at: Option<String>,
    #[serde(rename = "tokenName")]
    token_name: Option<String>,
    source: Option<String>,
    value: String,
    preview: Option<String>,
    length: Option<Value>,
}

#[derive(Debug, Deserialize, Serialize)]
struct AuthVaultFile {
    #[serde(rename = "schemaVersion")]
    schema_version: u8,
    #[serde(rename = "updatedAt")]
    updated_at: String,
    #[serde(default)]
    sites: HashMap<String, AuthSiteEntry>,
    #[serde(default, rename = "tokenVault")]
    token_vault: HashMap<String, AuthVaultEntry>,
}

#[derive(Debug, Serialize)]
pub struct AuthVaultSummary {
    count: usize,
    #[serde(rename = "siteCount")]
    site_count: usize,
    sites: Vec<AuthSiteSummary>,
    tokens: Vec<AuthVaultTokenSummary>,
}

#[derive(Debug, Serialize)]
pub struct AuthSiteSummary {
    host: String,
    origin: String,
    #[serde(rename = "authTokenSource")]
    auth_token_source: Option<String>,
    #[serde(rename = "authTokenPreview")]
    auth_token_preview: Option<String>,
    #[serde(rename = "cookieNames")]
    cookie_names: Vec<String>,
    #[serde(rename = "cookieHeaderPreview")]
    cookie_header_preview: Option<String>,
    #[serde(rename = "capturedAt")]
    captured_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AuthVaultTokenSummary {
    #[serde(rename = "tokenName")]
    token_name: String,
    origin: Option<String>,
    source: Option<String>,
    preview: Option<String>,
    length: Option<Value>,
    #[serde(rename = "capturedAt")]
    captured_at: Option<String>,
}

fn vault_path() -> PathBuf {
    PathBuf::from(cc_switch_core::get_app_config_dir())
        .join("auth-vault")
        .join("tokens.json")
}

fn is_valid_host(host: &str) -> bool {
    !host.is_empty()
        && host.len() <= 253
        && host
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-'))
}

fn validate_sites(sites: &HashMap<String, AuthSiteEntry>) -> Result<(), String> {
    for (host, entry) in sites {
        if !is_valid_host(host) {
            return Err(format!("invalid site host: {host}"));
        }
        if entry.host.to_lowercase() != host.to_lowercase() {
            return Err(format!("site key/host mismatch: {host}"));
        }
        if entry.auth_token.as_deref().unwrap_or("").trim().is_empty()
            && entry
                .cookie_header
                .as_deref()
                .unwrap_or("")
                .trim()
                .is_empty()
        {
            return Err(format!("site has no authToken or cookieHeader: {host}"));
        }
    }

    Ok(())
}

fn validate_token_vault(vault: &HashMap<String, AuthVaultEntry>) -> Result<(), String> {
    for (token_name, entry) in vault {
        if token_name.is_empty()
            || token_name.len() > 160
            || !token_name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-' | b'.' | b':'))
        {
            return Err(format!("invalid token name: {token_name}"));
        }
        if entry.value.trim().len() < 20 {
            return Err(format!("invalid token value: {token_name}"));
        }
    }

    Ok(())
}

fn summarize(
    sites: &HashMap<String, AuthSiteEntry>,
    vault: &HashMap<String, AuthVaultEntry>,
) -> AuthVaultSummary {
    let mut site_summaries = sites
        .iter()
        .map(|(host, entry)| AuthSiteSummary {
            host: host.clone(),
            origin: entry.origin.clone(),
            auth_token_source: entry.auth_token_source.clone(),
            auth_token_preview: entry.auth_token_preview.clone(),
            cookie_names: entry.cookie_names.clone(),
            cookie_header_preview: entry.cookie_header_preview.clone(),
            captured_at: entry.captured_at.clone(),
        })
        .collect::<Vec<_>>();
    site_summaries.sort_by(|a, b| a.host.cmp(&b.host));

    let mut tokens = vault
        .iter()
        .map(|(token_name, entry)| AuthVaultTokenSummary {
            token_name: token_name.clone(),
            origin: entry.origin.clone(),
            source: entry.source.clone(),
            preview: entry.preview.clone(),
            length: entry.length.clone(),
            captured_at: entry.captured_at.clone(),
        })
        .collect::<Vec<_>>();
    tokens.sort_by(|a, b| a.token_name.cmp(&b.token_name));

    AuthVaultSummary {
        count: tokens.len(),
        site_count: site_summaries.len(),
        sites: site_summaries,
        tokens,
    }
}

fn unauthorized() -> (StatusCode, Json<Value>) {
    (
        StatusCode::UNAUTHORIZED,
        Json(serde_json::json!({
            "ok": false,
            "error": "Unauthorized"
        })),
    )
}

pub fn auth_vault_disabled() -> (StatusCode, Json<Value>) {
    (
        StatusCode::FORBIDDEN,
        Json(serde_json::json!({
            "error": "capability_disabled",
            "capability": "auth-vault",
            "message": "This capability is disabled in the current ccs-web profile."
        })),
    )
}

fn auth_vault_not_found() -> (StatusCode, Json<Value>) {
    (
        StatusCode::NOT_FOUND,
        Json(serde_json::json!({
            "error": "api_route_not_found",
            "message": "Unknown API route."
        })),
    )
}

fn is_save_authorized(state: &ServerState, headers: &HeaderMap, peer_addr: &SocketAddr) -> bool {
    state.auth_config.is_none()
        || has_valid_session(state, headers)
        || (state.allow_extension_session_header
            && is_loopback_peer(peer_addr)
            && has_valid_session_from_header(state, headers))
}

pub fn auth_vault_routes(profile: &ProfileConfig) -> Router<Arc<ServerState>> {
    if !profile.is_group_enabled(CapabilityGroup::AuthVault) {
        return Router::new().fallback(|| async { auth_vault_disabled() });
    }

    Router::new()
        .route(
            "/tokens",
            post(save_auth_vault_handler).layer(DefaultBodyLimit::max(1024 * 1024)),
        )
        .route("/tokens/summary", get(auth_vault_summary_handler))
        .fallback(|| async { auth_vault_not_found() })
}

pub async fn save_auth_vault_handler(
    ConnectInfo(peer_addr): ConnectInfo<SocketAddr>,
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
    Json(req): Json<AuthVaultRequest>,
) -> impl IntoResponse {
    if state
        .profile
        .ensure_group_allowed(CapabilityGroup::AuthVault)
        .is_err()
    {
        return auth_vault_disabled();
    }

    if !is_save_authorized(&state, &headers, &peer_addr) {
        return unauthorized();
    }

    if let Err(error) = validate_sites(&req.sites) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "ok": false, "error": error })),
        );
    }

    if let Err(error) = validate_token_vault(&req.token_vault) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "ok": false, "error": error })),
        );
    }

    let path = vault_path();
    let file = AuthVaultFile {
        schema_version: 1,
        updated_at: chrono::Utc::now().to_rfc3339(),
        sites: req.sites,
        token_vault: req.token_vault,
    };

    if let Some(parent) = path.parent() {
        if let Err(error) = std::fs::create_dir_all(parent) {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "ok": false, "error": error.to_string() })),
            );
        }
    }

    let temp_path = path.with_extension("json.tmp");
    let write_result = serde_json::to_vec_pretty(&file)
        .map_err(|error| error.to_string())
        .and_then(|bytes| std::fs::write(&temp_path, bytes).map_err(|error| error.to_string()))
        .and_then(|_| std::fs::rename(&temp_path, &path).map_err(|error| error.to_string()));

    if let Err(error) = write_result {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({ "ok": false, "error": error })),
        );
    }

    let summary = summarize(&file.sites, &file.token_vault);
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "count": summary.count,
            "siteCount": summary.site_count,
            "sites": summary.sites,
            "tokens": summary.tokens
        })),
    )
}

pub async fn auth_vault_summary_handler(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if state
        .profile
        .ensure_group_allowed(CapabilityGroup::AuthVault)
        .is_err()
    {
        return auth_vault_disabled();
    }

    if state.auth_config.is_some() && !has_valid_session(&state, &headers) {
        return unauthorized();
    }

    let path = vault_path();
    let file = std::fs::read_to_string(&path)
        .ok()
        .and_then(|raw| serde_json::from_str::<AuthVaultFile>(&raw).ok())
        .unwrap_or(AuthVaultFile {
            schema_version: 1,
            updated_at: String::new(),
            sites: HashMap::new(),
            token_vault: HashMap::new(),
        });
    let summary = summarize(&file.sites, &file.token_vault);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "count": summary.count,
            "siteCount": summary.site_count,
            "sites": summary.sites,
            "tokens": summary.tokens
        })),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        build_info::build_info_from_assets, create_event_bus, profile::ProfileConfig, AuthConfig,
        ServerState, SessionStore,
    };
    use axum::http::HeaderValue;
    use cc_switch::{AppState, Database};
    use cc_switch_core::CoreContext;
    use std::sync::Arc;

    fn test_state(allow_extension_session_header: bool) -> ServerState {
        let db = Arc::new(Database::memory().expect("in-memory database"));
        let profile = ProfileConfig::default();
        let build_info = build_info_from_assets(&profile, Vec::new(), "test");
        ServerState {
            auth_token: None,
            event_bus: create_event_bus(8),
            core: CoreContext::from_app_state(AppState::new(db)),
            session_store: Arc::new(SessionStore::new()),
            auth_config: Some(AuthConfig {
                password_hash: "test".to_string(),
            }),
            allow_extension_session_header,
            profile,
            build_info,
        }
    }

    #[test]
    fn summary_does_not_serialize_secret_values() {
        let sites = HashMap::from([(
            "example.com".to_string(),
            AuthSiteEntry {
                origin: "https://example.com".to_string(),
                host: "example.com".to_string(),
                url: Some("https://example.com/dashboard".to_string()),
                captured_at: Some("2026-06-17T00:00:00Z".to_string()),
                auth_token: Some("full-auth-token-value".to_string()),
                auth_token_source: Some("localStorage.auth_token".to_string()),
                auth_token_preview: Some("full-a...value len=21".to_string()),
                cookie_header: Some("session=full-cookie-value; csrf=full-csrf".to_string()),
                cookie_names: vec!["session".to_string(), "csrf".to_string()],
                cookie_header_preview: Some("session; csrf len=41".to_string()),
            },
        )]);
        let vault = HashMap::from([(
            "example_com__auth_token".to_string(),
            AuthVaultEntry {
                origin: Some("https://example.com".to_string()),
                url: None,
                captured_at: Some("2026-06-17T00:00:00Z".to_string()),
                token_name: Some("example_com__auth_token".to_string()),
                source: Some("localStorage.auth_token".to_string()),
                value: "full-named-token-value".to_string(),
                preview: Some("full-n...value len=22".to_string()),
                length: Some(serde_json::json!(22)),
            },
        )]);

        let summary = summarize(&sites, &vault);
        let body = serde_json::to_string(&summary).expect("serialize summary");

        assert!(!body.contains("full-auth-token-value"));
        assert!(!body.contains("full-cookie-value"));
        assert!(!body.contains("full-named-token-value"));
        assert!(!body.contains("\"authToken\":"));
        assert!(!body.contains("\"cookieHeader\":"));
        assert!(body.contains("full-a...value"));
        assert!(body.contains("session; csrf"));
    }

    #[test]
    fn save_auth_rejects_extension_header_when_server_is_not_loopback_bound() {
        let state = test_state(false);
        let token = state.session_store.create_session();
        let mut headers = HeaderMap::new();
        headers.insert("x-ccs-session", HeaderValue::from_str(&token).unwrap());

        assert!(!is_save_authorized(
            &state,
            &headers,
            &"127.0.0.1:17666".parse().unwrap()
        ));
    }

    #[test]
    fn save_auth_rejects_extension_header_from_non_loopback_peer() {
        let state = test_state(true);
        let token = state.session_store.create_session();
        let mut headers = HeaderMap::new();
        headers.insert("x-ccs-session", HeaderValue::from_str(&token).unwrap());

        assert!(!is_save_authorized(
            &state,
            &headers,
            &"192.0.2.10:17666".parse().unwrap()
        ));
    }

    #[test]
    fn save_auth_accepts_extension_header_only_when_bound_and_connected_on_loopback() {
        let state = test_state(true);
        let token = state.session_store.create_session();
        let mut headers = HeaderMap::new();
        headers.insert("x-ccs-session", HeaderValue::from_str(&token).unwrap());

        assert!(is_save_authorized(
            &state,
            &headers,
            &"127.0.0.1:17666".parse().unwrap()
        ));
    }
}
