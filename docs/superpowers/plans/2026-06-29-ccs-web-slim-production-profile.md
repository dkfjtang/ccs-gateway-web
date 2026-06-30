# ccs-web Slim Production Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit opt-in `slim` profile for `ccs-web` that keeps proxy, provider, usage, import/export, backup, and WebDAV/S3 sync while disabling desktop-only, extension ecosystem, third-party local tool, local personal workflow, and auth-vault capabilities.

**Architecture:** Phase 0 freezes a capability matrix before code changes. Phase 1 adds a shared profile/capability manifest, runtime gates for HTTP/WS/RPC, frontend capability filtering, and build/publish profile plumbing without changing proxy routing behavior. Later phases move the disabled surface behind Cargo feature boundaries and document TTFlows integration contracts.

**Tech Stack:** Rust/Axum server, `cc-switch-core`, Tauri headless library, React/Vite frontend, Vitest, Cargo tests, Dockerfile, existing `scripts/publish-local-wsl-ccs-web.ps1`.

---

## Source Spec

- `docs/superpowers/specs/2026-06-29-ccs-web-slim-production-profile-design.md`

## Files

- Create: `docs/ccs-web-slim-capability-matrix.md`
- Create: `crates/server/src/profile.rs`
- Create: `crates/server/tests/slim_profile.rs`
- Create: `src/lib/capabilities.ts`
- Create: `tests/lib/capabilities.test.ts`
- Modify: `crates/server/src/lib.rs`
- Modify: `crates/server/src/state.rs`
- Modify: `crates/server/src/rpc/error.rs`
- Modify: `crates/server/src/api/dispatch.rs`
- Modify: `crates/server/src/api/invoke.rs`
- Modify: `crates/server/src/api/ws.rs`
- Modify: `crates/server/src/main.rs`
- Modify: `src/App.tsx`
- Modify: `src/components/settings/SettingsPage.tsx`
- Modify: `Dockerfile.web`
- Modify: `scripts/publish-local-wsl-ccs-web.ps1`
- Modify: targeted tests under `tests/`

## Non-Negotiable Constraints

- Do not publish or deploy.
- Do not change proxy routing, failover, circuit breaker, 429 retry, or Responses stickiness behavior.
- Do not remove usage, pricing, request log, import/export, backup, WebDAV, or S3 sync.
- Do not use or modify local dirty compose state as production evidence.
- Do not write private hosts, IPs, local absolute paths, tokens, container IDs, runtime logs, or release evidence into tracked docs.
- Keep `full` as the default profile everywhere.
- Treat an omitted profile as `full`; treat any explicit profile value other than `full` or `slim` as an error.
- Do not use `CCS_WEB_SLIM_ALLOW_NO_AUTH` in publish/smoke paths.

---

### Task 0: Capability Matrix And Contract Freeze

**Files:**
- Create: `docs/ccs-web-slim-capability-matrix.md`

