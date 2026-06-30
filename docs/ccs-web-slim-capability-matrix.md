# ccs-web Slim Capability Matrix

This matrix is the first slim production profile boundary and implementation-gate reference. It is intentionally sanitized for a public repository: no local runtime evidence, private hostnames, IP addresses, tokens, or machine-specific paths belong here.

## Profile Contract

- Default profile: `full`.
- Slim profile activation: explicit publish/build input `-Profile slim`, propagated to backend `CCS_WEB_PROFILE=slim` and frontend `VITE_CCS_WEB_PROFILE=slim`.
- `VITE_CCS_WEB_PROFILE` is not an independent product switch; it must match the backend/build profile exposed by `build-info.json`.
- An omitted profile means `full`; an explicitly provided value other than `full` or `slim` is invalid and must fail closed during build/startup verification.
- Runtime profile environment may assert or tighten behavior, but must not silently convert a slim build to full or a default full build to slim.
- Backend and frontend capability group definitions must come from a shared manifest or be protected by a drift test that fails when slim disabled groups diverge.
- The first implementation stage uses a shared capability manifest plus runtime gates. Compile-time feature slimming is a follow-up stage.
- `ttflows` owns users, business API keys, business billing, user-level audit, public error normalization, and production orchestration. `ccs-web slim` owns upstream provider routing and provider cost observability.

## A+B Mapping

`A+B` is the retained production surface:

| Area | Capability Groups | UI/API Evidence |
| --- | --- | --- |
| A: proxy/router runtime | `proxy`, `failover`, `providers`, `usage` | Proxy status/config, provider routing, failover/circuit breaker, request logs, provider cost observability, OpenAI/Anthropic-compatible proxy paths |
| B: web admin management | `auth`, `providers`, `settings-basic`, `usage`, `backup`, `import-export`, `sync` | Web admin login/session, provider management, usage/pricing/logs/statistics, backup/restore, SQL/config import/export, WebDAV/S3 sync |

Everything outside this mapping must be explicitly retained by the spec or disabled in slim.

## Capability Groups

| Group | Slim | Purpose |
| --- | --- | --- |
| `auth` | retained | Web admin authentication and session checks |
| `providers` | retained | Provider CRUD, switch, sort, live config, model fetch, provider health surface needed by admin UI |
| `proxy` | retained | Proxy service config, status, takeover controls, and OpenAI/Anthropic-compatible proxy paths |
| `failover` | retained | Failover queue, provider health, circuit breaker, auto failover controls |
| `usage` | retained | Usage summaries, pricing, request logs, usage scripts, provider/model stats, read-only quota/usage checks |
| `backup` | retained | Database backup, restore, rename, delete |
| `import-export` | retained | SQL import/export and config import/export needed for migration and rollback |
| `sync` | retained | WebDAV and S3 sync |
| `settings-basic` | retained | General, proxy, auth, usage, logs, and about settings needed by retained views |
| `protocol` | retained | JSON-RPC protocol commands and sanitized public health/build metadata |
| `desktop-helpers` | disabled | Tray, updater, auto launch, desktop dialogs, local open helpers, desktop-only window helpers |
| `skills` | disabled | Skill repo/search/install/update/migration/backup/import ecosystem management |
| `mcp` | disabled | MCP server management and cross-application sync |
| `sessions` | disabled | Session manager and terminal launch |
| `workspace` | disabled | Workspace file editor and local workspace directory open |
| `daily-memory` | disabled | Daily memory file management |
| `third-party-local-tools` | disabled | Claude Desktop repair/config, Hermes local dashboard/memory, OpenClaw tools/env/agents, OpenCode/OMO local files, local prompt file tooling, managed-account login/token/model management |
| `local-env-helpers` | disabled | Local directory picker and environment conflict repair |
| `auth-vault` | disabled | Token/cookie capture and token summary APIs |

## HTTP Routes

