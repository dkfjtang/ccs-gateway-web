use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::sync::RwLock;
use std::time::{Duration, Instant};

use crate::profile::{CcsWebProfile, ProfileConfig};

/// Session expiry duration: 7 days (604800 seconds)
const SESSION_EXPIRY_SECS: u64 = 604800;

/// Configuration for web authentication
#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    pub password_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthConfigLoadError {
    HomeDirUnavailable,
    MissingConfig,
    UnreadableConfig,
    InvalidJson,
    EmptyPasswordHash,
    InvalidPasswordHash,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthPolicyError {
    pub reason: AuthConfigLoadError,
}

/// Represents an active user session
#[derive(Debug, Clone)]
pub struct Session {
    pub token: String,
    pub created_at: Instant,
    pub expires_at: Instant,
}

/// In-memory session store with thread-safe access
pub struct SessionStore {
    sessions: RwLock<HashMap<String, Session>>,
}

impl SessionStore {
    pub fn new() -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
        }
    }

    /// Creates a new session and returns the token
    pub fn create_session(&self) -> String {
        use rand::Rng;

        let mut rng = rand::thread_rng();
        let mut bytes = [0u8; 32];
        rng.fill(&mut bytes);
        let token = hex::encode(bytes);

        let now = Instant::now();
        let session = Session {
            token: token.clone(),
            created_at: now,
            expires_at: now + Duration::from_secs(SESSION_EXPIRY_SECS),
        };

        let mut sessions = self.sessions.write().unwrap();
        sessions.insert(token.clone(), session);
        token
    }

    /// Validates a session token
    pub fn validate_session(&self, token: &str) -> bool {
        let sessions = self.sessions.read().unwrap();
        if let Some(session) = sessions.get(token) {
            Instant::now() < session.expires_at
        } else {
            false
        }
    }

    /// Removes expired sessions
    pub fn cleanup_expired(&self) {
        let now = Instant::now();
        let mut sessions = self.sessions.write().unwrap();
        sessions.retain(|_, session| now < session.expires_at);
    }
}

impl Default for SessionStore {
    fn default() -> Self {
        Self::new()
    }
}

/// Loads authentication configuration from ~/.cc-switch/web-auth.json.
/// Returns a structured error so slim production startup can fail closed.
pub fn load_auth_config_result() -> Result<AuthConfig, AuthConfigLoadError> {
    let home = dirs::home_dir().ok_or(AuthConfigLoadError::HomeDirUnavailable)?;
    let config_path = home.join(".cc-switch").join("web-auth.json");

    let content = fs::read_to_string(&config_path).map_err(|err| {
        if err.kind() == io::ErrorKind::NotFound {
            AuthConfigLoadError::MissingConfig
        } else {
            AuthConfigLoadError::UnreadableConfig
        }
    })?;
    parse_auth_config(&content)
}

/// Loads authentication configuration from ~/.cc-switch/web-auth.json.
/// Returns None if file is missing or invalid (legacy full-profile behavior).
pub fn load_auth_config() -> Option<AuthConfig> {
    load_auth_config_result().ok()
}

pub fn parse_auth_config(content: &str) -> Result<AuthConfig, AuthConfigLoadError> {
    let mut config: AuthConfig =
        serde_json::from_str(content).map_err(|_| AuthConfigLoadError::InvalidJson)?;
    config.password_hash = config.password_hash.trim().to_string();

    if config.password_hash.is_empty() {
        return Err(AuthConfigLoadError::EmptyPasswordHash);
    }
    if bcrypt::verify("__ccs_web_auth_probe__", &config.password_hash).is_err() {
        return Err(AuthConfigLoadError::InvalidPasswordHash);
    }

    Ok(config)
}

pub fn slim_no_auth_override_enabled() -> bool {
    slim_no_auth_override_value_enabled(std::env::var("CCS_WEB_SLIM_ALLOW_NO_AUTH").ok().as_deref())
}

pub fn slim_no_auth_override_value_enabled(value: Option<&str>) -> bool {
    value
        .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
}

pub fn auth_config_for_profile(
    profile: &ProfileConfig,
    result: Result<AuthConfig, AuthConfigLoadError>,
    allow_slim_no_auth: bool,
) -> Result<Option<AuthConfig>, AuthPolicyError> {
    match (profile.profile, result) {
        (_, Ok(config)) => Ok(Some(config)),
        (
            CcsWebProfile::Full,
            Err(AuthConfigLoadError::HomeDirUnavailable | AuthConfigLoadError::MissingConfig),
        ) => Ok(None),
        (CcsWebProfile::Full, Err(reason)) => Err(AuthPolicyError { reason }),
        (CcsWebProfile::Slim, Err(_)) if allow_slim_no_auth => Ok(None),
        (CcsWebProfile::Slim, Err(reason)) => Err(AuthPolicyError { reason }),
    }
}

/// Verifies a password against a bcrypt hash
/// Returns false for any error (invalid hash, wrong password, etc.)
pub fn verify_password(password: &str, hash: &str) -> bool {
    bcrypt::verify(password, hash).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_store_create_and_validate() {
        let store = SessionStore::new();
        let token = store.create_session();

        assert_eq!(token.len(), 64); // 32 bytes = 64 hex chars
        assert!(store.validate_session(&token));
        assert!(!store.validate_session("invalid_token"));
    }

    #[test]
    fn test_session_token_is_unique() {
        let store = SessionStore::new();
        let token1 = store.create_session();
        let token2 = store.create_session();
        assert_ne!(token1, token2);
    }

    #[test]
    fn test_verify_password_with_valid_hash() {
        // Pre-generated bcrypt hash for "test123" with cost 4 (for fast tests)
        let hash = "$2b$04$MJuc/Azj7j9Js28.20f31uIhhVpf8f1GqCdPbh3D5StxPf8/FxYSi";
        assert!(verify_password("test123", hash));
        assert!(!verify_password("wrong", hash));
    }

    #[test]
    fn test_verify_password_with_invalid_hash() {
        assert!(!verify_password("test", "invalid_hash"));
        assert!(!verify_password("test", ""));
    }

    #[test]
    fn test_parse_auth_config_rejects_invalid_config() {
        assert!(matches!(
            parse_auth_config("{not-json"),
            Err(AuthConfigLoadError::InvalidJson)
        ));
        assert!(matches!(
            parse_auth_config(r#"{"password_hash":""}"#),
            Err(AuthConfigLoadError::EmptyPasswordHash)
        ));
        assert!(matches!(
            parse_auth_config(r#"{"password_hash":"not-a-bcrypt-hash"}"#),
            Err(AuthConfigLoadError::InvalidPasswordHash)
        ));
    }

    #[test]
    fn test_parse_auth_config_accepts_valid_hash() {
        let hash = "$2b$04$MJuc/Azj7j9Js28.20f31uIhhVpf8f1GqCdPbh3D5StxPf8/FxYSi";
        let config = parse_auth_config(&format!(r#"{{"password_hash":"{hash}"}}"#)).unwrap();
        assert_eq!(config.password_hash, hash);
    }

    #[test]
    fn test_load_auth_config_missing_file() {
        // This test assumes no config file exists at the path
        // In a real test environment, we'd mock the filesystem
        // For now, we just verify the function doesn't panic
        let _ = load_auth_config();
    }
}
