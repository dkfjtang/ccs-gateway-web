use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;

use crate::rpc::RpcError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CcsWebProfile {
    Full,
    Slim,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CapabilityGroup {
    Auth,
    Providers,
    Proxy,
    Failover,
    Usage,
    Backup,
    ImportExport,
    Sync,
    SettingsBasic,
    Protocol,
    DesktopHelpers,
    Skills,
    Mcp,
    Sessions,
    Workspace,
    DailyMemory,
    ThirdPartyLocalTools,
    LocalEnvHelpers,
    AuthVault,
}

#[derive(Debug, Clone, Serialize)]
pub struct CapabilityManifest {
    pub profile: CcsWebProfile,
    pub enabled_groups: Vec<CapabilityGroup>,
    pub disabled_groups: Vec<CapabilityGroup>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProfileConfig {
    pub profile: CcsWebProfile,
}

impl ProfileConfig {
    pub fn from_env() -> Result<Self, String> {
        Self::from_env_value(std::env::var("CCS_WEB_PROFILE").ok().as_deref())
    }

    pub fn from_env_value(value: Option<&str>) -> Result<Self, String> {
        let raw = value.unwrap_or("full").trim();
        let profile = match raw.to_ascii_lowercase().as_str() {
            "" | "full" => CcsWebProfile::Full,
            "slim" => CcsWebProfile::Slim,
            other => return Err(format!("invalid CCS_WEB_PROFILE value: {other}")),
        };
        Ok(Self { profile })
    }

    pub fn manifest(&self) -> CapabilityManifest {
        let all = all_groups();
        let enabled: BTreeSet<_> = all
            .iter()
            .copied()
            .filter(|group| self.is_group_enabled(*group))
            .collect();
        let disabled = all
            .into_iter()
            .filter(|group| !enabled.contains(group))
            .collect();
        CapabilityManifest {
            profile: self.profile,
            enabled_groups: enabled.into_iter().collect(),
            disabled_groups: disabled,
        }
    }

    pub fn is_group_enabled(&self, group: CapabilityGroup) -> bool {
        if self.profile == CcsWebProfile::Full {
            return true;
        }
        !matches!(
            group,
            CapabilityGroup::DesktopHelpers
                | CapabilityGroup::Skills
                | CapabilityGroup::Mcp
                | CapabilityGroup::Sessions
                | CapabilityGroup::Workspace
                | CapabilityGroup::DailyMemory
                | CapabilityGroup::ThirdPartyLocalTools
                | CapabilityGroup::LocalEnvHelpers
                | CapabilityGroup::AuthVault
        )
    }

    pub fn ensure_group_allowed(&self, group: CapabilityGroup) -> Result<(), RpcError> {
        if self.is_group_enabled(group) {
            Ok(())
        } else {
            Err(RpcError::capability_disabled(group.as_str(), None))
        }
    }

    pub fn ensure_command_allowed(&self, command: &str) -> Result<(), RpcError> {
        match command_capability_group(command) {
            Some(group) if self.is_group_enabled(group) => Ok(()),
            Some(group) => Err(RpcError::capability_disabled(group.as_str(), Some(command))),
            None if self.profile == CcsWebProfile::Full => Ok(()),
            None => Err(RpcError::capability_disabled("unclassified", Some(command))),
        }
    }

    pub fn ensure_command_allowed_with_params(
        &self,
        command: &str,
        params: &Value,
    ) -> Result<(), RpcError> {
        self.ensure_command_allowed(command)?;

        if self.profile == CcsWebProfile::Slim {
            ensure_slim_params_allowed(command, params)?;
        }

        Ok(())
    }
}

fn is_third_party_local_tool_app(app: &str) -> bool {
    matches!(
        app.trim().to_ascii_lowercase().as_str(),
        "claude-desktop"
            | "claude_desktop"
            | "claudedesktop"
            | "opencode"
            | "openclaw"
            | "hermes"
            | "omo"
            | "omo-slim"
            | "omo_slim"
    )
}

fn ensure_slim_params_allowed(command: &str, params: &Value) -> Result<(), RpcError> {
    if app_values_in_value(params).any(is_third_party_local_tool_app) {
        return Err(RpcError::capability_disabled(
            CapabilityGroup::ThirdPartyLocalTools.as_str(),
            Some(command),
        ));
    }

    let Some(request) = params.get("request") else {
        return Ok(());
    };

    if request
        .get("app")
        .and_then(Value::as_str)
        .is_some_and(is_third_party_local_tool_app)
    {
        return Err(RpcError::capability_disabled(
            CapabilityGroup::ThirdPartyLocalTools.as_str(),
            Some(command),
        ));
    }

    if let Some(group) = request
        .get("resource")
        .and_then(Value::as_str)
        .and_then(deeplink_resource_capability_group)
    {
        let slim = ProfileConfig {
            profile: CcsWebProfile::Slim,
        };
        if !slim.is_group_enabled(group) {
            return Err(RpcError::capability_disabled(group.as_str(), Some(command)));
        }
    }

    Ok(())
}

fn app_values_in_value(value: &Value) -> impl Iterator<Item = &str> {
    let mut values = Vec::new();
    collect_app_values(value, &mut values);
    values.into_iter()
}

fn collect_app_values<'a>(value: &'a Value, values: &mut Vec<&'a str>) {
    match value {
        Value::Object(map) => {
            for (key, nested) in map {
                if is_app_param_key(key) {
                    if let Some(app) = nested.as_str() {
                        values.push(app);
                    }
                }
                collect_app_values(nested, values);
            }
        }
        Value::Array(items) => {
            for item in items {
                collect_app_values(item, values);
            }
        }
        _ => {}
    }
}

fn is_app_param_key(key: &str) -> bool {
    matches!(
        key,
        "app" | "appType" | "app_type" | "currentApp" | "current_app"
    )
}

fn deeplink_resource_capability_group(resource: &str) -> Option<CapabilityGroup> {
    match resource.trim().to_ascii_lowercase().as_str() {
        "provider" => Some(CapabilityGroup::Providers),
        "prompt" => Some(CapabilityGroup::ThirdPartyLocalTools),
        "mcp" => Some(CapabilityGroup::Mcp),
        "skill" => Some(CapabilityGroup::Skills),
        _ => None,
    }
}

impl Default for ProfileConfig {
    fn default() -> Self {
        Self {
            profile: CcsWebProfile::Full,
        }
    }
}

impl CapabilityGroup {
    pub fn as_str(self) -> &'static str {
        match self {
            CapabilityGroup::Auth => "auth",
            CapabilityGroup::Providers => "providers",
            CapabilityGroup::Proxy => "proxy",
            CapabilityGroup::Failover => "failover",
            CapabilityGroup::Usage => "usage",
            CapabilityGroup::Backup => "backup",
            CapabilityGroup::ImportExport => "import-export",
            CapabilityGroup::Sync => "sync",
            CapabilityGroup::SettingsBasic => "settings-basic",
            CapabilityGroup::Protocol => "protocol",
            CapabilityGroup::DesktopHelpers => "desktop-helpers",
            CapabilityGroup::Skills => "skills",
            CapabilityGroup::Mcp => "mcp",
            CapabilityGroup::Sessions => "sessions",
            CapabilityGroup::Workspace => "workspace",
            CapabilityGroup::DailyMemory => "daily-memory",
            CapabilityGroup::ThirdPartyLocalTools => "third-party-local-tools",
            CapabilityGroup::LocalEnvHelpers => "local-env-helpers",
            CapabilityGroup::AuthVault => "auth-vault",
        }
    }
}