- [ ] **Step 1: Create a matrix document from current code**

  Add a sanitized public doc with these sections:

  ```markdown
  # ccs-web Slim Capability Matrix

  ## Profile Contract

  - Default profile: `full`
  - Slim profile activation: explicit publish/build input `-Profile slim`, propagated to backend `CCS_WEB_PROFILE=slim` and frontend `VITE_CCS_WEB_PROFILE=slim`
  - `VITE_CCS_WEB_PROFILE` is not an independent product switch; it must match backend build-info profile
  - Unknown explicit profile values fail closed instead of silently falling back to `full`
  - Runtime profile env may assert/tighten behavior but must not silently convert a slim build to full or a full build to slim

  ## A+B Mapping

  | Area | Capability groups | Evidence |
  | --- | --- | --- |
  | A: proxy/router runtime | `proxy`, `failover`, `providers`, `usage` | provider routing, proxy status/config, failover/circuit breaker, request logs, provider cost observability |
  | B: web admin management | `auth`, `providers`, `settings-basic`, `usage`, `backup`, `import-export`, `sync` | web admin auth, provider management, usage/pricing/logs/statistics, backup/restore, SQL/config import/export, WebDAV/S3 sync |
  ```

  Also include the product裁决 that prompt management is disabled in the first slim stage because the current prompts UI manages local prompt files and app-specific local configuration rather than the retained A+B production surface.

  ## Capability Groups

  | Group | Slim | Purpose |
  | --- | --- | --- |
  | auth | retained | Web admin authentication and session checks |
  | providers | retained | Provider CRUD, switch, sort, live config, model fetch |
  | proxy | retained | Proxy service config/status/takeover controls |
  | failover | retained | Failover queue, provider health, circuit breaker |
  | usage | retained | Usage summaries, pricing, request logs, usage scripts |
  | backup | retained | DB backup, restore, rename, delete |
  | import-export | retained | SQL import/export and config file import/export |
  | sync | retained | WebDAV and S3 sync |
  | settings-basic | retained | General, proxy, auth, usage, logs, about settings needed by retained views |
  | desktop-helpers | disabled | Tray, updater, auto launch, desktop dialogs, local open helpers |
  | skills | disabled | Skill repo/search/install/update/migration/backup/import |
  | mcp | disabled | MCP server management and cross-app sync |
  | sessions | disabled | Session manager and terminal launch |
  | workspace | disabled | Workspace file editor and local workspace directory open |
  | daily-memory | disabled | Daily memory file management |
  | third-party-local-tools | disabled | Claude Desktop repair, Hermes local dashboard/memory, OpenClaw tools/env/agents, OpenCode/OMO local files |
  | local-env-helpers | disabled | Local directory picker and env conflict repair |
  | auth-vault | disabled | Token/cookie capture and token summary APIs |
  | protocol | retained | JSON-RPC protocol commands such as ping/event subscription |
  ```

- [ ] **Step 2: Add HTTP route matrix**

  Include this table and verify it matches `crates/server/src/main.rs`:

  ```markdown
  ## HTTP Routes

  | Route | Slim | Group | Gate |
  | --- | --- | --- | --- |
  | `GET /health` | retained | protocol | public sanitized health |
  | `GET /build-info.json` | retained | protocol | public sanitized build metadata with profile |
  | `GET /` and static SPA fallback | retained | protocol | static assets only |
  | `POST /api/invoke` | retained | protocol | auth first, then per-command capability gate |
  | `GET /api/ws` | retained | protocol | auth first, then per-message capability gate |
  | `POST /api/import-config` | retained | import-export | auth and route capability gate |
  | `GET /api/export-config` | retained | import-export | auth and route capability gate |
  | `POST /api/auth-vault/tokens` | disabled | auth-vault | fixed 403 `capability_disabled` in slim |
  | `GET /api/auth-vault/tokens/summary` | disabled | auth-vault | fixed 403 `capability_disabled` in slim |
  | `* /api/auth-vault/*` unknown subpaths | disabled | auth-vault | fixed 403 `capability_disabled` in slim |
  | `* /api/*` unknown management route | disabled | unclassified | auth first when applicable, then fail closed; must not fall through to SPA |
  | proxy `/status` and OpenAI/Anthropic-compatible paths | retained | proxy | proxy server path, no slim behavior change |
  ```

- [ ] **Step 3: Add frontend view and settings matrix**

  Include this table and verify it matches `src/App.tsx` and `src/components/settings/SettingsPage.tsx`:

  ```markdown
  ## Frontend Views And Actions

  | UI Surface | Slim | Group |
  | --- | --- | --- |
  | providers view | retained | providers |
  | settings view | retained | settings-basic |
  | settings general language/theme/app visibility | retained | settings-basic |
  | settings proxy tab | retained | proxy |
  | settings auth tab | retained | auth |
  | settings usage tab | retained | usage |
  | settings about tab | retained | settings-basic |
  | settings import/export | retained | import-export |
  | settings backup list | retained | backup |
  | settings WebDAV/S3 sync | retained | sync |
  | settings log config | retained | settings-basic |
  | prompts view and prompt toolbar actions | disabled | third-party-local-tools |
  | skills and skillsDiscovery views/actions | disabled | skills |
  | mcp view/actions | disabled | mcp |
  | agents view | disabled | third-party-local-tools |
  | universal providers view | retained | providers |
  | sessions view/actions | disabled | sessions |
  | workspace view/actions | disabled | workspace |
  | openclawEnv/openclawTools/openclawAgents views | disabled | third-party-local-tools |
  | hermesMemory view and dashboard launcher | disabled | third-party-local-tools |
  | startup env conflict check | disabled | local-env-helpers |
  | startup skills migration check | disabled | skills |
  | WebDAV/S3 status listeners | retained | sync |
  ```

- [ ] **Step 4: Add RPC command matrix summary**

  Do not paste every implementation body. Group the existing commands from `crates/server/src/api/dispatch.rs` by capability:

  ```markdown
  ## RPC Command Groups

  - `providers`: `get_providers`, `get_current_provider`, `add_provider`, `update_provider`, `delete_provider`, `switch_provider`, `update_providers_sort_order`, `read_live_provider_settings`, `fetch_models_for_config`, provider live import/read helpers that feed retained provider management.
  - `usage`: `queryProviderUsage`, `testUsageScript`, `get_usage_summary`, `get_usage_summary_by_app`, `get_usage_trends`, `get_provider_stats`, `get_model_stats`, `get_request_logs`, `get_request_detail`, `sync_session_usage`, `get_usage_data_sources`, `get_model_pricing`, `update_model_pricing`, `delete_model_pricing`, pricing multiplier/source commands, quota/balance commands used by retained usage UI.
  - `proxy`: proxy start/stop/status/config/takeover/global proxy/upstream proxy/stream check commands.
  - `failover`: provider health, circuit breaker, failover queue, auto failover commands.
  - `settings-basic`: settings, rectifier/optimizer/log config, config status, migration result, init error, auth status/login/check commands.
  - `backup`: DB backup list/create/restore/rename/delete commands.
  - `import-export`: config import/export and live sync commands retained for rollback/config migration.
  - `sync`: WebDAV and S3 test/upload/download/save/fetch commands.
  - `desktop-helpers`: tray menu, restart/update/portable/config folder/dialog/auto launch/window theme/local open helpers.
  - `skills`: all skill install/search/repo/migration/backup/import commands and `get_skills_migration_result`.
  - `mcp`: all MCP import/read/upsert/delete/toggle/validate commands.
  - `sessions`: session list/messages/delete/terminal commands.
  - `workspace`: workspace file read/write/open commands.
  - `daily-memory`: daily memory list/read/write/delete/search commands.
  - `third-party-local-tools`: Claude Desktop repair/status/routes/plugin, Hermes local memory/dashboard, OpenClaw local env/tools/agents/config, OpenCode/OMO local file/disable, prompts that manage local prompt files.
  - `local-env-helpers`: env conflict scan/delete/restore and local directory picker commands.
  - `auth-vault`: route-only token capture APIs.
  ```

- [ ] **Step 5: Add test coverage matrix**

  Include the tests that must exist before implementation is considered complete:

  ```markdown
  ## Test Gate

  - Rust unit: omitted profile defaults to `full`; explicit `full`/`slim` are accepted; unknown explicit values fail closed.
  - Rust unit: every current `dispatch_command` command is classified exactly once; unclassified commands fail closed in slim.
  - Rust integration: unauthenticated protected `/api/invoke` and `/api/ws` return auth failure before capability details; authenticated disabled commands return HTTP 403 or JSON-RPC `capability_disabled`.
  - Rust integration: slim route gate disables all `/api/auth-vault/*` paths with fixed `403 capability_disabled` before auth state matters; unknown `/api/*` management routes fail closed and never fall through to SPA.
  - Rust auth: slim production auth config missing, invalid JSON, empty required fields, or invalid hash/config values fail closed unless explicit non-production no-auth override is present.
  - Frontend unit/render: slim filters disabled views/actions; localStorage disabled view falls back to providers; disabled lazy components and startup side effects do not run; retained WebDAV/S3/import-export/usage/proxy/provider surfaces remain visible.
  - Frontend/backend drift: disabled group and view mapping must be generated from shared manifest or covered by a drift test.
  - Publish script: default `full`; explicit `slim`; Docker build args include frontend/backend profile; frontend dist/cache/log/smoke are profile-aware; tests/static checks prove no publish command is executed.
  ```

- [ ] **Step 6: Run doc hygiene checks**

  Run:

  ```powershell
  git diff -- docs/ccs-web-slim-capability-matrix.md
  ```

  Expected: no private hostnames, IPs, local absolute paths, tokens, container IDs, or runtime evidence.

### Task 1: Server Profile Manifest And Capability Gate

**Files:**
- Create: `crates/server/src/profile.rs`
- Modify: `crates/server/src/lib.rs`
- Modify: `crates/server/src/state.rs`
- Modify: `crates/server/src/rpc/error.rs`
- Modify: `crates/server/src/api/dispatch.rs`
- Create: `crates/server/tests/slim_profile.rs`

- [ ] **Step 1: Write failing tests for profile parsing and command classification**

  Add tests in `crates/server/tests/slim_profile.rs` that assert:

  ```rust
  use cc_switch_server::profile::{CapabilityGroup, CcsWebProfile, ProfileConfig};

  #[test]
  fn default_profile_is_full() {
      assert_eq!(
          ProfileConfig::from_env_value(None).unwrap().profile,
          CcsWebProfile::Full
      );
  }

  #[test]
  fn unknown_explicit_profile_is_rejected() {
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
  fn unknown_commands_fail_closed_in_slim() {
      let config = ProfileConfig::from_env_value(Some("slim")).unwrap();
      let err = config.ensure_command_allowed("new_unclassified_command").unwrap_err();
      assert_eq!(err.code, -32043);
      assert_eq!(err.data.as_ref().unwrap()["error"], "capability_disabled");
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
          "webdav_sync_save_settings",
          "s3_sync_save_settings",
          "create_db_backup",
          "export_config_to_file",
      ] {
          config.ensure_command_allowed(command).unwrap();
      }
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
      ] {
          let err = config.ensure_command_allowed(command).unwrap_err();
          assert_eq!(err.code, -32043);
      }
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  Run:

  ```powershell
  cargo test --manifest-path crates/server/Cargo.toml --test slim_profile
  ```

  Expected: FAIL because `profile` module does not exist.

