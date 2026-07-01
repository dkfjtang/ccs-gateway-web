use chrono::{DateTime, Duration, Utc};
use serde::Serialize;
use std::sync::{Arc, Mutex};

use cc_switch_core::CoreContext;

use crate::auth::{AuthConfig, SessionStore};
use crate::build_info::BuildInfo;
use crate::events::EventSender;
use crate::profile::ProfileConfig;

pub struct ServerState {
    pub auth_token: Option<String>,
    pub event_bus: EventSender,
    pub core: CoreContext,
    pub session_store: Arc<SessionStore>,
    pub auth_config: Option<AuthConfig>,
    pub allow_extension_session_header: bool,
    pub profile: ProfileConfig,
    pub build_info: BuildInfo,
    pub auth_vault_receive_window: AuthVaultReceiveWindow,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AuthVaultReceiveCloseReason {
    Manual,
    Expired,
    Success,
    FailureLimit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthVaultReceiveBegin {
    Claimed,
    NeverOpened,
    Closed,
    Busy,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthVaultReceiveWindowStatus {
    pub enabled: bool,
    pub status: &'static str,
    pub expires_at: Option<String>,
    pub remaining_seconds: Option<i64>,
    pub failure_count: u8,
    pub closed_reason: Option<AuthVaultReceiveCloseReason>,
}

#[derive(Debug, Clone)]
struct AuthVaultReceiveWindowInner {
    expires_at: Option<DateTime<Utc>>,
    failure_count: u8,
    closed_reason: Option<AuthVaultReceiveCloseReason>,
    in_progress: bool,
}

#[derive(Debug)]
pub struct AuthVaultReceiveWindow {
    inner: Mutex<AuthVaultReceiveWindowInner>,
}

impl Default for AuthVaultReceiveWindow {
    fn default() -> Self {
        Self {
            inner: Mutex::new(AuthVaultReceiveWindowInner {
                expires_at: None,
                failure_count: 0,
                closed_reason: None,
                in_progress: false,
            }),
        }
    }
}

impl AuthVaultReceiveWindow {
    const DEFAULT_WINDOW_SECONDS: i64 = 5 * 60;
    const MAX_FAILURES: u8 = 5;

    pub fn open_default(&self) -> AuthVaultReceiveWindowStatus {
        self.open_for_seconds(Self::DEFAULT_WINDOW_SECONDS)
    }

    pub fn open_for_seconds(&self, seconds: i64) -> AuthVaultReceiveWindowStatus {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        inner.expires_at = Some(Utc::now() + Duration::seconds(seconds));
        inner.failure_count = 0;
        inner.closed_reason = None;
        inner.in_progress = false;
        Self::status_from_inner(&mut inner)
    }

    pub fn close_manual(&self) -> AuthVaultReceiveWindowStatus {
        self.close(AuthVaultReceiveCloseReason::Manual)
    }

    pub fn close_success(&self) -> AuthVaultReceiveWindowStatus {
        self.close(AuthVaultReceiveCloseReason::Success)
    }

    pub fn status(&self) -> AuthVaultReceiveWindowStatus {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        Self::status_from_inner(&mut inner)
    }

    pub fn begin_receive(&self) -> AuthVaultReceiveBegin {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        if !Self::is_inner_open(&mut inner) {
            return if inner.closed_reason.is_none() {
                AuthVaultReceiveBegin::NeverOpened
            } else {
                AuthVaultReceiveBegin::Closed
            };
        }
        if inner.in_progress {
            return AuthVaultReceiveBegin::Busy;
        }
        inner.in_progress = true;
        AuthVaultReceiveBegin::Claimed
    }

    pub fn record_failure(&self) -> AuthVaultReceiveWindowStatus {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        Self::record_failure_from_inner(&mut inner)
    }

    pub fn finish_receive_failure(&self) -> AuthVaultReceiveWindowStatus {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        inner.in_progress = false;
        Self::record_failure_from_inner(&mut inner)
    }

    fn record_failure_from_inner(
        inner: &mut AuthVaultReceiveWindowInner,
    ) -> AuthVaultReceiveWindowStatus {
        if Self::is_inner_open(inner) {
            inner.failure_count = inner.failure_count.saturating_add(1);
            if inner.failure_count >= Self::MAX_FAILURES {
                inner.expires_at = None;
                inner.closed_reason = Some(AuthVaultReceiveCloseReason::FailureLimit);
                inner.in_progress = false;
            }
        }
        Self::status_from_inner(inner)
    }

    fn close(&self, reason: AuthVaultReceiveCloseReason) -> AuthVaultReceiveWindowStatus {
        let mut inner = self.inner.lock().expect("auth vault receive window lock");
        inner.expires_at = None;
        inner.closed_reason = Some(reason);
        inner.in_progress = false;
        Self::status_from_inner(&mut inner)
    }

    fn is_inner_open(inner: &mut AuthVaultReceiveWindowInner) -> bool {
        match inner.expires_at {
            Some(expires_at) if expires_at > Utc::now() => true,
            Some(_) => {
                inner.expires_at = None;
                inner.closed_reason = Some(AuthVaultReceiveCloseReason::Expired);
                inner.in_progress = false;
                false
            }
            None => false,
        }
    }

    fn status_from_inner(inner: &mut AuthVaultReceiveWindowInner) -> AuthVaultReceiveWindowStatus {
        let enabled = Self::is_inner_open(inner);
        let now = Utc::now();
        let remaining_seconds = inner
            .expires_at
            .map(|expires_at| (expires_at - now).num_seconds().max(0));
        AuthVaultReceiveWindowStatus {
            enabled,
            status: if enabled { "open" } else { "closed" },
            expires_at: inner.expires_at.map(|expires_at| expires_at.to_rfc3339()),
            remaining_seconds,
            failure_count: inner.failure_count,
            closed_reason: inner.closed_reason.clone(),
        }
    }
}

impl ServerState {
    pub fn new(
        auth_token: Option<String>,
        event_bus: EventSender,
        session_store: Arc<SessionStore>,
        auth_config: Option<AuthConfig>,
        allow_extension_session_header: bool,
        profile: ProfileConfig,
        build_info: BuildInfo,
    ) -> Arc<Self> {
        // 初始化核心上下文（数据库、SkillService 等）
        let core = CoreContext::new().unwrap_or_else(|e| {
            panic!("failed to initialize cc-switch core context: {e}");
        });
        Arc::new(Self {
            auth_token,
            event_bus,
            core,
            session_store,
            auth_config,
            allow_extension_session_header,
            profile,
            build_info,
            auth_vault_receive_window: AuthVaultReceiveWindow::default(),
        })
    }
}