| Route | Slim | Group | Gate |
| --- | --- | --- | --- |
| `GET /health` | retained | `protocol` | Public sanitized health |
| `GET /build-info.json` | retained | `protocol` | Public sanitized build metadata with profile and capability manifest |
| `GET /` and static SPA fallback | retained | `protocol` | Static assets only; not a backend security boundary |
| `POST /api/invoke` | retained | `protocol` | Management auth first, then per-command capability gate |
| `GET /api/ws` | retained | `protocol` | Management auth first, then per-message capability gate |
| `POST /api/import-config` | retained | `import-export` | Management auth and route capability gate |
| `GET /api/export-config` | retained | `import-export` | Management auth and route capability gate |
| `POST /api/auth-vault/tokens` | disabled | `auth-vault` | Fixed HTTP 403 `capability_disabled` in slim |
| `GET /api/auth-vault/tokens/summary` | disabled | `auth-vault` | Fixed HTTP 403 `capability_disabled` in slim |
| `* /api/auth-vault/*` unknown subpaths | disabled | `auth-vault` | Fixed HTTP 403 `capability_disabled` in slim |
| `* /api/*` unknown management route | disabled | `unclassified` | Fail closed; must not fall through to SPA |
| Proxy `/status` and OpenAI/Anthropic-compatible paths | retained | `proxy` | Proxy server path; slim must not change routing behavior |

Unknown management routes and unknown RPC commands must fail closed in slim. If web auth is enabled, protected management routes must return `401` before capability or route details are exposed; authenticated unknown management routes may return a JSON `404`/`403` fail-closed response, but never the SPA. The `auth-vault` prefix is an explicit disabled route group in slim and always returns fixed `403 capability_disabled`, including unauthenticated requests, so token/cookie capture is never reachable and the response does not depend on auth state.

## WebSocket Commands

| Command Type | Slim | Group | Gate |
| --- | --- | --- | --- |
| `ping` | retained | `protocol` | Protocol handler |
| `event.subscribe` / `event.unsubscribe` | retained | `protocol` | Protocol handler |
| Business JSON-RPC commands | per command | command group | `dispatch_command` capability gate |
| Unknown business command | disabled | `unclassified` | JSON-RPC error with `capability_disabled` in slim |

## Frontend Views And Actions

| UI Surface | Slim | Group |
| --- | --- | --- |
| Providers view | retained | `providers` |
| Settings view | retained | `settings-basic` |
| Settings general language/theme/app visibility | retained | `settings-basic` |
| Settings proxy tab | retained | `proxy` |
| Web admin auth/session gate | retained | `auth` |
| Settings managed-account auth center | disabled | `third-party-local-tools` |
| Settings usage tab | retained | `usage` |
| Settings about tab | retained | `settings-basic` |
| Settings import/export | retained | `import-export` |
| Settings backup list | retained | `backup` |
| Settings WebDAV/S3 sync | retained | `sync` |
| Settings log config | retained | `settings-basic` |
| Universal providers view | retained | `providers` |
| Provider live import/sync actions for local third-party tools | disabled | `third-party-local-tools` |
| Claude Desktop/OpenClaw/Hermes/OpenCode local config repair actions | disabled | `third-party-local-tools` |
| Proxy toggle and failover toolbar actions | retained | `proxy` / `failover` |
| Refresh usage toolbar action | retained | `usage` |
| Prompts view and prompt toolbar actions | disabled | `third-party-local-tools` |
| Skills and skillsDiscovery views/actions | disabled | `skills` |
| MCP view/actions | disabled | `mcp` |
| Agents view | disabled | `third-party-local-tools` |
| Sessions view/actions | disabled | `sessions` |
| Workspace view/actions | disabled | `workspace` |
| OpenClaw env/tools/agents views | disabled | `third-party-local-tools` |
| Hermes memory view and dashboard launcher | disabled | `third-party-local-tools` |
| Startup environment conflict checks | disabled | `local-env-helpers` |
| Startup skills migration check | disabled | `skills` |
| WebDAV/S3 status listeners | retained | `sync` |
| ThemeProvider desktop theme write side effect | disabled | `desktop-helpers` |
| DeepLinkImportDialog provider import branch | retained | `import-export` / `providers` |
| DeepLinkImportDialog skill/MCP/prompt import branches | disabled | `skills` / `mcp` / `third-party-local-tools` |

Prompt management is classified as disabled for the first slim stage because the current prompt UI manages local prompt files and app-specific local configuration rather than the retained A+B provider/proxy/usage/sync surface. If prompt management later becomes a TTFlows-facing production requirement, it needs a separate product decision and capability group.

Slim frontend behavior:

