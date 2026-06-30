use std::collections::BTreeSet;

use cc_switch_server::{
    api::{PUBLIC_METHODS, RPC_BUSINESS_METHODS},
    auth_config_for_profile,
    profile::{
        classified_command_names, CapabilityGroup, CcsWebProfile, ProfileConfig,
        DISABLED_IN_SLIM_GROUPS,
    },
    rpc::RpcError,
    AuthConfig, AuthConfigLoadError,
};
use serde_json::json;

#[test]
fn default_profile_is_full() {
    assert_eq!(
        ProfileConfig::from_env_value(None).unwrap().profile,
        CcsWebProfile::Full
    );
}

#[test]
fn explicit_profiles_are_validated() {
    assert_eq!(
        ProfileConfig::from_env_value(Some("full")).unwrap().profile,
        CcsWebProfile::Full
    );
    assert_eq!(
        ProfileConfig::from_env_value(Some("slim")).unwrap().profile,
        CcsWebProfile::Slim
    );
    assert!(ProfileConfig::from_env_value(Some("unexpected")).is_err());
}

#[test]
fn slim_disables_non_production_groups() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    assert!(!config.is_group_enabled(CapabilityGroup::Skills));
    assert!(!config.is_group_enabled(CapabilityGroup::Mcp));
    assert!(!config.is_group_enabled(CapabilityGroup::AuthVault));
    assert!(config.is_group_enabled(CapabilityGroup::Providers));
    assert!(config.is_group_enabled(CapabilityGroup::Usage));
    assert!(config.is_group_enabled(CapabilityGroup::Sync));
}

#[test]
fn full_enables_all_groups() {
    let config = ProfileConfig::from_env_value(Some("full")).unwrap();
    for group in cc_switch_server::profile::all_groups() {
        assert!(config.is_group_enabled(group), "group {group:?}");
    }
}

#[test]
fn manifest_reports_slim_disabled_groups() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    let manifest = config.manifest();
    let disabled: BTreeSet<_> = manifest.disabled_groups.into_iter().collect();
    let expected: BTreeSet<_> = DISABLED_IN_SLIM_GROUPS.iter().copied().collect();
    assert_eq!(disabled, expected);
}

#[test]
fn classified_commands_cover_rpc_business_methods() {
    let classified: BTreeSet<_> = classified_command_names().into_iter().collect();
    let mut expected: BTreeSet<_> = RPC_BUSINESS_METHODS.iter().copied().collect();
    expected.extend(PUBLIC_METHODS.iter().copied());
    expected.insert("ping");
    assert_eq!(classified, expected);
}

#[test]
fn unknown_commands_fail_closed_in_slim() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    let err = config
        .ensure_command_allowed("new_unclassified_command")
        .unwrap_err();
    assert_eq!(err.code, -32043);
    assert_eq!(err.data.as_ref().unwrap()["error"], "capability_disabled");
    assert_eq!(err.data.as_ref().unwrap()["capability"], "unclassified");
}

#[test]
fn retained_commands_stay_enabled_in_slim() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    for command in [
        "get_providers",
        "add_provider",
        "get_proxy_status",
        "get_usage_summary",
        "get_request_logs",
        "get_model_pricing",
        "get_default_cost_multiplier",
        "get_pricing_model_source",
        "webdav_sync_upload",
        "webdav_sync_download",
        "webdav_sync_save_settings",
        "webdav_sync_fetch_remote_info",
        "s3_sync_upload",
        "s3_sync_download",
        "s3_sync_save_settings",
        "s3_sync_fetch_remote_info",
        "create_db_backup",
        "export_config_to_file",
        "auth.status",
        "auth.login",
        "auth.check",
    ] {
        config.ensure_command_allowed(command).unwrap();
    }
}

#[test]
fn slim_rejects_switch_provider_for_local_tool_apps() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();

    for app in ["claude-desktop", "opencode", "openclaw", "hermes"] {
        let err = config
            .ensure_command_allowed_with_params(
                "switch_provider",
                &json!({ "app": app, "id": "provider-1" }),
            )
            .unwrap_err();
        assert_eq!(err.code, -32043, "{app}");
        assert_eq!(
            err.data.as_ref().unwrap()["capability"],
            "third-party-local-tools",
            "{app}"
        );
    }

    for app in ["claude", "codex", "gemini"] {
        config
            .ensure_command_allowed_with_params(
                "switch_provider",
                &json!({ "app": app, "id": "provider-1" }),
            )
            .unwrap();
    }
}