- [ ] **Step 3: Implement `profile.rs`**

  Add:

  ```rust
  use serde::Serialize;
  use std::collections::BTreeSet;

  use crate::rpc::RpcError;

  #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
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

  #[derive(Debug, Clone)]
  pub struct ProfileConfig {
      pub profile: CcsWebProfile,
  }

  impl ProfileConfig {
      pub fn from_env() -> Result<Self, String> {
          Self::from_env_value(std::env::var("CCS_WEB_PROFILE").ok().as_deref())
      }

      pub fn from_env_value(value: Option<&str>) -> Result<Self, String> {
          let profile = match value.unwrap_or("full").trim().to_ascii_lowercase().as_str() {
              "slim" => CcsWebProfile::Slim,
              "full" | "" => CcsWebProfile::Full,
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
          let disabled = all.into_iter().filter(|group| !enabled.contains(group)).collect();
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
  ```

  Then add exact command group mapping in the same file using `matches!` arms copied from the current `dispatch_command` command names. Use the matrix from Task 0 as the source of truth. In slim, every command not listed must fail closed.

  Add a test helper such as `classified_command_names()` and a test that compares it directly with the existing `cc_switch_server::api::RPC_BUSINESS_METHODS` live constant and the dispatch parser used by `tauri_rpc_consistency.rs`. The test must fail when a new command is added without classification. Include `PUBLIC_METHODS` commands (`auth.status`, `auth.login`, `auth.check`) because they still dispatch business auth logic.

- [ ] **Step 4: Export profile module**

  Modify `crates/server/src/lib.rs`:

  ```rust
  pub mod profile;
  ```

- [ ] **Step 5: Store profile config in server state**

  Modify `crates/server/src/state.rs` to add:

  ```rust
  use crate::profile::ProfileConfig;

  pub profile: ProfileConfig,
  ```

  Add a `profile: ProfileConfig` parameter to `ServerState::new` and store it.

- [ ] **Step 6: Add structured capability error**

  Modify `crates/server/src/rpc/error.rs`:

  ```rust
  pub fn capability_disabled(capability: &str, command: Option<&str>) -> Self {
      let mut data = serde_json::json!({
          "error": "capability_disabled",
          "capability": capability,
          "message": "This capability is disabled in the current ccs-web profile."
      });
      if let Some(command) = command {
          data["command"] = serde_json::json!(command);
      }
      Self {
          code: -32043,
          message: "capability_disabled".into(),
          data: Some(data),
      }
  }
  ```

- [ ] **Step 7: Gate dispatch before command execution**

  At the top of `dispatch_command`, before matching command names:

  ```rust
  state.profile.ensure_command_allowed(method)?;
  ```

- [ ] **Step 8: Run targeted Rust test**

  Run:

  ```powershell
  cargo test --manifest-path crates/server/Cargo.toml --test slim_profile
  cargo test --manifest-path crates/server/Cargo.toml --test slim_routes
  cargo test --manifest-path crates/server/Cargo.toml --test slim_ws
  ```

  Expected: PASS.

