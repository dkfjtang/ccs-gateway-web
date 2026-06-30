use axum::http::HeaderMap;
use std::net::SocketAddr;

use crate::state::ServerState;

pub(crate) const SESSION_COOKIE_NAME: &str = "cc-switch-session";

pub(crate) fn extract_session_cookie(headers: &HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::COOKIE)?
        .to_str()
        .ok()?
        .split(';')
        .find_map(|cookie| {
            let cookie = cookie.trim();
            if cookie.starts_with(SESSION_COOKIE_NAME) {
                cookie
                    .strip_prefix(SESSION_COOKIE_NAME)
                    .and_then(|s| s.strip_prefix('='))
                    .map(|s| s.to_string())
            } else {
                None
            }
        })
}

pub(crate) fn has_valid_session(state: &ServerState, headers: &HeaderMap) -> bool {
    extract_session_cookie(headers)
        .map(|token| state.session_store.validate_session(&token))
        .unwrap_or(false)
}

pub(crate) fn is_loopback_peer(addr: &SocketAddr) -> bool {
    addr.ip().is_loopback()
}

pub(crate) fn has_valid_session_from_header(state: &ServerState, headers: &HeaderMap) -> bool {
    headers
        .get("x-ccs-session")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .map(|token| state.session_store.validate_session(token))
        .unwrap_or(false)
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

    fn test_state() -> ServerState {
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
            allow_extension_session_header: true,
            profile,
            build_info,
        }
    }

    #[test]
    fn validates_session_from_extension_header() {
        let state = test_state();
        let token = state.session_store.create_session();
        let mut headers = HeaderMap::new();
        headers.insert("x-ccs-session", HeaderValue::from_str(&token).unwrap());

        assert!(has_valid_session_from_header(&state, &headers));
    }

    #[test]
    fn rejects_invalid_extension_header_session() {
        let state = test_state();
        let mut headers = HeaderMap::new();
        headers.insert("x-ccs-session", HeaderValue::from_static("invalid"));

        assert!(!has_valid_session_from_header(&state, &headers));
    }

    #[test]
    fn recognizes_loopback_peers_only() {
        assert!(is_loopback_peer(&"127.0.0.1:17666".parse().unwrap()));
        assert!(is_loopback_peer(&"[::1]:17666".parse().unwrap()));
        assert!(!is_loopback_peer(&"192.0.2.10:17666".parse().unwrap()));
    }
}