pub fn all_groups() -> Vec<CapabilityGroup> {
    vec![
        CapabilityGroup::Auth,
        CapabilityGroup::Providers,
        CapabilityGroup::Proxy,
        CapabilityGroup::Failover,
        CapabilityGroup::Usage,
        CapabilityGroup::Backup,
        CapabilityGroup::ImportExport,
        CapabilityGroup::Sync,
        CapabilityGroup::SettingsBasic,
        CapabilityGroup::Protocol,
        CapabilityGroup::DesktopHelpers,
        CapabilityGroup::Skills,
        CapabilityGroup::Mcp,
        CapabilityGroup::Sessions,
        CapabilityGroup::Workspace,
        CapabilityGroup::DailyMemory,
        CapabilityGroup::ThirdPartyLocalTools,
        CapabilityGroup::LocalEnvHelpers,
        CapabilityGroup::AuthVault,
    ]
}

pub const DISABLED_IN_SLIM_GROUPS: &[CapabilityGroup] = &[
    CapabilityGroup::DesktopHelpers,
    CapabilityGroup::Skills,
    CapabilityGroup::Mcp,
    CapabilityGroup::Sessions,
    CapabilityGroup::Workspace,
    CapabilityGroup::DailyMemory,
    CapabilityGroup::ThirdPartyLocalTools,
    CapabilityGroup::LocalEnvHelpers,
    CapabilityGroup::AuthVault,
];

