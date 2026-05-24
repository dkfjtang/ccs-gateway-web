use std::{collections::HashMap, sync::Arc};

use serde_json::Value;

use crate::{auth::verify_password, events::ServerEvent, rpc::RpcError, ServerState};

macro_rules! rpc_business_methods {
    ($($method:literal),+ $(,)?) => {
        pub const RPC_BUSINESS_METHODS: &[&str] = &[$($method),+];
    };
}

rpc_business_methods!(
    "get_providers",
    "get_current_provider",
    "add_provider",
    "update_provider",
    "delete_provider",
    "switch_provider",
    "import_default_config",
    "update_tray_menu",
    "update_providers_sort_order",
    "queryProviderUsage",
    "testUsageScript",
    "read_live_provider_settings",
    "fetch_models_for_config",
    "import_claude_desktop_providers_from_claude",
    "get_claude_desktop_status",
    "get_claude_desktop_default_routes",
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
    "copilot_get_usage",
    "copilot_get_usage_for_account",
    "get_subscription_quota",
    "get_codex_oauth_quota",
    "get_coding_plan_quota",
    "get_balance",
    "test_api_endpoints",
    "get_custom_endpoints",
    "add_custom_endpoint",
    "remove_custom_endpoint",
    "update_endpoint_last_used",
    "stream_check_provider",
    "stream_check_all_providers",
    "get_stream_check_config",
    "save_stream_check_config",
    "get_usage_summary",
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
    "get_default_cost_multiplier",
    "set_default_cost_multiplier",
    "get_pricing_model_source",
    "set_pricing_model_source",
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
    "restart_app",
    "check_for_updates",
    "is_portable_mode",
    "get_claude_plugin_status",
    "read_claude_plugin_config",
    "get_config_dir",
    "open_config_folder",
    "pick_directory",
    "get_claude_code_config_path",
    "get_app_config_path",
    "open_app_config_folder",
    "get_app_config_dir_override",
    "set_app_config_dir_override",
    "apply_claude_plugin_config",
    "is_claude_plugin_applied",
    "apply_claude_onboarding_skip",
    "clear_claude_onboarding_skip",
    "save_file_dialog",
    "open_file_dialog",
    "open_zip_file_dialog",
    "export_config_to_file",
    "import_config_from_file",
    "sync_current_providers_live",
    "create_db_backup",
    "list_db_backups",
    "restore_db_backup",
    "rename_db_backup",
    "delete_db_backup",
    "open_external",
    "set_auto_launch",
    "get_auto_launch_status",
    "webdav_test_connection",
    "webdav_sync_upload",
    "webdav_sync_download",
    "webdav_sync_save_settings",
    "webdav_sync_fetch_remote_info",
    "get_skills",
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
    "toggle_skill_app",
    "scan_unmanaged_skills",
    "import_skills_from_apps",
    "restore_skill_backup",
    "update_skill",
    "migrate_skill_storage",
    "search_skills_sh",
    "get_skill_repos",
    "add_skill_repo",
    "remove_skill_repo",
    "install_skills_from_zip",
    "get_universal_providers",
    "get_universal_provider",
    "upsert_universal_provider",
    "delete_universal_provider",
    "sync_universal_provider",
    "list_sessions",
    "get_session_messages",
    "launch_session_terminal",
    "delete_session",
    "delete_sessions",
    "extract_common_config_snippet",
    "get_skills_migration_result",
    "get_tool_versions",
    "remove_provider_from_live_config",
    "import_mcp_from_apps",
    "import_openclaw_providers_from_live",
    "get_openclaw_live_provider_ids",
    "get_openclaw_live_provider",
    "import_hermes_providers_from_live",
    "get_hermes_live_provider_ids",
    "get_hermes_model_config",
    "get_hermes_memory",
    "set_hermes_memory",
    "get_hermes_memory_limits",
    "set_hermes_memory_enabled",
    "open_hermes_web_ui",
    "launch_hermes_dashboard",
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
    "get_global_proxy_url",
    "set_global_proxy_url",
    "test_proxy_url",
    "get_upstream_proxy_status",
    "scan_local_proxies",
    "set_window_theme",
    "read_omo_local_file",
    "get_current_omo_provider_id",
    "disable_current_omo",
    "read_omo_slim_local_file",
    "get_current_omo_slim_provider_id",
    "disable_current_omo_slim",
    "import_opencode_providers_from_live",
    "get_opencode_live_provider_ids",
    "open_provider_terminal",
    "read_workspace_file",
    "write_workspace_file",
    "list_daily_memory_files",
    "read_daily_memory_file",
    "write_daily_memory_file",
    "delete_daily_memory_file",
    "search_daily_memory_files",
    "open_workspace_directory",
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
    "get_prompts",
    "upsert_prompt",
    "delete_prompt",
    "enable_prompt",
    "import_prompt_from_file",
    "get_current_prompt_file_content",
    "check_env_conflicts",
    "delete_env_vars",
    "restore_env_backup",
    "get_claude_common_config_snippet",
    "set_claude_common_config_snippet",
    "get_common_config_snippet",
    "set_common_config_snippet",
    "import_from_deeplink",
    "parse_deeplink",
    "merge_deeplink_config",
    "import_from_deeplink_unified",
    "get_init_error",
    "get_migration_result",
);

fn get_str_param<'a>(params: &'a Value, keys: &[&str]) -> Result<&'a str, RpcError> {
    keys.iter()
        .find_map(|key| params.get(*key).and_then(|v| v.as_str()))
        .ok_or_else(|| RpcError::invalid_params(format!("missing '{}' field", keys[0])))
}

fn get_optional_str_param<'a>(
    params: &'a Value,
    keys: &[&str],
) -> Result<Option<&'a str>, RpcError> {
    for key in keys {
        match params.get(*key) {
            Some(value) => {
                return value
                    .as_str()
                    .map(Some)
                    .ok_or_else(|| RpcError::invalid_params(format!("invalid '{}' field", key)));
            }
            None => continue,
        }
    }

    Ok(None)
}

fn get_bool_param(params: &Value, keys: &[&str]) -> Result<bool, RpcError> {
    keys.iter()
        .find_map(|key| params.get(*key).and_then(|v| v.as_bool()))
        .ok_or_else(|| RpcError::invalid_params(format!("missing '{}' field", keys[0])))
}

fn get_optional_i64_param(params: &Value, keys: &[&str]) -> Result<Option<i64>, RpcError> {
    for key in keys {
        match params.get(*key) {
            Some(value) => {
                return value
                    .as_i64()
                    .map(Some)
                    .ok_or_else(|| RpcError::invalid_params(format!("invalid '{}' field", key)));
            }
            None => continue,
        }
    }

    Ok(None)
}

fn get_optional_u32_param(params: &Value, keys: &[&str]) -> Result<Option<u32>, RpcError> {
    for key in keys {
        match params.get(*key) {
            Some(value) => {
                let raw = value
                    .as_u64()
                    .ok_or_else(|| RpcError::invalid_params(format!("invalid '{}' field", key)))?;
                let parsed = u32::try_from(raw)
                    .map_err(|_| RpcError::invalid_params(format!("invalid '{}' field", key)))?;
                return Ok(Some(parsed));
            }
            None => continue,
        }
    }

    Ok(None)
}