#[test]
fn slim_rejects_local_tool_app_scoped_retained_commands() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();

    for command in [
        "get_providers",
        "add_provider",
        "update_provider",
        "delete_provider",
        "import_default_config",
        "update_providers_sort_order",
        "get_custom_endpoints",
        "add_custom_endpoint",
        "stream_check_provider",
        "get_failover_queue",
        "get_usage_summary",
    ] {
        let app_key = if matches!(
            command,
            "stream_check_provider" | "get_failover_queue" | "get_usage_summary"
        ) {
            "appType"
        } else {
            "app"
        };
        let err = config
            .ensure_command_allowed_with_params(command, &json!({ app_key: "openclaw" }))
            .unwrap_err();
        assert_eq!(err.code, -32043, "{command}");
        assert_eq!(
            err.data.as_ref().unwrap()["capability"],
            "third-party-local-tools",
            "{command}"
        );
    }

    for command in [
        "get_providers",
        "add_provider",
        "stream_check_provider",
        "get_usage_summary",
    ] {
        let app_key = if matches!(command, "stream_check_provider" | "get_usage_summary") {
            "appType"
        } else {
            "app"
        };
        config
            .ensure_command_allowed_with_params(command, &json!({ app_key: "codex" }))
            .unwrap();
    }
}

#[test]
fn slim_rejects_nested_local_tool_app_scoped_params() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();

    for (command, params) in [
        (
            "update_proxy_config_for_app",
            json!({ "config": { "appType": "openclaw" } }),
        ),
        (
            "get_request_logs",
            json!({ "filters": { "appType": "opencode" } }),
        ),
    ] {
        let err = config
            .ensure_command_allowed_with_params(command, &params)
            .unwrap_err();
        assert_eq!(err.code, -32043, "{command}");
        assert_eq!(
            err.data.as_ref().unwrap()["capability"],
            "third-party-local-tools",
            "{command}"
        );
    }

    for (command, params) in [
        (
            "update_proxy_config_for_app",
            json!({ "config": { "appType": "codex" } }),
        ),
        (
            "get_request_logs",
            json!({ "filters": { "appType": "gemini" } }),
        ),
    ] {
        config
            .ensure_command_allowed_with_params(command, &params)
            .unwrap();
    }
}

#[test]
fn slim_rejects_disabled_deeplink_resources_and_local_tool_provider_imports() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();

    for resource in ["prompt", "mcp", "skill"] {
        let err = config
            .ensure_command_allowed_with_params(
                "import_from_deeplink_unified",
                &json!({ "request": { "resource": resource, "app": "claude" } }),
            )
            .unwrap_err();
        assert_eq!(err.code, -32043, "{resource}");
        assert_ne!(err.data.as_ref().unwrap()["capability"], "providers");
    }

    for command in ["merge_deeplink_config", "import_from_deeplink"] {
        let err = config
            .ensure_command_allowed_with_params(
                command,
                &json!({
                    "request": {
                        "resource": "provider",
                        "app": "openclaw"
                    }
                }),
            )
            .unwrap_err();
        assert_eq!(err.code, -32043, "{command}");
        assert_eq!(
            err.data.as_ref().unwrap()["capability"],
            "third-party-local-tools",
            "{command}"
        );
    }

    config
        .ensure_command_allowed_with_params(
            "import_from_deeplink_unified",
            &json!({
                "request": {
                    "resource": "provider",
                    "app": "codex"
                }
            }),
        )
        .unwrap();
}

#[test]
fn disabled_commands_are_rejected_in_slim() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    for command in [
        "get_installed_skills",
        "get_mcp_servers",
        "launch_session_terminal",
        "read_workspace_file",
        "list_daily_memory_files",
        "open_hermes_web_ui",
        "get_openclaw_tools",
        "read_omo_local_file",
        "check_env_conflicts",
        "update_tray_menu",
        "open_external",
        "set_window_theme",
        "save_file_dialog",
        "open_file_dialog",
        "read_live_provider_settings",
        "import_openclaw_providers_from_live",
        "get_openclaw_live_provider_ids",
        "import_hermes_providers_from_live",
        "import_opencode_providers_from_live",
        "get_tool_versions",
        "auth_start_login",
        "auth_list_accounts",
        "copilot_get_token",
        "copilot_get_token_for_account",
        "import_prompt_from_file",
    ] {
        let err = config.ensure_command_allowed(command).unwrap_err();
        assert_eq!(err.code, -32043, "{command}");
    }
}