pub const AUTH_COMMANDS: &[&str] = &["auth.status", "auth.login", "auth.check"];
pub const PROVIDERS_COMMANDS: &[&str] = &[
    "get_providers",
    "get_current_provider",
    "add_provider",
    "update_provider",
    "delete_provider",
    "switch_provider",
    "import_default_config",
    "update_providers_sort_order",
    "fetch_models_for_config",
    "get_universal_providers",
    "get_universal_provider",
    "upsert_universal_provider",
    "delete_universal_provider",
    "sync_universal_provider",
];
pub const PROXY_COMMANDS: &[&str] = &[
    "start_proxy_server",
    "stop_proxy_server",
    "stop_proxy_with_restore",
    "get_proxy_takeover_status",
    "set_proxy_takeover_for_app",
    "get_proxy_status",
    "get_proxy_config",
    "update_proxy_config",
    "get_global_proxy_config",
    "update_global_proxy_config",
    "get_proxy_config_for_app",
    "update_proxy_config_for_app",
    "is_proxy_running",
    "is_live_takeover_active",
    "switch_proxy_provider",
    "test_api_endpoints",
    "get_custom_endpoints",
    "add_custom_endpoint",
    "remove_custom_endpoint",
    "update_endpoint_last_used",
    "stream_check_provider",
    "stream_check_all_providers",
    "get_stream_check_config",
    "save_stream_check_config",
    "get_global_proxy_url",
    "set_global_proxy_url",
    "test_proxy_url",
    "get_upstream_proxy_status",
    "scan_local_proxies",
];
pub const FAILOVER_COMMANDS: &[&str] = &[
    "get_provider_health",
    "reset_circuit_breaker",
    "get_circuit_breaker_config",
    "update_circuit_breaker_config",
    "get_circuit_breaker_stats",
    "get_failover_queue",
    "get_available_providers_for_failover",
    "add_to_failover_queue",
    "remove_from_failover_queue",
    "get_auto_failover_enabled",
    "set_auto_failover_enabled",
];
pub const USAGE_COMMANDS: &[&str] = &[
    "queryProviderUsage",
    "testUsageScript",
    "copilot_get_usage",
    "copilot_get_usage_for_account",
    "get_subscription_quota",
    "get_codex_oauth_quota",
    "get_coding_plan_quota",
    "get_balance",
    "get_usage_summary",
    "get_usage_summary_by_app",
    "get_usage_trends",
    "get_provider_stats",
    "get_model_stats",
    "get_request_logs",
    "get_request_detail",
    "sync_session_usage",
    "get_usage_data_sources",
    "get_model_pricing",
    "update_model_pricing",
    "delete_model_pricing",
    "check_provider_limits",
    "get_default_cost_multiplier",
    "set_default_cost_multiplier",
    "get_pricing_model_source",
    "set_pricing_model_source",
];
pub const BACKUP_COMMANDS: &[&str] = &[
    "create_db_backup",
    "list_db_backups",
    "restore_db_backup",
    "rename_db_backup",
    "delete_db_backup",
];
pub const IMPORT_EXPORT_COMMANDS: &[&str] = &[
    "export_config_to_file",
    "import_config_from_file",
    "parse_deeplink",
    "merge_deeplink_config",
    "import_from_deeplink",
    "import_from_deeplink_unified",
];
pub const SYNC_COMMANDS: &[&str] = &[
    "webdav_test_connection",
    "webdav_sync_upload",
    "webdav_sync_download",
    "webdav_sync_save_settings",
    "webdav_sync_fetch_remote_info",
    "s3_test_connection",
    "s3_sync_upload",
    "s3_sync_download",
    "s3_sync_save_settings",
    "s3_sync_fetch_remote_info",
];
pub const SETTINGS_BASIC_COMMANDS: &[&str] = &[
    "get_settings",
    "save_settings",
    "get_rectifier_config",
    "set_rectifier_config",
    "get_optimizer_config",
    "set_optimizer_config",
    "get_log_config",
    "set_log_config",
    "get_claude_config_status",
    "get_config_status",
    "is_portable_mode",
    "get_config_dir",
    "get_claude_code_config_path",
    "get_app_config_path",
    "get_app_config_dir_override",
    "set_app_config_dir_override",
    "extract_common_config_snippet",
    "get_init_error",
    "get_migration_result",
];
pub const PROTOCOL_COMMANDS: &[&str] = &["ping"];
pub const DESKTOP_HELPERS_COMMANDS: &[&str] = &[
    "update_tray_menu",
    "restart_app",
    "check_for_updates",
    "open_config_folder",
    "open_app_config_folder",
    "open_external",
    "set_auto_launch",
    "get_auto_launch_status",
    "set_window_theme",
    "open_provider_terminal",
    "save_file_dialog",
    "open_file_dialog",
    "open_zip_file_dialog",
];
pub const SKILLS_COMMANDS: &[&str] = &[
    "get_installed_skills",
    "get_skill_backups",
    "delete_skill_backup",
    "discover_available_skills",
    "check_skill_updates",
    "get_skills_for_app",
    "install_skill",
    "install_skill_for_app",
    "uninstall_skill",
    "uninstall_skill_for_app",
    "install_skill_unified",
    "uninstall_skill_unified",
    "restore_skill_backup",
    "toggle_skill_app",
    "scan_unmanaged_skills",
    "import_skills_from_apps",
    "update_skill",
    "migrate_skill_storage",
    "search_skills_sh",
    "get_skill_repos",
    "add_skill_repo",
    "remove_skill_repo",
    "install_skills_from_zip",
    "get_skills_migration_result",
    "get_skills",
];
pub const MCP_COMMANDS: &[&str] = &[
    "import_mcp_from_apps",
    "get_mcp_servers",
    "get_claude_mcp_status",
    "read_claude_mcp_config",
    "upsert_claude_mcp_server",
    "delete_claude_mcp_server",
    "validate_mcp_command",
    "get_mcp_config",
    "upsert_mcp_server_in_config",
    "delete_mcp_server_in_config",
    "set_mcp_enabled",
    "upsert_mcp_server",
    "delete_mcp_server",
    "toggle_mcp_app",
];
pub const SESSIONS_COMMANDS: &[&str] = &[
    "list_sessions",
    "get_session_messages",
    "launch_session_terminal",
    "delete_session",
    "delete_sessions",
];
pub const WORKSPACE_COMMANDS: &[&str] = &[
    "read_workspace_file",
    "write_workspace_file",
    "open_workspace_directory",
];
pub const DAILY_MEMORY_COMMANDS: &[&str] = &[
    "list_daily_memory_files",
    "read_daily_memory_file",
    "write_daily_memory_file",
    "delete_daily_memory_file",
    "search_daily_memory_files",
];
pub const THIRD_PARTY_LOCAL_TOOLS_COMMANDS: &[&str] = &[
    "read_live_provider_settings",
    "sync_current_providers_live",
    "remove_provider_from_live_config",
    "import_claude_desktop_providers_from_claude",
    "get_claude_desktop_status",
    "get_claude_desktop_default_routes",
    "apply_claude_plugin_config",
    "get_claude_plugin_status",
    "read_claude_plugin_config",
    "is_claude_plugin_applied",
    "apply_claude_onboarding_skip",
    "clear_claude_onboarding_skip",
    "get_hermes_model_config",
    "get_hermes_memory",
    "set_hermes_memory",
    "get_hermes_memory_limits",
    "set_hermes_memory_enabled",
    "open_hermes_web_ui",
    "launch_hermes_dashboard",
    "import_hermes_providers_from_live",
    "get_hermes_live_provider_ids",
    "scan_openclaw_config_health",
    "get_openclaw_default_model",
    "set_openclaw_default_model",
    "get_openclaw_model_catalog",
    "set_openclaw_model_catalog",
    "get_openclaw_agents_defaults",
    "set_openclaw_agents_defaults",
    "get_openclaw_env",
    "set_openclaw_env",
    "get_openclaw_tools",
    "set_openclaw_tools",
    "import_openclaw_providers_from_live",
    "get_openclaw_live_provider_ids",
    "get_openclaw_live_provider",
    "read_omo_local_file",
    "get_current_omo_provider_id",
    "disable_current_omo",
    "read_omo_slim_local_file",
    "get_current_omo_slim_provider_id",
    "disable_current_omo_slim",
    "import_opencode_providers_from_live",
    "get_opencode_live_provider_ids",
    "auth_start_login",
    "auth_poll_for_account",
    "auth_list_accounts",
    "auth_get_status",
    "auth_remove_account",
    "auth_set_default_account",
    "auth_logout",
    "copilot_start_device_flow",
    "copilot_poll_for_auth",
    "copilot_poll_for_account",
    "copilot_list_accounts",
    "copilot_remove_account",
    "copilot_set_default_account",
    "copilot_get_auth_status",
    "copilot_logout",
    "copilot_is_authenticated",
    "copilot_get_token",
    "copilot_get_token_for_account",
    "copilot_get_models",
    "copilot_get_models_for_account",
    "get_prompts",
    "upsert_prompt",
    "delete_prompt",
    "enable_prompt",
    "import_prompt_from_file",
    "get_current_prompt_file_content",
    "create_caveman_style_profile",
    "get_claude_common_config_snippet",
    "set_claude_common_config_snippet",
    "get_common_config_snippet",
    "set_common_config_snippet",
];
pub const LOCAL_ENV_HELPERS_COMMANDS: &[&str] = &[
    "pick_directory",
    "check_env_conflicts",
    "delete_env_vars",
    "restore_env_backup",
    "get_tool_versions",
];
pub const AUTH_VAULT_COMMANDS: &[&str] = &[];