/// Dispatch a command to the appropriate handler
pub async fn dispatch_command(
    state: &Arc<ServerState>,
    method: &str,
    params: &Value,
) -> Result<Value, RpcError> {
    let core = &state.core;

    match method {
        "ping" => Ok(serde_json::json!({ "pong": true })),

        // Provider commands
        "get_providers" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let providers =
                cc_switch_core::get_providers(core, app).map_err(RpcError::app_error)?;

            serde_json::to_value(providers).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_current_provider" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id =
                cc_switch_core::get_current_provider(core, app).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(id))
        }

        "add_provider" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_value = params
                .get("provider")
                .ok_or_else(|| RpcError::invalid_params("missing 'provider' field"))?;

            let provider: cc_switch_core::CoreProvider =
                serde_json::from_value(provider_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'provider' value: {e}"))
                })?;

            let ok =
                cc_switch_core::add_provider(core, app, provider).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "update_provider" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_value = params
                .get("provider")
                .ok_or_else(|| RpcError::invalid_params("missing 'provider' field"))?;

            let provider: cc_switch_core::CoreProvider =
                serde_json::from_value(provider_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'provider' value: {e}"))
                })?;

            let ok = cc_switch_core::update_provider(core, app, provider)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "delete_provider" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let ok = cc_switch_core::delete_provider(core, app, id).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "switch_provider" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let ok = cc_switch_core::switch_provider(core, app, id).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "import_default_config" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let ok =
                cc_switch_core::import_default_config(core, app).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        // Web / server 模式下托盘菜单更新为 no-op，只返回 true
        "update_tray_menu" => {
            let ok = cc_switch_core::update_tray_menu(core).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "update_providers_sort_order" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let updates = params
                .get("updates")
                .ok_or_else(|| RpcError::invalid_params("missing 'updates' field"))?;

            let ok = cc_switch_core::update_providers_sort_order(core, app, updates)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "queryProviderUsage" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let usage = cc_switch_core::query_provider_usage(core, app, provider_id)
                .await
                .map_err(RpcError::app_error)?;

            Ok(usage)
        }

        "testUsageScript" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let script_code = params
                .get("scriptCode")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'scriptCode' field"))?;

            let timeout = params.get("timeout").and_then(|v| v.as_u64());
            let api_key = params.get("apiKey").and_then(|v| v.as_str());
            let base_url = params.get("baseUrl").and_then(|v| v.as_str());
            let access_token = params.get("accessToken").and_then(|v| v.as_str());
            let user_id = params.get("userId").and_then(|v| v.as_str());
            let template_type = params.get("templateType").and_then(|v| v.as_str());

            let result = cc_switch_core::test_usage_script(
                core,
                app,
                provider_id,
                script_code,
                timeout,
                api_key,
                base_url,
                access_token,
                user_id,
                template_type,
            )
            .await
            .map_err(RpcError::app_error)?;

            Ok(result)
        }

        "read_live_provider_settings" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let settings =
                cc_switch_core::read_live_provider_settings(app).map_err(RpcError::app_error)?;

            Ok(settings)
        }

        "fetch_models_for_config" => {
            let base_url = get_str_param(params, &["baseUrl", "base_url"])?;
            let api_key = get_str_param(params, &["apiKey", "api_key"])?;
            let is_full_url = params
                .get("isFullUrl")
                .or_else(|| params.get("is_full_url"))
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let models_url = params
                .get("modelsUrl")
                .or_else(|| params.get("models_url"))
                .and_then(|v| v.as_str());

            let models =
                cc_switch_core::fetch_models_for_config(base_url, api_key, is_full_url, models_url)
                    .await
                    .map_err(RpcError::app_error)?;

            serde_json::to_value(models).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "import_claude_desktop_providers_from_claude" => {
            let count = cc_switch_core::import_claude_desktop_providers_from_claude(core)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(count))
        }

        "get_claude_desktop_status" => {
            let status = cc_switch_core::get_claude_desktop_status(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_claude_desktop_default_routes" => {
            let routes = cc_switch_core::get_claude_desktop_default_routes();
            serde_json::to_value(routes).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "auth_start_login" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let github_domain = params
                .get("githubDomain")
                .or_else(|| params.get("github_domain"))
                .and_then(|v| v.as_str());
            let response = cc_switch_core::auth_start_login(core, auth_provider, github_domain)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(response).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "auth_poll_for_account" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let device_code = get_str_param(params, &["deviceCode", "device_code"])?;
            let github_domain = params
                .get("githubDomain")
                .or_else(|| params.get("github_domain"))
                .and_then(|v| v.as_str());
            let account = cc_switch_core::auth_poll_for_account(
                core,
                auth_provider,
                device_code,
                github_domain,
            )
            .await
            .map_err(RpcError::app_error)?;
            serde_json::to_value(account).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "auth_list_accounts" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let accounts = cc_switch_core::auth_list_accounts(core, auth_provider)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(accounts).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "auth_get_status" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let status = cc_switch_core::auth_get_status(core, auth_provider)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "auth_remove_account" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            cc_switch_core::auth_remove_account(core, auth_provider, account_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "auth_set_default_account" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            cc_switch_core::auth_set_default_account(core, auth_provider, account_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "auth_logout" => {
            let auth_provider = get_str_param(params, &["authProvider", "auth_provider"])?;
            cc_switch_core::auth_logout(core, auth_provider)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "copilot_start_device_flow" => {
            let github_domain = params
                .get("githubDomain")
                .or_else(|| params.get("github_domain"))
                .and_then(|v| v.as_str());
            let response = cc_switch_core::copilot_start_device_flow(core, github_domain)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(response).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_poll_for_auth" => {
            let device_code = get_str_param(params, &["deviceCode", "device_code"])?;
            let github_domain = params
                .get("githubDomain")
                .or_else(|| params.get("github_domain"))
                .and_then(|v| v.as_str());
            let ok = cc_switch_core::copilot_poll_for_auth(core, device_code, github_domain)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "copilot_poll_for_account" => {
            let device_code = get_str_param(params, &["deviceCode", "device_code"])?;
            let github_domain = params
                .get("githubDomain")
                .or_else(|| params.get("github_domain"))
                .and_then(|v| v.as_str());
            let account =
                cc_switch_core::copilot_poll_for_account(core, device_code, github_domain)
                    .await
                    .map_err(RpcError::app_error)?;
            serde_json::to_value(account).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_list_accounts" => {
            let accounts = cc_switch_core::copilot_list_accounts(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(accounts).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_remove_account" => {
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            cc_switch_core::copilot_remove_account(core, account_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "copilot_set_default_account" => {
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            cc_switch_core::copilot_set_default_account(core, account_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "copilot_get_auth_status" => {
            let status = cc_switch_core::copilot_get_auth_status(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_logout" => {
            cc_switch_core::copilot_logout(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "copilot_is_authenticated" => {
            let ok = cc_switch_core::copilot_is_authenticated(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "copilot_get_token" => {
            let token = cc_switch_core::copilot_get_token(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(token))
        }

        "copilot_get_token_for_account" => {
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            let token = cc_switch_core::copilot_get_token_for_account(core, account_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(token))
        }

        "copilot_get_models" => {
            let models = cc_switch_core::copilot_get_models(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(models).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_get_models_for_account" => {
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            let models = cc_switch_core::copilot_get_models_for_account(core, account_id)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(models).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_get_usage" => {
            let usage = cc_switch_core::copilot_get_usage(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(usage).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "copilot_get_usage_for_account" => {
            let account_id = get_str_param(params, &["accountId", "account_id"])?;
            let usage = cc_switch_core::copilot_get_usage_for_account(core, account_id)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(usage).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_subscription_quota" => {
            let tool = get_str_param(params, &["tool"])?;
            let quota = cc_switch_core::get_subscription_quota(tool)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(quota).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_codex_oauth_quota" => {
            let account_id = params
                .get("accountId")
                .or_else(|| params.get("account_id"))
                .and_then(|v| v.as_str());
            let quota = cc_switch_core::get_codex_oauth_quota(account_id)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(quota).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_coding_plan_quota" => {
            let base_url = get_str_param(params, &["baseUrl", "base_url"])?;
            let api_key = get_str_param(params, &["apiKey", "api_key"])?;
            let quota = cc_switch_core::get_coding_plan_quota(base_url, api_key)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(quota).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_balance" => {
            let base_url = get_str_param(params, &["baseUrl", "base_url"])?;
            let api_key = get_str_param(params, &["apiKey", "api_key"])?;
            let result = cc_switch_core::get_balance(base_url, api_key)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "test_api_endpoints" => {
            let urls_value = params
                .get("urls")
                .ok_or_else(|| RpcError::invalid_params("missing 'urls' field"))?;

            let urls: Vec<String> = serde_json::from_value(urls_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'urls' value: {e}")))?;

            let timeout_secs = params.get("timeoutSecs").and_then(|v| v.as_u64());

            let result = cc_switch_core::test_api_endpoints(urls, timeout_secs)
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_custom_endpoints" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let endpoints = cc_switch_core::get_custom_endpoints(core, app, provider_id)
                .map_err(RpcError::app_error)?;

            Ok(endpoints)
        }

        "add_custom_endpoint" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let url = params
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'url' field"))?;

            cc_switch_core::add_custom_endpoint(core, app, provider_id, url.to_string())
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "remove_custom_endpoint" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let url = params
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'url' field"))?;

            cc_switch_core::remove_custom_endpoint(core, app, provider_id, url.to_string())
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "update_endpoint_last_used" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let provider_id = params
                .get("providerId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'providerId' field"))?;

            let url = params
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'url' field"))?;

            cc_switch_core::update_endpoint_last_used(core, app, provider_id, url.to_string())
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "stream_check_provider" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;

            let result = cc_switch_core::stream_check_provider(core, app_type, provider_id)
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "stream_check_all_providers" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let proxy_targets_only = params
                .get("proxyTargetsOnly")
                .or_else(|| params.get("proxy_targets_only"))
                .and_then(|v| v.as_bool())
                .unwrap_or(false);

            let result =
                cc_switch_core::stream_check_all_providers(core, app_type, proxy_targets_only)
                    .await
                    .map_err(RpcError::app_error)?;

            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_stream_check_config" => {
            let config =
                cc_switch_core::get_stream_check_config(core).map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "save_stream_check_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;

            let config: cc_switch_core::StreamCheckConfig =
                serde_json::from_value(config_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'config' value: {e}"))
                })?;

            cc_switch_core::save_stream_check_config(core, config).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_usage_summary" => {
            let start_date = get_optional_i64_param(params, &["startDate", "start_date"])?;
            let end_date = get_optional_i64_param(params, &["endDate", "end_date"])?;
            let app_type = get_optional_str_param(params, &["appType", "app_type"])?;

            let summary = cc_switch_core::get_usage_summary(core, start_date, end_date, app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(summary).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_usage_trends" => {
            let start_date = get_optional_i64_param(params, &["startDate", "start_date"])?;
            let end_date = get_optional_i64_param(params, &["endDate", "end_date"])?;
            let app_type = get_optional_str_param(params, &["appType", "app_type"])?;

            let trends = cc_switch_core::get_usage_trends(core, start_date, end_date, app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(trends).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_provider_stats" => {
            let start_date = get_optional_i64_param(params, &["startDate", "start_date"])?;
            let end_date = get_optional_i64_param(params, &["endDate", "end_date"])?;
            let app_type = get_optional_str_param(params, &["appType", "app_type"])?;

            let stats = cc_switch_core::get_provider_stats(core, start_date, end_date, app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(stats).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_model_stats" => {
            let start_date = get_optional_i64_param(params, &["startDate", "start_date"])?;
            let end_date = get_optional_i64_param(params, &["endDate", "end_date"])?;
            let app_type = get_optional_str_param(params, &["appType", "app_type"])?;

            let stats = cc_switch_core::get_model_stats(core, start_date, end_date, app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(stats).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_request_logs" => {
            let filters_value = params
                .get("filters")
                .ok_or_else(|| RpcError::invalid_params("missing 'filters' field"))?;
            let filters: cc_switch_core::LogFilters = serde_json::from_value(filters_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'filters' value: {e}")))?;
            let page = get_optional_u32_param(params, &["page"])?.unwrap_or(0);
            let page_size =
                get_optional_u32_param(params, &["pageSize", "page_size"])?.unwrap_or(20);

            let logs = cc_switch_core::get_request_logs(core, filters, page, page_size)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(logs).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_request_detail" => {
            let request_id = get_str_param(params, &["requestId", "request_id"])?;

            let detail = cc_switch_core::get_request_detail(core, request_id)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(detail).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "sync_session_usage" => {
            let result = cc_switch_core::sync_session_usage(core).map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_usage_data_sources" => {
            let result =
                cc_switch_core::get_usage_data_sources(core).map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_model_pricing" => {
            let pricing = cc_switch_core::get_model_pricing(core).map_err(RpcError::app_error)?;

            serde_json::to_value(pricing).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "update_model_pricing" => {
            let model_id = get_str_param(params, &["modelId", "model_id"])?;
            let display_name = get_str_param(params, &["displayName", "display_name"])?;
            let input_cost = get_str_param(params, &["inputCost", "input_cost"])?;
            let output_cost = get_str_param(params, &["outputCost", "output_cost"])?;
            let cache_read_cost = get_str_param(params, &["cacheReadCost", "cache_read_cost"])?;
            let cache_creation_cost =
                get_str_param(params, &["cacheCreationCost", "cache_creation_cost"])?;

            cc_switch_core::update_model_pricing(
                core,
                model_id.to_string(),
                display_name.to_string(),
                input_cost.to_string(),
                output_cost.to_string(),
                cache_read_cost.to_string(),
                cache_creation_cost.to_string(),
            )
            .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "delete_model_pricing" => {
            let model_id = get_str_param(params, &["modelId", "model_id"])?;

            cc_switch_core::delete_model_pricing(core, model_id.to_string())
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "check_provider_limits" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let status = cc_switch_core::check_provider_limits(core, provider_id, app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        // Proxy commands
        "start_proxy_server" => {
            let info = core
                .app_state()
                .proxy_service
                .start()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(info).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "stop_proxy_server" => {
            let takeover = core
                .app_state()
                .proxy_service
                .get_takeover_status()
                .await
                .map_err(RpcError::app_error)?;
            if takeover.claude
                || takeover.codex
                || takeover.gemini
                || takeover.opencode
                || takeover.openclaw
            {
                return Err(RpcError::app_error(
                    "仍有应用处于代理接管状态，请先在设置中关闭对应应用接管后再停止本地路由。"
                        .to_string(),
                ));
            }

            core.app_state()
                .proxy_service
                .stop()
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "stop_proxy_with_restore" => {
            core.app_state()
                .proxy_service
                .stop_with_restore()
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_proxy_takeover_status" => {
            let status = core
                .app_state()
                .proxy_service
                .get_takeover_status()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "set_proxy_takeover_for_app" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let enabled = get_bool_param(params, &["enabled"])?;

            core.app_state()
                .proxy_service
                .set_takeover_for_app(app_type, enabled)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_proxy_status" => {
            let status = core
                .app_state()
                .proxy_service
                .get_status()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_proxy_config" => {
            let config = core
                .app_state()
                .proxy_service
                .get_config()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "update_proxy_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;

            let config = serde_json::from_value(config_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'config' value: {e}")))?;

            core.app_state()
                .proxy_service
                .update_config(&config)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_global_proxy_config" => {
            let config = core
                .app_state()
                .db
                .get_global_proxy_config()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "update_global_proxy_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;

            let config = serde_json::from_value(config_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'config' value: {e}")))?;

            core.app_state()
                .db
                .update_global_proxy_config(config)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_proxy_config_for_app" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let config = core
                .app_state()
                .db
                .get_proxy_config_for_app(app_type)
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "update_proxy_config_for_app" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;

            let config = serde_json::from_value(config_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'config' value: {e}")))?;

            core.app_state()
                .db
                .update_proxy_config_for_app(config)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "is_proxy_running" => Ok(serde_json::json!(
            core.app_state().proxy_service.is_running().await
        )),

        "is_live_takeover_active" => {
            let active = core
                .app_state()
                .proxy_service
                .is_takeover_active()
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(active))
        }

        "switch_proxy_provider" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;

            core.app_state()
                .proxy_service
                .switch_proxy_target(app_type, provider_id)
                .await
                .map_err(RpcError::app_error)?;

            let _ = state.event_bus.send(ServerEvent {
                name: "provider-switched".to_string(),
                payload: serde_json::json!({
                    "appType": app_type,
                    "providerId": provider_id,
                    "source": "webProxySwitch"
                }),
            });

            Ok(Value::Null)
        }

        "get_provider_health" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let health = core
                .app_state()
                .db
                .get_provider_health(provider_id, app_type)
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(health).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "reset_circuit_breaker" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            core.app_state()
                .db
                .update_provider_health(provider_id, app_type, true, None)
                .await
                .map_err(RpcError::app_error)?;

            core.app_state()
                .proxy_service
                .reset_provider_circuit_breaker(provider_id, app_type)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_circuit_breaker_config" => {
            let config = core
                .app_state()
                .db
                .get_circuit_breaker_config()
                .await
                .map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "update_circuit_breaker_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;

            let config = serde_json::from_value(config_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'config' value: {e}")))?;

            core.app_state()
                .db
                .update_circuit_breaker_config(&config)
                .await
                .map_err(RpcError::app_error)?;

            core.app_state()
                .proxy_service
                .update_circuit_breaker_configs(config)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_circuit_breaker_stats" => Ok(Value::Null),

        "get_failover_queue" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let queue = core
                .app_state()
                .db
                .get_failover_queue(app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(queue).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_available_providers_for_failover" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let providers = core
                .app_state()
                .db
                .get_available_providers_for_failover(app_type)
                .map_err(RpcError::app_error)?;

            serde_json::to_value(providers).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "add_to_failover_queue" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;

            core.app_state()
                .db
                .add_to_failover_queue(app_type, provider_id)
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "remove_from_failover_queue" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;

            core.app_state()
                .db
                .remove_from_failover_queue(app_type, provider_id)
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_auto_failover_enabled" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let enabled = core
                .app_state()
                .db
                .get_proxy_config_for_app(app_type)
                .await
                .map(|config| config.auto_failover_enabled)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(enabled))
        }

        "set_auto_failover_enabled" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let enabled = get_bool_param(params, &["enabled"])?;

            let p1_provider_id = if enabled {
                let mut queue = core
                    .app_state()
                    .db
                    .get_failover_queue(app_type)
                    .map_err(RpcError::app_error)?;

                if queue.is_empty() {
                    let current_id = core
                        .app_state()
                        .db
                        .get_current_provider(app_type)
                        .map_err(RpcError::app_error)?
                        .ok_or_else(|| {
                            RpcError::app_error(
                                "故障转移队列为空，且未设置当前供应商，无法开启故障转移",
                            )
                        })?;

                    core.app_state()
                        .db
                        .add_to_failover_queue(app_type, &current_id)
                        .map_err(RpcError::app_error)?;

                    queue = core
                        .app_state()
                        .db
                        .get_failover_queue(app_type)
                        .map_err(RpcError::app_error)?;
                }

                Some(
                    queue
                        .first()
                        .map(|item| item.provider_id.clone())
                        .ok_or_else(|| RpcError::app_error("故障转移队列为空，无法开启故障转移"))?,
                )
            } else {
                None
            };

            let mut config = core
                .app_state()
                .db
                .get_proxy_config_for_app(app_type)
                .await
                .map_err(RpcError::app_error)?;
            config.auto_failover_enabled = enabled;

            core.app_state()
                .db
                .update_proxy_config_for_app(config)
                .await
                .map_err(RpcError::app_error)?;

            if let Some(provider_id) = p1_provider_id {
                core.app_state()
                    .proxy_service
                    .switch_proxy_target(app_type, &provider_id)
                    .await
                    .map_err(RpcError::app_error)?;

                let _ = state.event_bus.send(ServerEvent {
                    name: "provider-switched".to_string(),
                    payload: serde_json::json!({
                        "appType": app_type,
                        "providerId": provider_id,
                        "source": "failoverEnabled"
                    }),
                });
            }

            Ok(Value::Null)
        }

        "get_default_cost_multiplier" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let value = core
                .app_state()
                .db
                .get_default_cost_multiplier(app_type)
                .await
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(value))
        }

        "set_default_cost_multiplier" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let value = get_str_param(params, &["value"])?;

            core.app_state()
                .db
                .set_default_cost_multiplier(app_type, value)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_pricing_model_source" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;

            let value = core
                .app_state()
                .db
                .get_pricing_model_source(app_type)
                .await
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(value))
        }

        "set_pricing_model_source" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let value = get_str_param(params, &["value"])?;

            core.app_state()
                .db
                .set_pricing_model_source(app_type, value)
                .await
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        // Settings commands
        "get_settings" => {
            let settings = cc_switch_core::get_settings();
            serde_json::to_value(settings).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "save_settings" => {
            let settings_value = params
                .get("settings")
                .ok_or_else(|| RpcError::invalid_params("missing 'settings' field"))?;

            let settings: cc_switch_core::CoreAppSettings =
                serde_json::from_value(settings_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'settings' value: {e}"))
                })?;

            let ok = cc_switch_core::save_settings(settings).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_rectifier_config" => {
            let config = cc_switch_core::get_rectifier_config(core).map_err(RpcError::app_error)?;
            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "set_rectifier_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;
            let config: cc_switch_core::RectifierConfig =
                serde_json::from_value(config_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'config' value: {e}"))
                })?;
            let ok =
                cc_switch_core::set_rectifier_config(core, config).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_optimizer_config" => {
            let config = cc_switch_core::get_optimizer_config(core).map_err(RpcError::app_error)?;
            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "set_optimizer_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;
            let config: cc_switch_core::OptimizerConfig =
                serde_json::from_value(config_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'config' value: {e}"))
                })?;
            let ok =
                cc_switch_core::set_optimizer_config(core, config).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_log_config" => {
            let config = cc_switch_core::get_log_config(core).map_err(RpcError::app_error)?;
            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "set_log_config" => {
            let config_value = params
                .get("config")
                .ok_or_else(|| RpcError::invalid_params("missing 'config' field"))?;
            let config: cc_switch_core::LogConfig = serde_json::from_value(config_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'config' value: {e}")))?;
            let ok = cc_switch_core::set_log_config(core, config).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_claude_config_status" => {
            let status = cc_switch_core::get_claude_config_status();
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_config_status" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");
            let status = cc_switch_core::get_config_status(app).map_err(RpcError::app_error)?;
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "restart_app" => {
            // Stub for web server - not applicable
            let ok = cc_switch_core::restart_app().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "check_for_updates" => {
            // Returns the update URL for client to handle
            let url = cc_switch_core::check_for_updates().map_err(RpcError::app_error)?;
            Ok(serde_json::json!({ "url": url }))
        }

        "is_portable_mode" => {
            let is_portable = cc_switch_core::is_portable_mode().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(is_portable))
        }

        "get_config_dir" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");
            let dir = cc_switch_core::get_config_dir(app).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(dir))
        }

        "open_config_folder" => {
            // Stub for web server - returns path for client to handle
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");
            let path = cc_switch_core::open_config_folder(app).map_err(RpcError::app_error)?;
            Ok(serde_json::json!({ "path": path }))
        }

        "pick_directory" => {
            // Stub for web server - not applicable
            let result = cc_switch_core::pick_directory().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "get_claude_code_config_path" => {
            let path = cc_switch_core::get_claude_code_config_path();
            Ok(serde_json::json!(path))
        }

        "get_app_config_path" => {
            let path = cc_switch_core::get_app_config_path();
            Ok(serde_json::json!(path))
        }

        "open_app_config_folder" => {
            // Stub for web server - returns path for client to handle
            let path = cc_switch_core::open_app_config_folder().map_err(RpcError::app_error)?;
            Ok(serde_json::json!({ "path": path }))
        }

        "get_app_config_dir_override" => {
            let override_path = cc_switch_core::get_app_config_dir_override();
            Ok(serde_json::json!(override_path))
        }

        "set_app_config_dir_override" => {
            let path = params.get("path").and_then(|v| v.as_str());
            let ok =
                cc_switch_core::set_app_config_dir_override(path).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "apply_claude_plugin_config" => {
            let official = params
                .get("official")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let ok = cc_switch_core::apply_claude_plugin_config(official)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_claude_plugin_status" => {
            let status = cc_switch_core::get_claude_plugin_status()
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "read_claude_plugin_config" => {
            let content = cc_switch_core::read_claude_plugin_config()
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(content))
        }

        "is_claude_plugin_applied" => {
            let applied = cc_switch_core::is_claude_plugin_applied()
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(applied))
        }

        "apply_claude_onboarding_skip" => {
            let ok = cc_switch_core::apply_claude_onboarding_skip()
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "clear_claude_onboarding_skip" => {
            let ok = cc_switch_core::clear_claude_onboarding_skip()
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "save_file_dialog" => {
            // Stub for web server - not applicable
            let result = cc_switch_core::save_file_dialog().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "open_file_dialog" => {
            // Stub for web server - not applicable
            let result = cc_switch_core::open_file_dialog().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "open_zip_file_dialog" => {
            let result = cc_switch_core::open_zip_file_dialog().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "export_config_to_file" => {
            let file_path = params
                .get("filePath")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'filePath' field"))?;

            let result = cc_switch_core::export_config_to_file(core, file_path)
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "import_config_from_file" => {
            let file_path = params
                .get("filePath")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'filePath' field"))?;

            let result = cc_switch_core::import_config_from_file(core, file_path)
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "sync_current_providers_live" => {
            let result =
                cc_switch_core::sync_current_providers_live(core).map_err(RpcError::app_error)?;
            Ok(result)
        }

        "create_db_backup" => {
            let backup = cc_switch_core::create_db_backup(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(backup))
        }

        "list_db_backups" => {
            let backups = cc_switch_core::list_db_backups().map_err(RpcError::app_error)?;
            serde_json::to_value(backups).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "restore_db_backup" => {
            let filename = get_str_param(params, &["filename"])?;
            let result =
                cc_switch_core::restore_db_backup(core, filename).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "rename_db_backup" => {
            let old_filename = get_str_param(params, &["oldFilename", "old_filename"])?;
            let new_name = get_str_param(params, &["newName", "new_name"])?;
            let result = cc_switch_core::rename_db_backup(old_filename, new_name)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(result))
        }

        "delete_db_backup" => {
            let filename = get_str_param(params, &["filename"])?;
            cc_switch_core::delete_db_backup(filename).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "open_external" => {
            // Stub for web server - returns URL for client to handle
            let url = params
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'url' field"))?;

            let resolved_url = cc_switch_core::open_external(url).map_err(RpcError::app_error)?;
            Ok(serde_json::json!({ "url": resolved_url }))
        }

        "set_auto_launch" => {
            // Stub for web server - not applicable
            let enabled = params
                .get("enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let ok = cc_switch_core::set_auto_launch(enabled).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_auto_launch_status" => {
            // Stub for web server - returns false
            let status = cc_switch_core::get_auto_launch_status().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(status))
        }

        "webdav_test_connection" => {
            let settings_value = params
                .get("settings")
                .ok_or_else(|| RpcError::invalid_params("missing 'settings' field"))?;
            let settings: cc_switch_core::WebDavSyncSettings =
                serde_json::from_value(settings_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'settings' value: {e}"))
                })?;
            let preserve_empty_password = params
                .get("preserveEmptyPassword")
                .and_then(|v| v.as_bool())
                .or_else(|| {
                    params
                        .get("preserve_empty_password")
                        .and_then(|v| v.as_bool())
                });
            let result = cc_switch_core::webdav_test_connection(settings, preserve_empty_password)
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "webdav_sync_upload" => {
            let result = cc_switch_core::webdav_sync_upload(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "webdav_sync_download" => {
            let result = cc_switch_core::webdav_sync_download(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "webdav_sync_save_settings" => {
            let settings_value = params
                .get("settings")
                .ok_or_else(|| RpcError::invalid_params("missing 'settings' field"))?;
            let settings: cc_switch_core::WebDavSyncSettings =
                serde_json::from_value(settings_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'settings' value: {e}"))
                })?;
            let password_touched = params
                .get("passwordTouched")
                .and_then(|v| v.as_bool())
                .or_else(|| params.get("password_touched").and_then(|v| v.as_bool()));
            let result = cc_switch_core::webdav_sync_save_settings(settings, password_touched)
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "webdav_sync_fetch_remote_info" => {
            let result = cc_switch_core::webdav_sync_fetch_remote_info()
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_installed_skills" => {
            let skills = cc_switch_core::get_installed_skills(core).map_err(RpcError::app_error)?;
            Ok(skills)
        }

        "get_skill_backups" => {
            let backups = cc_switch_core::get_skill_backups().map_err(RpcError::app_error)?;
            serde_json::to_value(backups).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "delete_skill_backup" => {
            let backup_id = get_str_param(params, &["backupId", "backup_id"])?;
            let ok = cc_switch_core::delete_skill_backup(backup_id).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "discover_available_skills" => {
            let skills = cc_switch_core::discover_available_skills(core)
                .await
                .map_err(RpcError::app_error)?;
            Ok(skills)
        }

        "check_skill_updates" => {
            let updates = cc_switch_core::check_skill_updates(core)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(updates).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_skills_for_app" => {
            let app = get_str_param(params, &["app"])?;
            let skills = cc_switch_core::get_skills_for_app(core, app)
                .await
                .map_err(RpcError::app_error)?;
            Ok(skills)
        }

        "install_skill" => {
            let directory = get_str_param(params, &["directory"])?;
            let ok = cc_switch_core::install_skill(core, directory)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "install_skill_for_app" => {
            let app = get_str_param(params, &["app"])?;
            let directory = get_str_param(params, &["directory"])?;
            let ok = cc_switch_core::install_skill_for_app(core, app, directory)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "uninstall_skill" => {
            let directory = get_str_param(params, &["directory"])?;
            let ok =
                cc_switch_core::uninstall_skill(core, directory).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "uninstall_skill_for_app" => {
            let app = get_str_param(params, &["app"])?;
            let directory = get_str_param(params, &["directory"])?;
            let ok = cc_switch_core::uninstall_skill_for_app(core, app, directory)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "install_skill_unified" => {
            let skill_value = params
                .get("skill")
                .ok_or_else(|| RpcError::invalid_params("missing 'skill' field"))?;
            let skill: cc_switch_core::DiscoverableSkill =
                serde_json::from_value(skill_value.clone())
                    .map_err(|e| RpcError::invalid_params(format!("invalid 'skill' value: {e}")))?;
            let current_app = get_str_param(params, &["current_app", "currentApp"])?;
            let installed = cc_switch_core::install_skill_unified(core, skill, current_app)
                .await
                .map_err(RpcError::app_error)?;
            Ok(installed)
        }

        "uninstall_skill_unified" => {
            let id = get_str_param(params, &["id"])?;
            let ok =
                cc_switch_core::uninstall_skill_unified(core, id).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "restore_skill_backup" => {
            let backup_id = get_str_param(params, &["backupId", "backup_id"])?;
            let current_app = get_str_param(params, &["currentApp", "current_app"])?;
            let installed = cc_switch_core::restore_skill_backup(core, backup_id, current_app)
                .map_err(RpcError::app_error)?;
            Ok(installed)
        }

        "toggle_skill_app" => {
            let id = get_str_param(params, &["id"])?;
            let app = get_str_param(params, &["app"])?;
            let enabled = get_bool_param(params, &["enabled"])?;
            let ok = cc_switch_core::toggle_skill_app(core, id, app, enabled)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "scan_unmanaged_skills" => {
            let skills =
                cc_switch_core::scan_unmanaged_skills(core).map_err(RpcError::app_error)?;
            Ok(skills)
        }

        "import_skills_from_apps" => {
            let imports = if let Some(imports_value) = params.get("imports").cloned() {
                serde_json::from_value(imports_value).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'imports' value: {e}"))
                })?
            } else {
                let directories_value = params.get("directories").cloned().ok_or_else(|| {
                    RpcError::invalid_params("missing 'imports' or legacy 'directories' field")
                })?;
                let directories: Vec<String> =
                    serde_json::from_value(directories_value).map_err(|e| {
                        RpcError::invalid_params(format!("invalid 'directories' value: {e}"))
                    })?;
                directories
                    .into_iter()
                    .map(|directory| cc_switch_core::ImportSkillSelection {
                        directory,
                        apps: Default::default(),
                    })
                    .collect()
            };
            let installed = cc_switch_core::import_skills_from_apps(core, imports)
                .map_err(RpcError::app_error)?;
            Ok(installed)
        }

        "update_skill" => {
            let id = get_str_param(params, &["id"])?;
            let updated = cc_switch_core::update_skill(core, id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(updated)
        }

        "migrate_skill_storage" => {
            let target_value = params
                .get("target")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'target' field"))?;
            let target: cc_switch_core::SkillStorageLocation = serde_json::from_value(target_value)
                .map_err(|e| RpcError::invalid_params(format!("invalid 'target' value: {e}")))?;
            let result = cc_switch_core::migrate_skill_storage(core, target)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "search_skills_sh" => {
            let query = get_str_param(params, &["query"])?;
            let limit = params
                .get("limit")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| RpcError::invalid_params("missing 'limit' field"))
                .and_then(|v| {
                    usize::try_from(v)
                        .map_err(|_| RpcError::invalid_params("invalid 'limit' field"))
                })?;
            let offset = params
                .get("offset")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| RpcError::invalid_params("missing 'offset' field"))
                .and_then(|v| {
                    usize::try_from(v)
                        .map_err(|_| RpcError::invalid_params("invalid 'offset' field"))
                })?;
            let result = cc_switch_core::search_skills_sh(query, limit, offset)
                .await
                .map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_skill_repos" => {
            let repos = cc_switch_core::get_skill_repos(core).map_err(RpcError::app_error)?;
            serde_json::to_value(repos).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "add_skill_repo" => {
            let repo_value = params
                .get("repo")
                .ok_or_else(|| RpcError::invalid_params("missing 'repo' field"))?;
            let repo: cc_switch_core::SkillRepo = serde_json::from_value(repo_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'repo' value: {e}")))?;
            let ok = cc_switch_core::add_skill_repo(core, repo).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "remove_skill_repo" => {
            let owner = get_str_param(params, &["owner"])?;
            let name = get_str_param(params, &["name"])?;
            let ok = cc_switch_core::remove_skill_repo(core, owner, name)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "install_skills_from_zip" => {
            let file_path = get_str_param(params, &["filePath", "file_path"])?;
            let current_app = get_str_param(params, &["current_app", "currentApp"])?;
            let installed = cc_switch_core::install_skills_from_zip(core, file_path, current_app)
                .map_err(RpcError::app_error)?;
            Ok(installed)
        }

        "list_sessions" => {
            let sessions = cc_switch_core::list_sessions()
                .await
                .map_err(RpcError::app_error)?;
            Ok(sessions)
        }

        "get_session_messages" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let source_path = get_str_param(params, &["sourcePath", "source_path"])?;
            let messages = cc_switch_core::get_session_messages(provider_id, source_path)
                .await
                .map_err(RpcError::app_error)?;
            Ok(messages)
        }

        "launch_session_terminal" => {
            let command = get_str_param(params, &["command"])?;
            let cwd = params
                .get("cwd")
                .and_then(|value| value.as_str())
                .map(str::to_string);
            let custom_config = params
                .get("customConfig")
                .and_then(|value| value.as_str())
                .map(str::to_string)
                .or_else(|| {
                    params
                        .get("custom_config")
                        .and_then(|value| value.as_str())
                        .map(str::to_string)
                });
            let ok = cc_switch_core::launch_session_terminal(command, cwd, custom_config)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "delete_session" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let session_id = get_str_param(params, &["sessionId", "session_id"])?;
            let source_path = get_str_param(params, &["sourcePath", "source_path"])?;
            let ok = cc_switch_core::delete_session(provider_id, session_id, source_path)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "delete_sessions" => {
            let items_value = params
                .get("items")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'items' field"))?;
            let items: Vec<cc_switch_core::DeleteSessionRequest> =
                serde_json::from_value(items_value)
                    .map_err(|e| RpcError::invalid_params(format!("invalid 'items' value: {e}")))?;
            let result = cc_switch_core::delete_sessions(items).map_err(RpcError::app_error)?;
            serde_json::to_value(result).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "extract_common_config_snippet" => {
            let app_type = get_str_param(params, &["appType", "app_type"])?;
            let settings_config = params
                .get("settingsConfig")
                .and_then(|value| value.as_str())
                .or_else(|| {
                    params
                        .get("settings_config")
                        .and_then(|value| value.as_str())
                });
            let snippet =
                cc_switch_core::extract_common_config_snippet(core, app_type, settings_config)
                    .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(snippet))
        }

        "get_skills_migration_result" => {
            let result = cc_switch_core::get_skills_migration_result()
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_tool_versions" => {
            let tools = params
                .get("tools")
                .cloned()
                .map(serde_json::from_value)
                .transpose()
                .map_err(|e| RpcError::invalid_params(format!("invalid 'tools' value: {e}")))?;
            let wsl_shell_by_tool = params
                .get("wslShellByTool")
                .or_else(|| params.get("wsl_shell_by_tool"))
                .cloned()
                .map(
                    serde_json::from_value::<
                        HashMap<String, cc_switch_core::WslShellPreferenceInput>,
                    >,
                )
                .transpose()
                .map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'wslShellByTool' value: {e}"))
                })?;
            let result = cc_switch_core::get_tool_versions(tools, wsl_shell_by_tool)
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "remove_provider_from_live_config" => {
            let app = get_str_param(params, &["app"])?;
            let id = get_str_param(params, &["id"])?;
            let ok = cc_switch_core::remove_provider_from_live_config(core, app, id)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "import_mcp_from_apps" => {
            let count = cc_switch_core::import_mcp_from_apps(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(count))
        }

        "import_openclaw_providers_from_live" => {
            let count = cc_switch_core::import_openclaw_providers_from_live(core)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(count))
        }

        "get_openclaw_live_provider_ids" => {
            let ids =
                cc_switch_core::get_openclaw_live_provider_ids().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ids))
        }

        "get_openclaw_live_provider" => {
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let provider = cc_switch_core::get_openclaw_live_provider(provider_id)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(provider))
        }

        "import_hermes_providers_from_live" => {
            let count = cc_switch_core::import_hermes_providers_from_live(core)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(count))
        }

        "get_hermes_live_provider_ids" => {
            let ids =
                cc_switch_core::get_hermes_live_provider_ids().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ids))
        }

        "get_hermes_model_config" => {
            let config = cc_switch_core::get_hermes_model_config().map_err(RpcError::app_error)?;
            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_hermes_memory" => {
            let kind_value = params
                .get("kind")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'kind' field"))?;
            let kind: cc_switch_core::MemoryKind = serde_json::from_value(kind_value)
                .map_err(|e| RpcError::invalid_params(format!("invalid 'kind' value: {e}")))?;
            let content = cc_switch_core::get_hermes_memory(kind).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(content))
        }

        "set_hermes_memory" => {
            let kind_value = params
                .get("kind")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'kind' field"))?;
            let kind: cc_switch_core::MemoryKind = serde_json::from_value(kind_value)
                .map_err(|e| RpcError::invalid_params(format!("invalid 'kind' value: {e}")))?;
            let content = get_str_param(params, &["content"])?;
            cc_switch_core::set_hermes_memory(kind, content).map_err(RpcError::app_error)?;
            Ok(Value::Null)
        }

        "get_hermes_memory_limits" => {
            let limits = cc_switch_core::get_hermes_memory_limits().map_err(RpcError::app_error)?;
            serde_json::to_value(limits).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "set_hermes_memory_enabled" => {
            let kind_value = params
                .get("kind")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'kind' field"))?;
            let kind: cc_switch_core::MemoryKind = serde_json::from_value(kind_value)
                .map_err(|e| RpcError::invalid_params(format!("invalid 'kind' value: {e}")))?;
            let enabled = get_bool_param(params, &["enabled"])?;
            let outcome = cc_switch_core::set_hermes_memory_enabled(kind, enabled)
                .map_err(RpcError::app_error)?;
            serde_json::to_value(outcome).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "open_hermes_web_ui" => {
            let path = params.get("path").and_then(|value| value.as_str());
            let target = cc_switch_core::open_hermes_web_ui(path).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(target))
        }

        "launch_hermes_dashboard" => {
            let ok = cc_switch_core::launch_hermes_dashboard().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "scan_openclaw_config_health" => {
            let warnings =
                cc_switch_core::scan_openclaw_config_health().map_err(RpcError::app_error)?;
            Ok(warnings)
        }

        "get_openclaw_default_model" => {
            let model =
                cc_switch_core::get_openclaw_default_model().map_err(RpcError::app_error)?;
            Ok(model)
        }

        "set_openclaw_default_model" => {
            let model_value = params
                .get("model")
                .ok_or_else(|| RpcError::invalid_params("missing 'model' field"))?;
            let model: cc_switch_core::OpenClawDefaultModel =
                serde_json::from_value(model_value.clone())
                    .map_err(|e| RpcError::invalid_params(format!("invalid 'model' value: {e}")))?;
            let result =
                cc_switch_core::set_openclaw_default_model(model).map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_openclaw_model_catalog" => {
            let catalog =
                cc_switch_core::get_openclaw_model_catalog().map_err(RpcError::app_error)?;
            Ok(catalog)
        }

        "set_openclaw_model_catalog" => {
            let catalog_value = params
                .get("catalog")
                .ok_or_else(|| RpcError::invalid_params("missing 'catalog' field"))?;
            let catalog: HashMap<String, cc_switch_core::OpenClawModelCatalogEntry> =
                serde_json::from_value(catalog_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'catalog' value: {e}"))
                })?;
            let result =
                cc_switch_core::set_openclaw_model_catalog(catalog).map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_openclaw_agents_defaults" => {
            let defaults =
                cc_switch_core::get_openclaw_agents_defaults().map_err(RpcError::app_error)?;
            Ok(defaults)
        }

        "set_openclaw_agents_defaults" => {
            let defaults_value = params
                .get("defaults")
                .ok_or_else(|| RpcError::invalid_params("missing 'defaults' field"))?;
            let defaults: cc_switch_core::OpenClawAgentsDefaults =
                serde_json::from_value(defaults_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'defaults' value: {e}"))
                })?;
            let result = cc_switch_core::set_openclaw_agents_defaults(defaults)
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_openclaw_env" => {
            let env = cc_switch_core::get_openclaw_env().map_err(RpcError::app_error)?;
            Ok(env)
        }

        "set_openclaw_env" => {
            let env_value = params
                .get("env")
                .ok_or_else(|| RpcError::invalid_params("missing 'env' field"))?;
            let env: cc_switch_core::OpenClawEnvConfig = serde_json::from_value(env_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'env' value: {e}")))?;
            let result = cc_switch_core::set_openclaw_env(env).map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_openclaw_tools" => {
            let tools = cc_switch_core::get_openclaw_tools().map_err(RpcError::app_error)?;
            Ok(tools)
        }

        "set_openclaw_tools" => {
            let tools_value = params
                .get("tools")
                .ok_or_else(|| RpcError::invalid_params("missing 'tools' field"))?;
            let tools: cc_switch_core::OpenClawToolsConfig =
                serde_json::from_value(tools_value.clone())
                    .map_err(|e| RpcError::invalid_params(format!("invalid 'tools' value: {e}")))?;
            let result = cc_switch_core::set_openclaw_tools(tools).map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_global_proxy_url" => {
            let url = cc_switch_core::get_global_proxy_url(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(url))
        }

        "set_global_proxy_url" => {
            let url = get_str_param(params, &["url"])?;
            cc_switch_core::set_global_proxy_url(core, url).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "test_proxy_url" => {
            let url = get_str_param(params, &["url"])?;
            let result = cc_switch_core::test_proxy_url(url)
                .await
                .map_err(RpcError::app_error)?;
            Ok(result)
        }

        "get_upstream_proxy_status" => {
            let status =
                cc_switch_core::get_upstream_proxy_status().map_err(RpcError::app_error)?;
            Ok(status)
        }

        "scan_local_proxies" => {
            let proxies = cc_switch_core::scan_local_proxies()
                .await
                .map_err(RpcError::app_error)?;
            Ok(proxies)
        }

        "set_window_theme" => {
            let theme = get_str_param(params, &["theme"])?;
            cc_switch_core::set_window_theme(theme).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "read_omo_local_file" => {
            let data = cc_switch_core::read_omo_local_file()
                .await
                .map_err(RpcError::app_error)?;
            Ok(data)
        }

        "get_current_omo_provider_id" => {
            let id =
                cc_switch_core::get_current_omo_provider_id(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(id))
        }

        "disable_current_omo" => {
            cc_switch_core::disable_current_omo(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "read_omo_slim_local_file" => {
            let data = cc_switch_core::read_omo_slim_local_file()
                .await
                .map_err(RpcError::app_error)?;
            Ok(data)
        }

        "get_current_omo_slim_provider_id" => {
            let id = cc_switch_core::get_current_omo_slim_provider_id(core)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(id))
        }

        "disable_current_omo_slim" => {
            cc_switch_core::disable_current_omo_slim(core).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "import_opencode_providers_from_live" => {
            let count = cc_switch_core::import_opencode_providers_from_live(core)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(count))
        }

        "get_opencode_live_provider_ids" => {
            let ids =
                cc_switch_core::get_opencode_live_provider_ids().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ids))
        }

        "open_provider_terminal" => {
            let app = get_str_param(params, &["app"])?;
            let provider_id = get_str_param(params, &["providerId", "provider_id"])?;
            let ok = cc_switch_core::open_provider_terminal(core, app, provider_id)
                .await
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "get_universal_providers" => {
            let providers =
                cc_switch_core::get_universal_providers(core).map_err(RpcError::app_error)?;
            serde_json::to_value(providers).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_universal_provider" => {
            let id = get_str_param(params, &["id"])?;
            let provider =
                cc_switch_core::get_universal_provider(core, id).map_err(RpcError::app_error)?;
            serde_json::to_value(provider).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "upsert_universal_provider" => {
            let provider_value = params
                .get("provider")
                .ok_or_else(|| RpcError::invalid_params("missing 'provider' field"))?;
            let provider: cc_switch_core::UniversalProvider =
                serde_json::from_value(provider_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'provider' value: {e}"))
                })?;
            let ok = cc_switch_core::upsert_universal_provider(core, provider)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "delete_universal_provider" => {
            let id = get_str_param(params, &["id"])?;
            let ok =
                cc_switch_core::delete_universal_provider(core, id).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "sync_universal_provider" => {
            let id = get_str_param(params, &["id"])?;
            let ok =
                cc_switch_core::sync_universal_provider(core, id).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(ok))
        }

        "read_workspace_file" => {
            let filename = get_str_param(params, &["filename"])?;
            let content =
                cc_switch_core::read_workspace_file(filename).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(content))
        }

        "write_workspace_file" => {
            let filename = get_str_param(params, &["filename"])?;
            let content = get_str_param(params, &["content"])?;
            cc_switch_core::write_workspace_file(filename, content).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "list_daily_memory_files" => {
            let files = cc_switch_core::list_daily_memory_files().map_err(RpcError::app_error)?;
            Ok(serde_json::json!(files))
        }

        "read_daily_memory_file" => {
            let filename = get_str_param(params, &["filename"])?;
            let content =
                cc_switch_core::read_daily_memory_file(filename).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(content))
        }

        "write_daily_memory_file" => {
            let filename = get_str_param(params, &["filename"])?;
            let content = get_str_param(params, &["content"])?;
            cc_switch_core::write_daily_memory_file(filename, content)
                .map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "delete_daily_memory_file" => {
            let filename = get_str_param(params, &["filename"])?;
            cc_switch_core::delete_daily_memory_file(filename).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(null))
        }

        "search_daily_memory_files" => {
            let query = get_str_param(params, &["query"])?;
            let results =
                cc_switch_core::search_daily_memory_files(query).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(results))
        }

        "open_workspace_directory" => {
            let subdir = params
                .get("subdir")
                .and_then(|value| value.as_str())
                .unwrap_or("workspace");
            let path =
                cc_switch_core::open_workspace_directory(subdir).map_err(RpcError::app_error)?;
            Ok(serde_json::json!(path))
        }

        // Skill commands
        "get_skills" => {
            let skills = cc_switch_core::get_skills(core)
                .await
                .map_err(RpcError::app_error)?;

            Ok(skills)
        }

        // MCP commands
        "get_mcp_servers" => {
            let servers = cc_switch_core::get_mcp_servers(core).map_err(RpcError::app_error)?;

            serde_json::to_value(servers).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "get_claude_mcp_status" => {
            let status = cc_switch_core::get_claude_mcp_status().map_err(RpcError::app_error)?;

            serde_json::to_value(status).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "read_claude_mcp_config" => {
            let content = cc_switch_core::read_claude_mcp_config().map_err(RpcError::app_error)?;

            Ok(serde_json::json!(content))
        }

        "upsert_claude_mcp_server" => {
            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let spec = params
                .get("spec")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'spec' field"))?;

            let ok =
                cc_switch_core::upsert_claude_mcp_server(id, spec).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "delete_claude_mcp_server" => {
            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let ok = cc_switch_core::delete_claude_mcp_server(id).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "validate_mcp_command" => {
            let cmd = params
                .get("cmd")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'cmd' field"))?;

            let ok = cc_switch_core::validate_mcp_command(cmd).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "get_mcp_config" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let config = cc_switch_core::get_mcp_config(core, app).map_err(RpcError::app_error)?;

            serde_json::to_value(config).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "upsert_mcp_server_in_config" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let spec = params
                .get("spec")
                .cloned()
                .ok_or_else(|| RpcError::invalid_params("missing 'spec' field"))?;

            let sync_other_side = params.get("syncOtherSide").and_then(|v| v.as_bool());

            let ok =
                cc_switch_core::upsert_mcp_server_in_config(core, app, id, spec, sync_other_side)
                    .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "delete_mcp_server_in_config" => {
            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let ok = cc_switch_core::delete_mcp_server_in_config(core, id)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "set_mcp_enabled" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let enabled = params
                .get("enabled")
                .and_then(|v| v.as_bool())
                .ok_or_else(|| RpcError::invalid_params("missing 'enabled' field"))?;

            let ok = cc_switch_core::set_mcp_enabled(core, app, id, enabled)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "upsert_mcp_server" => {
            let server_value = params
                .get("server")
                .ok_or_else(|| RpcError::invalid_params("missing 'server' field"))?;

            let server: cc_switch_core::CoreMcpServer =
                serde_json::from_value(server_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'server' value: {e}"))
                })?;

            cc_switch_core::upsert_mcp_server(core, server).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "delete_mcp_server" => {
            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let ok = cc_switch_core::delete_mcp_server(core, id).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(ok))
        }

        "toggle_mcp_app" => {
            let server_id = params
                .get("serverId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'serverId' field"))?;

            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'app' field"))?;

            let enabled = params
                .get("enabled")
                .and_then(|v| v.as_bool())
                .ok_or_else(|| RpcError::invalid_params("missing 'enabled' field"))?;

            cc_switch_core::toggle_mcp_app(core, server_id, app, enabled)
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        // ========================
        // Prompt commands
        // ========================
        "get_prompts" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let prompts = cc_switch_core::get_prompts(core, app).map_err(RpcError::app_error)?;

            serde_json::to_value(prompts).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "upsert_prompt" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            let prompt_value = params
                .get("prompt")
                .ok_or_else(|| RpcError::invalid_params("missing 'prompt' field"))?;

            let prompt: cc_switch_core::Prompt = serde_json::from_value(prompt_value.clone())
                .map_err(|e| RpcError::invalid_params(format!("invalid 'prompt' value: {e}")))?;

            cc_switch_core::upsert_prompt(core, app, id, prompt).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "delete_prompt" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            cc_switch_core::delete_prompt(core, app, id).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "enable_prompt" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id = params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'id' field"))?;

            cc_switch_core::enable_prompt(core, app, id).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "import_prompt_from_file" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let id =
                cc_switch_core::import_prompt_from_file(core, app).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(id))
        }

        "get_current_prompt_file_content" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .unwrap_or("claude");

            let content = cc_switch_core::get_current_prompt_file_content(app)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(content))
        }

        // ========================
        // Environment commands
        // ========================
        "check_env_conflicts" => {
            let app = params
                .get("app")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'app' field"))?;

            let conflicts =
                cc_switch_core::check_env_conflicts(app).map_err(RpcError::app_error)?;

            serde_json::to_value(conflicts).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "delete_env_vars" => {
            let conflicts_value = params
                .get("conflicts")
                .ok_or_else(|| RpcError::invalid_params("missing 'conflicts' field"))?;

            let conflicts: Vec<cc_switch_core::EnvConflict> =
                serde_json::from_value(conflicts_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'conflicts' value: {e}"))
                })?;

            let backup_info =
                cc_switch_core::delete_env_vars(conflicts).map_err(RpcError::app_error)?;

            serde_json::to_value(backup_info).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "restore_env_backup" => {
            let backup_path = params
                .get("backupPath")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'backupPath' field"))?;

            cc_switch_core::restore_env_backup(backup_path).map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        // ========================
        // Config snippet commands
        // ========================
        "get_claude_common_config_snippet" => {
            let snippet = cc_switch_core::get_claude_common_config_snippet(core)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(snippet))
        }

        "set_claude_common_config_snippet" => {
            let snippet = params.get("snippet").and_then(|v| v.as_str()).unwrap_or("");

            cc_switch_core::set_claude_common_config_snippet(core, snippet)
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        "get_common_config_snippet" => {
            let app_type = params
                .get("appType")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'appType' field"))?;

            let snippet = cc_switch_core::get_common_config_snippet(core, app_type)
                .map_err(RpcError::app_error)?;

            Ok(serde_json::json!(snippet))
        }

        "set_common_config_snippet" => {
            let app_type = params
                .get("appType")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'appType' field"))?;

            let snippet = params.get("snippet").and_then(|v| v.as_str()).unwrap_or("");

            cc_switch_core::set_common_config_snippet(core, app_type, snippet)
                .map_err(RpcError::app_error)?;

            Ok(Value::Null)
        }

        // ========================
        // DeepLink commands
        // ========================
        "parse_deeplink" => {
            let url = params
                .get("url")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'url' field"))?;

            let request = cc_switch_core::parse_deeplink(url).map_err(RpcError::app_error)?;

            serde_json::to_value(request).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "merge_deeplink_config" => {
            let request_value = params
                .get("request")
                .ok_or_else(|| RpcError::invalid_params("missing 'request' field"))?;

            let request: cc_switch_core::DeepLinkImportRequest =
                serde_json::from_value(request_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'request' value: {e}"))
                })?;

            let merged =
                cc_switch_core::merge_deeplink_config(request).map_err(RpcError::app_error)?;

            serde_json::to_value(merged).map_err(|e| RpcError::internal_error(e.to_string()))
        }

        "import_from_deeplink" => {
            let request_value = params
                .get("request")
                .ok_or_else(|| RpcError::invalid_params("missing 'request' field"))?;

            let request: cc_switch_core::DeepLinkImportRequest =
                serde_json::from_value(request_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'request' value: {e}"))
                })?;

            let provider_id =
                cc_switch_core::import_from_deeplink(core, request).map_err(RpcError::app_error)?;

            Ok(serde_json::json!(provider_id))
        }

        "import_from_deeplink_unified" => {
            let request_value = params
                .get("request")
                .ok_or_else(|| RpcError::invalid_params("missing 'request' field"))?;

            let request: cc_switch_core::DeepLinkImportRequest =
                serde_json::from_value(request_value.clone()).map_err(|e| {
                    RpcError::invalid_params(format!("invalid 'request' value: {e}"))
                })?;

            let result = cc_switch_core::import_from_deeplink_unified(core, request)
                .map_err(RpcError::app_error)?;

            Ok(result)
        }

        // Misc commands
        "get_init_error" => {
            // Web 服务器环境下没有初始化错误
            Ok(serde_json::json!(null))
        }

        "get_migration_result" => {
            // Web 服务器环境下没有迁移
            Ok(serde_json::json!(false))
        }

        // ========================
        // Auth commands
        // ========================
        "auth.status" => {
            let enabled = state.auth_config.is_some();
            Ok(serde_json::json!({ "enabled": enabled }))
        }

        "auth.login" => {
            // Check if auth is enabled
            let auth_config = match &state.auth_config {
                Some(config) => config,
                None => {
                    return Ok(serde_json::json!({
                        "success": false,
                        "error": "Authentication not configured"
                    }));
                }
            };

            // Get password from params
            let password = params
                .get("password")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'password' field"))?;

            // Verify password
            if !verify_password(password, &auth_config.password_hash) {
                return Ok(serde_json::json!({
                    "success": false,
                    "error": "Invalid password"
                }));
            }

            // Create session
            let token = state.session_store.create_session();

            Ok(serde_json::json!({
                "success": true,
                "token": token
            }))
        }

        "auth.check" => {
            let token = params
                .get("token")
                .and_then(|v| v.as_str())
                .ok_or_else(|| RpcError::invalid_params("missing 'token' field"))?;

            let valid = state.session_store.validate_session(token);
            Ok(serde_json::json!({ "valid": valid }))
        }

        _ => Err(RpcError::method_not_found(method)),
    }
}