#[test]
fn usage_and_quota_commands_are_retained_in_slim() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    for command in [
        "queryProviderUsage",
        "testUsageScript",
        "copilot_get_usage",
        "copilot_get_usage_for_account",
        "get_subscription_quota",
        "get_codex_oauth_quota",
        "get_coding_plan_quota",
        "get_balance",
        "get_usage_summary",
        "get_model_pricing",
        "update_model_pricing",
        "delete_model_pricing",
        "get_default_cost_multiplier",
        "set_default_cost_multiplier",
        "get_pricing_model_source",
        "set_pricing_model_source",
    ] {
        config.ensure_command_allowed(command).unwrap();
    }
}

#[test]
fn sync_commands_are_retained_in_slim() {
    let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
    for command in [
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
    ] {
        config.ensure_command_allowed(command).unwrap();
    }
}

#[test]
fn capability_error_has_stable_payload() {
    let err = RpcError::capability_disabled("skills", Some("get_installed_skills"));
    assert_eq!(err.code, -32043);
    assert_eq!(err.message, "capability_disabled");
    assert_eq!(err.data.as_ref().unwrap()["error"], "capability_disabled");
    assert_eq!(err.data.as_ref().unwrap()["capability"], "skills");
    assert_eq!(
        err.data.as_ref().unwrap()["command"],
        "get_installed_skills"
    );
}

#[test]
fn slim_auth_policy_rejects_missing_invalid_and_empty_auth_config() {
    let slim = ProfileConfig::from_env_value(Some("slim")).unwrap();
    for reason in [
        AuthConfigLoadError::MissingConfig,
        AuthConfigLoadError::InvalidJson,
        AuthConfigLoadError::EmptyPasswordHash,
        AuthConfigLoadError::InvalidPasswordHash,
    ] {
        let err = auth_config_for_profile(&slim, Err(reason.clone()), false).unwrap_err();
        assert_eq!(err.reason, reason);
    }
}

#[test]
fn full_profile_preserves_existing_no_auth_default() {
    let full = ProfileConfig::from_env_value(Some("full")).unwrap();
    let auth = auth_config_for_profile(&full, Err(AuthConfigLoadError::MissingConfig), false)
        .expect("full keeps legacy no-auth default");
    assert!(auth.is_none());
}

#[test]
fn full_profile_does_not_disable_auth_for_invalid_existing_config() {
    let full = ProfileConfig::from_env_value(Some("full")).unwrap();
    for reason in [
        AuthConfigLoadError::UnreadableConfig,
        AuthConfigLoadError::InvalidJson,
        AuthConfigLoadError::EmptyPasswordHash,
        AuthConfigLoadError::InvalidPasswordHash,
    ] {
        let err = auth_config_for_profile(&full, Err(reason.clone()), false).unwrap_err();
        assert_eq!(err.reason, reason);
    }
}

#[test]
fn slim_local_no_auth_override_is_explicit() {
    let slim = ProfileConfig::from_env_value(Some("slim")).unwrap();
    let rejected = auth_config_for_profile(&slim, Err(AuthConfigLoadError::MissingConfig), false);
    assert!(rejected.is_err());

    let allowed = auth_config_for_profile(&slim, Err(AuthConfigLoadError::MissingConfig), true)
        .expect("explicit local no-auth override");
    assert!(allowed.is_none());
}

#[test]
fn auth_policy_accepts_valid_config_for_all_profiles() {
    let slim = ProfileConfig::from_env_value(Some("slim")).unwrap();
    let config = AuthConfig {
        password_hash: "$2b$04$MJuc/Azj7j9Js28.20f31uIhhVpf8f1GqCdPbh3D5StxPf8/FxYSi".to_string(),
    };

    let auth = auth_config_for_profile(&slim, Ok(config), false).unwrap();
    assert!(auth.is_some());
}