- A disabled view restored from localStorage must fall back to `providers`.
- A direct attempt to open a disabled view must fall back to `providers` or show a stable unavailable state without loading the disabled lazy component.
- Disabled capability startup side effects must not run.
- Retained views must not call disabled hooks or APIs. Hiding JSX is insufficient.
- `/build-info.json` profile must agree with the baked frontend profile; mismatch is a configuration error.
- Frontend hiding is not a security boundary; backend gates are required.

## RPC Command Groups

The runtime gate must classify every command currently matched by `dispatch_command`. The implementation source of truth should be generated from this matrix and fail closed for unclassified commands in slim.

### `protocol`

- `ping`

### `auth`

- `auth.status`
- `auth.login`
- `auth.check`

### `providers`

- `get_providers`
- `get_current_provider`
- `add_provider`
- `update_provider`
- `delete_provider`
- `switch_provider`
- `import_default_config`
- `update_providers_sort_order`
- `fetch_models_for_config`
- `get_universal_providers`
- `get_universal_provider`
- `upsert_universal_provider`
- `delete_universal_provider`
- `sync_universal_provider`

Provider management remains retained for the web-admin provider database. Commands that read or mutate Claude Desktop, OpenClaw, Hermes, OpenCode, or OMO local files are classified as third-party local tool configuration and are disabled in slim, even when they appear on provider-facing pages.

### `usage`

- `queryProviderUsage`
- `testUsageScript`
- `copilot_get_usage`
- `copilot_get_usage_for_account`
- `get_subscription_quota`
- `get_codex_oauth_quota`
- `get_coding_plan_quota`
- `get_balance`
- `get_usage_summary`
- `get_usage_summary_by_app`
- `get_usage_trends`
- `get_provider_stats`
- `get_model_stats`
- `get_request_logs`
- `get_request_detail`
- `sync_session_usage`
- `get_usage_data_sources`
- `get_model_pricing`
- `update_model_pricing`
- `delete_model_pricing`
- `check_provider_limits`
- `get_default_cost_multiplier`
- `set_default_cost_multiplier`
- `get_pricing_model_source`
- `set_pricing_model_source`

The usage group is provider cost and operations observability only. It is not a TTFlows business billing source of truth. Read-only quota/usage checks remain retained; managed-account login, token retrieval, model retrieval, account mutation, or local subscription-token capture stay classified as third-party local tool configuration and are disabled in slim.

### `proxy`

- `start_proxy_server`
- `stop_proxy_server`
- `stop_proxy_with_restore`
- `get_proxy_takeover_status`
- `set_proxy_takeover_for_app`
- `get_proxy_status`
- `get_proxy_config`
- `update_proxy_config`
- `get_global_proxy_config`
- `update_global_proxy_config`
- `get_proxy_config_for_app`
- `update_proxy_config_for_app`
- `is_proxy_running`
- `is_live_takeover_active`
- `switch_proxy_provider`
- `test_api_endpoints`
- `get_custom_endpoints`
- `add_custom_endpoint`
- `remove_custom_endpoint`
- `update_endpoint_last_used`
- `stream_check_provider`
- `stream_check_all_providers`
- `get_stream_check_config`
- `save_stream_check_config`
- `get_global_proxy_url`
- `set_global_proxy_url`
- `test_proxy_url`
- `get_upstream_proxy_status`
- `scan_local_proxies`

### `failover`

- `get_provider_health`
- `reset_circuit_breaker`
- `get_circuit_breaker_config`
- `update_circuit_breaker_config`
- `get_circuit_breaker_stats`
- `get_failover_queue`
- `get_available_providers_for_failover`
- `add_to_failover_queue`
- `remove_from_failover_queue`
- `get_auto_failover_enabled`
- `set_auto_failover_enabled`

### `settings-basic`

- `get_settings`
- `save_settings`
- `get_rectifier_config`
- `set_rectifier_config`
- `get_optimizer_config`
- `set_optimizer_config`
- `get_log_config`
- `set_log_config`
- `get_claude_config_status`
- `get_config_status`
- `is_portable_mode`
- `get_config_dir`
- `get_claude_code_config_path`
- `get_app_config_path`
- `get_app_config_dir_override`
- `set_app_config_dir_override`
- `extract_common_config_snippet`
- `get_tool_versions`
- `get_init_error`
- `get_migration_result`

### `backup`

- `create_db_backup`
- `list_db_backups`
- `restore_db_backup`
- `rename_db_backup`
- `delete_db_backup`