### Task 2: HTTP/WS Route Gates, Build Info Profile, And Slim Auth Fail-Closed

**Files:**
- Modify: `crates/server/src/main.rs`
- Modify: `crates/server/src/api/invoke.rs`
- Modify: `crates/server/src/api/ws.rs`
- Modify: `crates/server/src/auth.rs`
- Modify: `crates/server/src/rpc/error.rs`
- Create: `crates/server/tests/slim_routes.rs`
- Modify: `crates/server/tests/slim_profile.rs`

- [ ] **Step 1: Add failing route integration tests**

  Create `crates/server/tests/slim_routes.rs`. Build a reusable test router that mirrors the production `/api` route wiring, injects `ProfileConfig`, and uses a temporary authenticated session. The tests must assert:

  ```rust
  #[tokio::test]
  async fn unauthenticated_invoke_gets_401_before_capability_details() {
      // slim + auth enabled + disabled command without session
      // POST /api/invoke {"command":"get_installed_skills","payload":{}}
      // Expected: 401 and no "capability_disabled" body.
  }

  #[tokio::test]
  async fn authenticated_disabled_invoke_gets_403_capability_disabled() {
      // slim + auth enabled + valid session
      // POST /api/invoke {"command":"get_installed_skills","payload":{}}
      // Expected: 403 with error=capability_disabled, capability=skills, command=get_installed_skills.
  }

  #[tokio::test]
  async fn retained_invoke_command_is_not_blocked_by_slim_capability_gate() {
      // slim + auth enabled + valid session
      // POST /api/invoke {"command":"ping","payload":{}}
      // Expected: 200 and result.pong=true.
  }

  #[tokio::test]
  async fn auth_vault_known_and_unknown_paths_are_403_in_slim() {
      // POST /api/auth-vault/tokens
      // GET /api/auth-vault/tokens/summary
      // GET /api/auth-vault/anything-else
      // Run with and without a valid session.
      // Expected for all: fixed 403 capability_disabled with capability=auth-vault.
  }

  #[tokio::test]
  async fn unknown_api_route_does_not_fall_through_to_spa() {
      // slim test app with SPA fallback enabled
      // GET /api/nonexistent-management-route
      // Expected: JSON fail-closed status, not text/html and not index.html.
  }

  #[tokio::test]
  async fn build_info_exposes_sanitized_profile_and_capabilities() {
      // full and slim profile configs
      // Expected: profile is full/slim and no local path or private runtime data is present.
  }
  ```

  Extend `crates/server/tests/ws_event_subscription.rs` or create `crates/server/tests/slim_ws.rs`:

  ```rust
  #[tokio::test]
  async fn unauthenticated_ws_upgrade_gets_401_before_capability_details() {
      // slim + auth enabled + no valid session
      // GET /api/ws
      // Expected: 401 during upgrade and no JSON-RPC capability payload.
  }

  #[tokio::test]
  async fn authenticated_disabled_ws_command_returns_jsonrpc_capability_error_and_keeps_socket_open() {
      // slim + auth enabled + valid session
      // Send get_installed_skills.
      // Expected: JSON-RPC error contains capability_disabled, capability=skills, command=get_installed_skills.
      // Then send ping.
      // Expected: second response succeeds, proving the socket stayed open.
  }
  ```

  Extend `crates/server/tests/slim_profile.rs` with the stable error payload unit test:

  ```rust
  #[test]
  fn capability_error_has_stable_payload() {
      let err = cc_switch_server::rpc::RpcError::capability_disabled("skills", Some("get_installed_skills"));
      assert_eq!(err.code, -32043);
      assert_eq!(err.message, "capability_disabled");
      assert_eq!(err.data.as_ref().unwrap()["error"], "capability_disabled");
      assert_eq!(err.data.as_ref().unwrap()["capability"], "skills");
      assert_eq!(err.data.as_ref().unwrap()["command"], "get_installed_skills");
  }
  ```

  Handler-only tests are not sufficient for this task. Route integration tests are required before implementation can be considered complete.

- [ ] **Step 2: Run tests and confirm failure**

  Run:

  ```powershell
  cargo test --manifest-path crates/server/Cargo.toml --test slim_profile
  ```

  Expected: FAIL until response conversion and profile code exist.

- [ ] **Step 3: Add profile to build info**

  Modify `BuildInfo` in `crates/server/src/main.rs`:

  ```rust
  profile: cc_switch_server::profile::CcsWebProfile,
  capabilities: cc_switch_server::profile::CapabilityManifest,
  ```

  Make `current_build_info(profile: &ProfileConfig)` include sanitized profile and manifest.

- [ ] **Step 4: Initialize profile once**

  In `main`, before auth config:

  ```rust
  let profile = cc_switch_server::profile::ProfileConfig::from_env().unwrap_or_else(|err| {
      tracing::error!(error = %err, "Invalid ccs-web profile");
      std::process::exit(1);
  });
  tracing::info!(profile = ?profile.profile, "ccs-web profile selected");
  ```

  Pass `profile.clone()` into `ServerState::new`.

- [ ] **Step 5: Return HTTP 403 for capability-disabled invoke**

  In `invoke_handler`, when `dispatch_command` returns an error whose `data.error == "capability_disabled"`, return:

  ```rust
  StatusCode::FORBIDDEN
  ```

  And include a JSON error payload with at least `error`, `capability`, `command`, and `message`.

- [ ] **Step 6: Keep WS capability errors as JSON-RPC errors**

  Ensure `ws.rs` returns `RpcResponse::error(Some(id), err)` for capability errors. Do not close the socket or return success with `null`.