pub fn classified_command_names() -> Vec<&'static str> {
    let mut commands = Vec::new();
    for group in [
        AUTH_COMMANDS,
        PROVIDERS_COMMANDS,
        PROXY_COMMANDS,
        FAILOVER_COMMANDS,
        USAGE_COMMANDS,
        BACKUP_COMMANDS,
        IMPORT_EXPORT_COMMANDS,
        SYNC_COMMANDS,
        SETTINGS_BASIC_COMMANDS,
        PROTOCOL_COMMANDS,
        DESKTOP_HELPERS_COMMANDS,
        SKILLS_COMMANDS,
        MCP_COMMANDS,
        SESSIONS_COMMANDS,
        WORKSPACE_COMMANDS,
        DAILY_MEMORY_COMMANDS,
        THIRD_PARTY_LOCAL_TOOLS_COMMANDS,
        LOCAL_ENV_HELPERS_COMMANDS,
        AUTH_VAULT_COMMANDS,
    ] {
        commands.extend_from_slice(group);
    }
    commands.sort_unstable();
    commands.dedup();
    commands
}

pub fn command_capability_group(command: &str) -> Option<CapabilityGroup> {
    if AUTH_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Auth);
    }
    if PROVIDERS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Providers);
    }
    if PROXY_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Proxy);
    }
    if FAILOVER_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Failover);
    }
    if USAGE_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Usage);
    }
    if BACKUP_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Backup);
    }
    if IMPORT_EXPORT_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::ImportExport);
    }
    if SYNC_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Sync);
    }
    if SETTINGS_BASIC_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::SettingsBasic);
    }
    if PROTOCOL_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Protocol);
    }
    if DESKTOP_HELPERS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::DesktopHelpers);
    }
    if SKILLS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Skills);
    }
    if MCP_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Mcp);
    }
    if SESSIONS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Sessions);
    }
    if WORKSPACE_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::Workspace);
    }
    if DAILY_MEMORY_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::DailyMemory);
    }
    if THIRD_PARTY_LOCAL_TOOLS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::ThirdPartyLocalTools);
    }
    if LOCAL_ENV_HELPERS_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::LocalEnvHelpers);
    }
    if AUTH_VAULT_COMMANDS.contains(&command) {
        return Some(CapabilityGroup::AuthVault);
    }
    None
}