### `import-export`

- `export_config_to_file`
- `import_config_from_file`
- `parse_deeplink`
- `merge_deeplink_config`
- `import_from_deeplink`
- `import_from_deeplink_unified`

Web/API import and export flows are retained. Desktop file picker commands are desktop helpers and disabled in slim; retained web flows must use browser upload/download paths instead. Implementation review must ensure disabled skill/MCP/prompt deeplink branches cannot bypass slim gates.

### `sync`

- `webdav_test_connection`
- `webdav_sync_upload`
- `webdav_sync_download`
- `webdav_sync_save_settings`
- `webdav_sync_fetch_remote_info`
- `s3_test_connection`
- `s3_sync_upload`
- `s3_sync_download`
- `s3_sync_save_settings`
- `s3_sync_fetch_remote_info`

### `desktop-helpers`

- `update_tray_menu`
- `restart_app`
- `check_for_updates`
- `open_config_folder`
- `open_app_config_folder`
- `open_external`
- `set_auto_launch`
- `get_auto_launch_status`
- `set_window_theme`
- `open_provider_terminal`
- `save_file_dialog`
- `open_file_dialog`
- `open_zip_file_dialog`

### `skills`

- `get_installed_skills`
- `get_skill_backups`
- `delete_skill_backup`
- `discover_available_skills`
- `check_skill_updates`
- `get_skills_for_app`
- `install_skill`
- `install_skill_for_app`
- `uninstall_skill`
- `uninstall_skill_for_app`
- `install_skill_unified`
- `uninstall_skill_unified`
- `restore_skill_backup`
- `toggle_skill_app`
- `scan_unmanaged_skills`
- `import_skills_from_apps`
- `update_skill`
- `migrate_skill_storage`
- `search_skills_sh`
- `get_skill_repos`
- `add_skill_repo`
- `remove_skill_repo`
- `install_skills_from_zip`
- `get_skills_migration_result`
- `get_skills`

### `mcp`

- `import_mcp_from_apps`
- `get_mcp_servers`
- `get_claude_mcp_status`
- `read_claude_mcp_config`
- `upsert_claude_mcp_server`
- `delete_claude_mcp_server`
- `validate_mcp_command`
- `get_mcp_config`
- `upsert_mcp_server_in_config`
- `delete_mcp_server_in_config`
- `set_mcp_enabled`
- `upsert_mcp_server`
- `delete_mcp_server`
- `toggle_mcp_app`

### `sessions`

- `list_sessions`
- `get_session_messages`
- `launch_session_terminal`
- `delete_session`
- `delete_sessions`

### `workspace`

- `read_workspace_file`
- `write_workspace_file`
- `open_workspace_directory`

### `daily-memory`

- `list_daily_memory_files`
- `read_daily_memory_file`
- `write_daily_memory_file`
- `delete_daily_memory_file`
- `search_daily_memory_files`

### `third-party-local-tools`

- `read_live_provider_settings`
- `sync_current_providers_live`
- `remove_provider_from_live_config`
- `import_claude_desktop_providers_from_claude`
- `get_claude_desktop_status`
- `get_claude_desktop_default_routes`
- `apply_claude_plugin_config`
- `get_claude_plugin_status`
- `read_claude_plugin_config`
- `is_claude_plugin_applied`
- `apply_claude_onboarding_skip`
- `clear_claude_onboarding_skip`
- `get_hermes_model_config`
- `get_hermes_memory`
- `set_hermes_memory`
- `get_hermes_memory_limits`
- `set_hermes_memory_enabled`
- `open_hermes_web_ui`
- `launch_hermes_dashboard`
- `import_hermes_providers_from_live`
- `get_hermes_live_provider_ids`
- `scan_openclaw_config_health`
- `get_openclaw_default_model`
- `set_openclaw_default_model`
- `get_openclaw_model_catalog`
- `set_openclaw_model_catalog`
- `get_openclaw_agents_defaults`
- `set_openclaw_agents_defaults`
- `get_openclaw_env`
- `set_openclaw_env`
- `get_openclaw_tools`
- `set_openclaw_tools`
- `import_openclaw_providers_from_live`
- `get_openclaw_live_provider_ids`
- `get_openclaw_live_provider`
- `read_omo_local_file`
- `get_current_omo_provider_id`
- `disable_current_omo`
- `read_omo_slim_local_file`
- `get_current_omo_slim_provider_id`
- `disable_current_omo_slim`
- `import_opencode_providers_from_live`
- `get_opencode_live_provider_ids`
- `auth_start_login`
- `auth_poll_for_account`
- `auth_list_accounts`
- `auth_get_status`
- `auth_remove_account`
- `auth_set_default_account`
- `auth_logout`
- `copilot_start_device_flow`
- `copilot_poll_for_auth`
- `copilot_poll_for_account`
- `copilot_list_accounts`
- `copilot_remove_account`
- `copilot_set_default_account`
- `copilot_get_auth_status`
- `copilot_logout`
- `copilot_is_authenticated`
- `copilot_get_token`
- `copilot_get_token_for_account`
- `copilot_get_models`
- `copilot_get_models_for_account`
- `get_prompts`
- `upsert_prompt`
- `delete_prompt`
- `enable_prompt`
- `import_prompt_from_file`
- `get_current_prompt_file_content`
- `create_caveman_style_profile`
- `get_claude_common_config_snippet`
- `set_claude_common_config_snippet`
- `get_common_config_snippet`
- `set_common_config_snippet`