- [ ] **Step 7: Gate auth-vault routes in slim**

  Add prefix-level route wrappers in `main.rs` or `api/auth_vault.rs` that call:

  ```rust
  state.profile.ensure_group_allowed(CapabilityGroup::AuthVault)
  ```

  In slim, every `/api/auth-vault/*` path, including currently unknown subpaths, returns fixed HTTP 403 JSON:

  ```json
  {
    "error": "capability_disabled",
    "capability": "auth-vault",
    "message": "This capability is disabled in the current ccs-web profile."
  }
  ```

- [ ] **Step 8: Add slim production auth fail-closed**

  Add a function in `auth.rs` or `profile.rs`:

  ```rust
  pub fn slim_no_auth_override_enabled() -> bool {
      std::env::var("CCS_WEB_SLIM_ALLOW_NO_AUTH")
          .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
          .unwrap_or(false)
  }
  ```

  Replace the current `load_auth_config() -> Option<AuthConfig>` ambiguity with a result type that distinguishes:

  - missing config
  - unreadable config
  - invalid JSON
  - empty required fields
  - invalid or unverifiable password hash/config values

  In `main`, if profile is slim and auth config is missing or invalid, exit with non-zero unless `CCS_WEB_SLIM_ALLOW_NO_AUTH=1` is explicitly set. This override is for local development/tests only and must not be used by publish smoke.

- [ ] **Step 9: Add auth fail-closed tests**

  Add tests that cover:

  ```rust
  #[test]
  fn slim_auth_policy_rejects_missing_invalid_and_empty_auth_config() {
      // missing file, invalid JSON, empty password_hash, invalid bcrypt hash are all rejected in slim production.
  }

  #[test]
  fn full_profile_preserves_existing_no_auth_default() {
      // full profile can still run with no auth config to preserve current behavior.
  }

  #[test]
  fn slim_local_no_auth_override_is_explicit() {
      // slim no-auth only passes when CCS_WEB_SLIM_ALLOW_NO_AUTH is explicitly true.
  }
  ```

- [ ] **Step 10: Add unknown management route fail-closed implementation**

  Ensure `/api/*` requests that do not match known API routes cannot fall through to `static_handler`. In slim they must return a JSON fail-closed response. Keep static SPA fallback for non-API paths.

- [ ] **Step 11: Run targeted Rust tests**

  Run:

  ```powershell
  cargo test --manifest-path crates/server/Cargo.toml --test slim_profile
  cargo test --manifest-path crates/server/Cargo.toml --test slim_routes
  cargo test --manifest-path crates/server/Cargo.toml --test slim_ws
  cargo test --manifest-path crates/server/Cargo.toml
  ```

  Expected: PASS.

### Task 3: Frontend Capability Manifest And Slim UI Filtering

**Files:**
- Create: `src/lib/capabilities.ts`
- Create: `tests/lib/capabilities.test.ts`
- Create: `tests/integration/App.slim-profile.test.tsx`
- Create: `tests/components/SettingsPage.slim-profile.test.tsx`
- Modify: `src/App.tsx`
- Modify: `src/components/settings/SettingsPage.tsx`

- [ ] **Step 1: Write frontend capability tests first**

  Create `tests/lib/capabilities.test.ts`:

  ```ts
  import { describe, expect, it } from "vitest";
  import {
    getCapabilityProfile,
    isCapabilityGroupEnabled,
    normalizeViewForProfile,
    viewCapabilityGroup,
  } from "@/lib/capabilities";

  describe("slim frontend capabilities", () => {
    it("defaults to full", () => {
      expect(getCapabilityProfile(undefined)).toBe("full");
    });

    it("rejects unknown explicit profiles", () => {
      expect(() => getCapabilityProfile("unexpected")).toThrow(/invalid/i);
    });

    it("disables extension and local workflow views in slim", () => {
      expect(isCapabilityGroupEnabled("slim", "skills")).toBe(false);
      expect(isCapabilityGroupEnabled("slim", "mcp")).toBe(false);
      expect(isCapabilityGroupEnabled("slim", "sessions")).toBe(false);
      expect(isCapabilityGroupEnabled("slim", "workspace")).toBe(false);
      expect(isCapabilityGroupEnabled("slim", "third-party-local-tools")).toBe(false);
    });

    it("keeps provider proxy usage import export backup and sync groups in slim", () => {
      for (const group of ["providers", "proxy", "usage", "import-export", "backup", "sync"] as const) {
        expect(isCapabilityGroupEnabled("slim", group)).toBe(true);
      }
    });

    it("falls back from disabled stored views", () => {
      expect(normalizeViewForProfile("slim", "skills")).toBe("providers");
      expect(normalizeViewForProfile("slim", "mcp")).toBe("providers");
      expect(normalizeViewForProfile("slim", "sessions")).toBe("providers");
      expect(normalizeViewForProfile("slim", "providers")).toBe("providers");
      expect(normalizeViewForProfile("slim", "settings")).toBe("settings");
    });

    it("maps known views to groups", () => {
      expect(viewCapabilityGroup("hermesMemory")).toBe("third-party-local-tools");
      expect(viewCapabilityGroup("openclawTools")).toBe("third-party-local-tools");
      expect(viewCapabilityGroup("workspace")).toBe("workspace");
    });
  });
  ```

  Also add a drift test that compares the frontend disabled group list with the backend manifest fixture exported by the Rust profile module or a checked-in shared JSON manifest. The test must fail if backend and frontend disagree about which groups are disabled in slim. Add a build-info/profile consistency test so the frontend profile helper treats `VITE_CCS_WEB_PROFILE` as the backend-propagated value, not an independent switch.

- [ ] **Step 2: Run tests and confirm failure**

  Run:

  ```powershell
  pnpm vitest run tests/lib/capabilities.test.ts
  ```

  Expected: FAIL because `src/lib/capabilities.ts` does not exist.

- [ ] **Step 3: Implement frontend capability helpers**

  Create `src/lib/capabilities.ts` with:

  ```ts
  export type CcsWebProfile = "full" | "slim";

  export type CapabilityGroup =
    | "auth"
    | "providers"
    | "proxy"
    | "failover"
    | "usage"
    | "backup"
    | "import-export"
    | "sync"
    | "settings-basic"
    | "protocol"
    | "desktop-helpers"
    | "skills"
    | "mcp"
    | "sessions"
    | "workspace"
    | "daily-memory"
    | "third-party-local-tools"
    | "local-env-helpers"
    | "auth-vault";

  export type SlimAwareView =
    | "providers"
    | "settings"
    | "prompts"
    | "skills"
    | "skillsDiscovery"
    | "mcp"
    | "agents"
    | "universal"
    | "sessions"
    | "workspace"
    | "openclawEnv"
    | "openclawTools"
    | "openclawAgents"
    | "hermesMemory";

  export const getCapabilityProfile = (value = import.meta.env.VITE_CCS_WEB_PROFILE): CcsWebProfile => {
    if (!value || value === "full") return "full";
    if (value === "slim") return "slim";
    throw new Error(`Invalid VITE_CCS_WEB_PROFILE value: ${value}`);
  };

  export const isCapabilityGroupEnabled = (profile: CcsWebProfile, group: CapabilityGroup): boolean => {
    if (profile === "full") return true;
    return ![
      "desktop-helpers",
      "skills",
      "mcp",
      "sessions",
      "workspace",
      "daily-memory",
      "third-party-local-tools",
      "local-env-helpers",
      "auth-vault",
    ].includes(group);
  };

  export const viewCapabilityGroup = (view: SlimAwareView): CapabilityGroup => {
    switch (view) {
      case "providers":
      case "universal":
        return "providers";
      case "settings":
        return "settings-basic";
      case "skills":
      case "skillsDiscovery":
        return "skills";
      case "mcp":
        return "mcp";
      case "sessions":
        return "sessions";
      case "workspace":
        return "workspace";
      case "prompts":
      case "agents":
      case "openclawEnv":
      case "openclawTools":
      case "openclawAgents":
      case "hermesMemory":
        return "third-party-local-tools";
    }
  };

  export const isViewEnabled = (profile: CcsWebProfile, view: SlimAwareView): boolean =>
    isCapabilityGroupEnabled(profile, viewCapabilityGroup(view));

  export const normalizeViewForProfile = (profile: CcsWebProfile, view: SlimAwareView): SlimAwareView =>
    isViewEnabled(profile, view) ? view : "providers";
  ```

- [ ] **Step 4: Apply view normalization in `App.tsx`**

  Import helpers. Use `getCapabilityProfile()` to compute `capabilityProfile`. Update `getInitialView` and every `setCurrentView` path so disabled views fall back to `providers` in slim. Prevent disabled lazy components from rendering by normalizing before `switch (currentView)`.

  Product decision: keep `providers`, `settings`, and `universal` enabled; disable `prompts` in slim because the current prompt UI operates on local prompt files/app-specific local configuration and is outside the retained A+B production surface.

- [ ] **Step 5: Disable startup side effects in slim**

  Guard these effects in `App.tsx`:

  ```ts
  if (capabilityProfile === "slim") return;
  ```

  Apply to:

  - startup all-app env conflict check
  - app-switch env conflict check
  - skills migration check
  - OpenClaw health hook enablement

  Keep WebDAV/S3 status listeners and build update monitor.

- [ ] **Step 6: Hide disabled toolbar actions in slim**

  Add helper checks around toolbar/view launch buttons for:

  - skills
  - skillsDiscovery
  - mcp
  - sessions
  - workspace
  - prompts
  - Hermes memory/dashboard
  - OpenClaw env/tools/agents

- [ ] **Step 7: Filter settings content**

  In `SettingsPage.tsx`, hide slim-disabled settings sections:

  - `SkillStorageLocationSettings`
  - `SkillSyncMethodSettings`
  - `WindowSettings`
  - `DirectorySettings`

  Keep:

  - import/export
  - backup list
  - WebDAV/S3 sync
  - auth
  - proxy
  - usage
  - log config
  - about

  Do not only hide rendered sections. Prevent disabled hooks/queries from firing in slim, including `useInstalledSkills()` and any skill sync/storage queries. The slim test must assert those mocks are not called.

- [ ] **Step 8: Run frontend targeted tests**

  Add render tests before running:

  ```ts
  describe("App slim profile", () => {
    it("does not render disabled toolbar launchers", async () => {
      // Mock VITE_CCS_WEB_PROFILE=slim and render App with providers view.
      // Assert skills, MCP, sessions, workspace, Hermes dashboard, OpenClaw env/tools/agents launchers are absent.
      // Assert provider add, proxy/failover, and usage refresh surfaces that are applicable remain present.
    });

    it("falls back from localStorage disabled view without loading disabled component", async () => {
      // Seed localStorage cc-switch-last-view=skills.
      // Mock skills component import or visible text.
      // Expected current view is providers and skills content is absent.
    });

    it("does not run slim-disabled startup side effects", async () => {
      // Mock checkAllEnvConflicts, checkEnvConflicts, invoke(get_skills_migration_result), and OpenClaw health hook.
      // Expected they are not called in slim.
      // WebDAV/S3 listeners remain registered.
    });
  });
  ```

  Add settings render tests:

  ```ts
  describe("SettingsPage slim profile", () => {
    it("keeps retained import export backup WebDAV S3 auth proxy usage sections", () => {});
    it("hides skill storage, skill sync, window, and directory local-helper settings", () => {});
  });
  ```

  Run:

  ```powershell
  pnpm vitest run tests/lib/capabilities.test.ts tests/integration/App.test.tsx tests/components/SettingsDialog.test.tsx
  pnpm vitest run tests/integration/App.slim-profile.test.tsx tests/components/SettingsPage.slim-profile.test.tsx
  ```

  Expected: PASS or only pre-existing unrelated failures documented with exact failure text.