### `local-env-helpers`

- `pick_directory`
- `check_env_conflicts`
- `delete_env_vars`
- `restore_env_backup`

### `auth-vault`

- `POST /api/auth-vault/tokens`
- `GET /api/auth-vault/tokens/summary`

## Retained Proxy Regression Boundary

Slim must not change these behaviors:

- `/v1/messages`
- `/v1/chat/completions`
- `/v1/responses`
- `/v1/responses/compact`
- provider routing
- failover queue
- circuit breaker
- provider health state
- same-provider/key retry for quota-like 429 responses
- Responses session stickiness

## Test Gate

- Rust unit: omitted profile defaults to `full`; explicit `full` and `slim` are accepted; unknown explicit profile values fail closed.
- Rust unit: slim manifest disables known disabled groups, retained groups stay enabled, and backend/frontend disabled group definitions do not drift.
- Rust unit: every command currently matched by `dispatch_command` is classified exactly once; unclassified commands fail closed in slim.
- Rust route integration: unauthenticated protected `/api/invoke` and `/api/ws` return auth failure before capability details; authenticated disabled commands return HTTP 403 or JSON-RPC `capability_disabled`.
- Rust route integration: `/api/auth-vault/*` returns fixed HTTP 403 `capability_disabled` in slim, including authenticated, unauthenticated, known, and unknown auth-vault subpaths.
- Rust route integration: unknown `/api/*` management routes fail closed and never fall through to the SPA.
- Rust auth: slim production auth config missing, invalid JSON, empty required fields, or invalid hash/config values fail closed unless the explicit local-test no-auth override is set; publish/smoke paths must reject that override.
- Frontend unit/render: slim filters disabled entries; retained provider/proxy/usage/import-export/backup/WebDAV/S3 surfaces remain visible; localStorage disabled view falls back to providers; disabled lazy components and startup side effects do not run.
- Publish script static/AST checks: default is `full`; `slim` is explicit; Docker build args include frontend/backend profile; frontend dist/cache/log/smoke paths are profile-aware; full default tag/compose behavior remains compatible; tests and static checks must not execute publish/deploy.
- Privacy: tracked docs and examples from `git ls-files` contain no private hosts, IPs, local paths, tokens, container IDs, or runtime evidence, verified by mechanical scan.

## Compile-Time Slimming Follow-Up

Compile-time slimming must proceed after the runtime gate is stable:

1. Put `src-tauri` non-production modules behind features.
2. Narrow `cc-switch-core` re-exports/API for headless slim use.
3. Add a `cc-switch-server` `server-slim` feature that disables non-production admin at compile time.

## TTFlows Integration Gate

Before production traffic is routed through slim:

- TTFlows must access `ccs-web slim` only through OpenAI/Anthropic-compatible proxy routes.
- TTFlows must own users, business API keys, business billing, user-level audit, public error normalization, health gating, and production orchestration.
- `ccs-web slim` remains the upstream provider/router manager and provider cost observability surface.
- TTFlows must prove success, failure, timeout, and controlled fallback audit/billing consistency on its side.
- TTFlows must not expose `ccs-web` internal management APIs or upstream provider/private runtime details to end users.