### Task 4: Docker And Local WSL Publish Script Profile Plumbing Without Publishing

**Files:**
- Modify: `Dockerfile.web`
- Modify: `scripts/publish-local-wsl-ccs-web.ps1`
- Create: `scripts/test-publish-local-wsl-ccs-web-profile.ps1`

- [ ] **Step 1: Inspect existing build args and publish script flow**

  Run:

  ```powershell
  Select-String -LiteralPath Dockerfile.web -Pattern 'ARG|ENV|pnpm|cargo|docker' -Encoding UTF8
  Select-String -LiteralPath scripts/publish-local-wsl-ccs-web.ps1 -Pattern 'param|docker build|docker compose|Image|Tag|Build' -Encoding UTF8
  ```

- [ ] **Step 2: Add Docker build args**

  Add profile args in every stage that needs them. `VITE_CCS_WEB_PROFILE` must exist before the frontend build command runs, and `CCS_WEB_PROFILE` must exist in the final runtime image:

  ```dockerfile
  ARG CCS_WEB_PROFILE=full
  ENV VITE_CCS_WEB_PROFILE=${CCS_WEB_PROFILE}
  ```

  In the runtime stage add:

  ```dockerfile
  ARG CCS_WEB_PROFILE=full
  ENV CCS_WEB_PROFILE=${CCS_WEB_PROFILE}
  ```

  Do not rely on a build arg declared in one stage being visible in another stage.

- [ ] **Step 3: Add publish script parameter**

  In `scripts/publish-local-wsl-ccs-web.ps1`, add:

  ```powershell
  [ValidateSet('full', 'slim')]
  [string]$Profile = 'full',
  ```

  Add profile to:

  - `docker buildx bake` build args
  - `docker buildx build --target frontend-dist` build args
  - compose image/tag environment used by build and up paths
  - frontend dist snapshot/cache key
  - local log names
  - smoke/build-info assertions
  - rollback metadata

  Do not only modify display variables such as `$Image`; verify the same profile-aware tag/env is used by build, inspect, compose up, health/smoke, and rollback paths. Do not execute publish in this task.

- [ ] **Step 4: Preserve default full behavior**

  Ensure no caller must pass `-Profile full`; default behavior remains current full profile. For default full:

  - existing image tag remains compatible with the current local WSL flow
  - compose service name, port, health checks, and log directory behavior remain current
  - no profile suffix is added to existing full tags unless the current script already creates immutable secondary tags

  Slim requires explicit `-Profile slim` and may use slim-specific immutable tags/log/cache names.

- [ ] **Step 5: Add static non-publishing verification script**

  Create `scripts/test-publish-local-wsl-ccs-web-profile.ps1`. It must not run Docker, WSL, compose, build, up, restart, health, or publish commands. It should parse and inspect files only:

  ```powershell
  $ErrorActionPreference = 'Stop'
  $script = Get-Content -LiteralPath 'scripts/publish-local-wsl-ccs-web.ps1' -Raw -Encoding UTF8
  $dockerfile = Get-Content -LiteralPath 'Dockerfile.web' -Raw -Encoding UTF8

  if ($script -notmatch "\\[ValidateSet\\('full',\\s*'slim'\\)\\]") { throw 'Missing Profile ValidateSet' }
  if ($script -notmatch "\\$Profile\\s*=\\s*'full'") { throw 'Profile default must be full' }
  if ($script -notmatch 'CCS_WEB_PROFILE') { throw 'Publish script must pass CCS_WEB_PROFILE' }
  if ($script -notmatch 'VITE_CCS_WEB_PROFILE') { throw 'Publish script must pass VITE_CCS_WEB_PROFILE or equivalent frontend build arg' }
  if ($script -match 'CCS_WEB_SLIM_ALLOW_NO_AUTH\\s*=\\s*1') { throw 'Publish script must not enable slim no-auth override' }
  if ($script -notmatch 'Remove-Item\\s+Env:CCS_WEB_SLIM_ALLOW_NO_AUTH|CCS_WEB_SLIM_ALLOW_NO_AUTH\\s*=\\s*0') { throw 'Publish/smoke path must clear or reject inherited slim no-auth override' }
  if ($dockerfile -notmatch 'ARG\\s+CCS_WEB_PROFILE=full') { throw 'Dockerfile missing CCS_WEB_PROFILE arg' }
  if ($dockerfile -notmatch 'VITE_CCS_WEB_PROFILE') { throw 'Dockerfile missing frontend profile env' }
  if ($dockerfile -notmatch 'ENV\\s+CCS_WEB_PROFILE=') { throw 'Dockerfile missing runtime profile env' }

  $parallelScripts = git ls-files --others --exclude-standard scripts |
    Where-Object { $_ -ne 'scripts/test-publish-local-wsl-ccs-web-profile.ps1' } |
    Select-String -Pattern 'publish|deploy|release'
  if ($parallelScripts) { throw "Unexpected untracked publish/deploy/release script: $parallelScripts" }
  ```

  If the final implementation uses helper functions instead of literal text, update this script to parse those helpers, but keep it read-only.

- [ ] **Step 6: Add non-publishing verification**

  Run:

  ```powershell
  powershell -NoProfile -File .\scripts\test-publish-local-wsl-ccs-web-profile.ps1
  git diff -- Dockerfile.web scripts/publish-local-wsl-ccs-web.ps1
  git diff --check -- Dockerfile.web scripts/publish-local-wsl-ccs-web.ps1 scripts/test-publish-local-wsl-ccs-web-profile.ps1
  ```

  Expected: static diff shows profile plumbing only. No release, deployment, container recreate, compose up, Docker build, WSL publish, or health command should be run.

### Task 5: Phase 2/3 Follow-Up Contracts

**Files:**
- Modify: `docs/ccs-web-slim-capability-matrix.md`
- Optionally create: `docs/ccs-web-slim-ttflows-contract.md`

- [ ] **Step 1: Add compile-time slimming follow-up**

  Document that compile-time feature work must proceed in this order:

  ```markdown
  1. `src-tauri` non-production modules behind features.
  2. `cc-switch-core` re-exports/API narrowed for headless slim use.
  3. `cc-switch-server` `server-slim` feature disables non-production admin at compile time.
  ```

- [ ] **Step 2: Add TTFlows boundary contract**

  Document:

  ```markdown
  - TTFlows owns users, API keys, business billing, audit, public error normalization, and production orchestration.
  - ccs-web slim owns upstream provider routing, failover/circuit breaker, upstream request forwarding, and provider cost observability.
  - TTFlows must integrate through OpenAI/Anthropic-compatible proxy routes and must not depend on ccs-web internal management APIs.
  - Production traffic requires TTFlows-side health gating, normalized public errors, and audit/billing consistency checks.
  ```

- [ ] **Step 3: Run docs privacy check**

  Run:

  ```powershell
  git diff -- docs/ccs-web-slim-capability-matrix.md docs/ccs-web-slim-ttflows-contract.md
  ```

  Expected: no private hostnames, IPs, local paths, tokens, or runtime evidence.

### Task 6: Verification And Expert Review Rounds

**Files:**
- No required source files unless reviews find issues.

- [ ] **Step 1: Run targeted checks**

  Run:

  ```powershell
  cargo test --manifest-path crates/server/Cargo.toml --test slim_profile
  cargo test --manifest-path crates/server/Cargo.toml --test slim_routes
  cargo test --manifest-path crates/server/Cargo.toml --test slim_ws
  cargo test --manifest-path crates/server/Cargo.toml
  pnpm vitest run tests/lib/capabilities.test.ts
  pnpm vitest run tests/integration/App.slim-profile.test.tsx tests/components/SettingsPage.slim-profile.test.tsx
  pnpm typecheck
  powershell -NoProfile -File .\scripts\test-publish-local-wsl-ccs-web-profile.ps1
  git diff --check
  ```

- [ ] **Step 2: Run proxy regression checks**

  First identify the exact existing tests:

  ```powershell
  rg -n "429|Responses|stickiness|failover|circuit" src-tauri crates tests
  ```

  Then execute the matching Rust tests for:

  - same-provider/key 429 retry before failover
  - Responses session stickiness
  - failover queue behavior
  - circuit breaker config/state behavior

  If a required regression has no existing test, add a focused regression test before claiming completion. Do not change proxy behavior to make slim tests pass.

- [ ] **Step 3: Expert review round 1**

  Dispatch independent reviews:

  - Product: verify retained/cut scope and TTFlows boundary.
  - Project: verify sequencing, rollback/publish boundary, and remaining risks.
  - Security/review: verify auth fail-closed, auth-vault disabled, unknown fail-closed, no sensitive docs.
  - Test: verify tests prove the acceptance criteria and identify gaps.
  - Ops: verify publish script changes do not publish and profile plumbing is operationally safe.

- [ ] **Step 4: Fix blockers**

  Fix every critical/important finding. Do not proceed on unresolved blocker findings.

- [ ] **Step 5: Expert review round 2**

  Re-run reviews focused on changed areas and blockers from round 1.

- [ ] **Step 6: Additional review rounds**

  Because this is a major feature, continue to at least 8 total review/verification rounds before making any completion claim. Rounds may include automated tests, spec compliance review, code review, security review, frontend review, ops review, and final diff/privacy review.

- [ ] **Step 7: Confirm no release was executed**

  Verify:

  ```powershell
  git status --short
  git log --oneline -5
  git ls-files --others --exclude-standard scripts
  ```

  Report that no publish/deploy command was run and no parallel publish/deploy/release script exists.

- [ ] **Step 8: Run mechanical privacy scan**

  Run a tracked-doc scan based on `git ls-files`, covering Windows absolute paths, IP addresses, token/secret/API-key literals, container IDs, and runtime evidence terms:

  ```powershell
  $trackedDocs = git ls-files | Where-Object { $_ -match '(^docs/|^examples/|README|CHANGELOG|SECURITY|SUPPORT|CONTRIBUTING).*\.(md|mdx|txt)$' }
  if ($trackedDocs) {
    Select-String -Path $trackedDocs -Pattern '[A-Za-z]:\\|\b\d{1,3}(\.\d{1,3}){3}\b|token\s*=|secret\s*=|api[_-]?key\s*=|container[_ -]?id\s*[:=]|image digest\s*[:=]' -Encoding UTF8
  }
  ```

  Expected: no private values. Mentions of forbidden categories as policy text are allowed only when they do not include actual values.

---

## Completion Criteria

- `slim` is explicit opt-in and `full` remains default.
- Capability matrix exists and covers command, HTTP route, WS command, frontend view, settings section, toolbar action, Rust module/future feature group, and tests.
- Disabled slim capabilities are hidden in frontend and rejected by backend RPC/HTTP/WS gates.
- Auth-vault returns fixed `403 capability_disabled` in slim.
- Slim production auth fails closed unless explicit local non-production no-auth override is set.
- Usage/pricing/request logs, providers, proxy, failover/circuit breaker, import/export, backup, WebDAV/S3 sync remain retained.
- Build-info exposes sanitized profile/capability metadata.
- Docker/publish script support `full|slim` profile without executing release.
- This plan's completion is a no-release implementation milestone only; it does not claim production publish readiness, slim Docker runtime smoke completion, or TTFlows production traffic readiness.
- Tests and expert review rounds are recorded in the final report.
- No private local/production evidence is committed.
