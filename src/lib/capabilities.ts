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

export interface CapabilityManifest {
  profile: CcsWebProfile;
  enabled_groups: CapabilityGroup[];
  disabled_groups: CapabilityGroup[];
}

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

export type SlimAwareApp =
  | "claude"
  | "claude-desktop"
  | "codex"
  | "gemini"
  | "opencode"
  | "openclaw"
  | "hermes";

const FULL_PROFILE: CcsWebProfile = "full";
const SLIM_PROFILE: CcsWebProfile = "slim";

const DISABLED_SLIM_GROUPS = new Set<CapabilityGroup>([
  "desktop-helpers",
  "skills",
  "mcp",
  "sessions",
  "workspace",
  "daily-memory",
  "third-party-local-tools",
  "local-env-helpers",
  "auth-vault",
]);

const VIEW_GROUPS: Partial<Record<SlimAwareView, CapabilityGroup>> = {
  prompts: "third-party-local-tools",
  skills: "skills",
  skillsDiscovery: "skills",
  mcp: "mcp",
  agents: "third-party-local-tools",
  sessions: "sessions",
  workspace: "workspace",
  openclawEnv: "third-party-local-tools",
  openclawTools: "third-party-local-tools",
  openclawAgents: "third-party-local-tools",
  hermesMemory: "third-party-local-tools",
};

const APP_GROUPS: Partial<Record<SlimAwareApp, CapabilityGroup>> = {
  "claude-desktop": "third-party-local-tools",
  opencode: "third-party-local-tools",
  openclaw: "third-party-local-tools",
  hermes: "third-party-local-tools",
};

const COMMAND_GROUPS: Record<string, CapabilityGroup> = {
  update_tray_menu: "desktop-helpers",
  restart_app: "desktop-helpers",
  check_for_updates: "desktop-helpers",
  open_config_folder: "desktop-helpers",
  open_app_config_folder: "desktop-helpers",
  open_external: "desktop-helpers",
  set_auto_launch: "desktop-helpers",
  get_auto_launch_status: "desktop-helpers",
  set_window_theme: "desktop-helpers",
  open_provider_terminal: "desktop-helpers",
  save_file_dialog: "desktop-helpers",
  open_file_dialog: "desktop-helpers",
  open_zip_file_dialog: "desktop-helpers",
  read_live_provider_settings: "third-party-local-tools",
  sync_current_providers_live: "third-party-local-tools",
  remove_provider_from_live_config: "third-party-local-tools",
  import_claude_desktop_providers_from_claude: "third-party-local-tools",
  get_claude_desktop_status: "third-party-local-tools",
  get_claude_desktop_default_routes: "third-party-local-tools",
  apply_claude_plugin_config: "third-party-local-tools",
  get_claude_plugin_status: "third-party-local-tools",
  read_claude_plugin_config: "third-party-local-tools",
  is_claude_plugin_applied: "third-party-local-tools",
  apply_claude_onboarding_skip: "third-party-local-tools",
  clear_claude_onboarding_skip: "third-party-local-tools",
  get_hermes_model_config: "third-party-local-tools",
  get_hermes_memory: "third-party-local-tools",
  set_hermes_memory: "third-party-local-tools",
  get_hermes_memory_limits: "third-party-local-tools",
  set_hermes_memory_enabled: "third-party-local-tools",
  open_hermes_web_ui: "third-party-local-tools",
  launch_hermes_dashboard: "third-party-local-tools",
  import_hermes_providers_from_live: "third-party-local-tools",
  get_hermes_live_provider_ids: "third-party-local-tools",
  scan_openclaw_config_health: "third-party-local-tools",
  get_openclaw_default_model: "third-party-local-tools",
  set_openclaw_default_model: "third-party-local-tools",
  get_openclaw_model_catalog: "third-party-local-tools",
  set_openclaw_model_catalog: "third-party-local-tools",
  get_openclaw_agents_defaults: "third-party-local-tools",
  set_openclaw_agents_defaults: "third-party-local-tools",
  get_openclaw_env: "third-party-local-tools",
  set_openclaw_env: "third-party-local-tools",
  get_openclaw_tools: "third-party-local-tools",
  set_openclaw_tools: "third-party-local-tools",
  import_openclaw_providers_from_live: "third-party-local-tools",
  get_openclaw_live_provider_ids: "third-party-local-tools",
  get_openclaw_live_provider: "third-party-local-tools",
  read_omo_local_file: "third-party-local-tools",
  get_current_omo_provider_id: "third-party-local-tools",
  disable_current_omo: "third-party-local-tools",
  read_omo_slim_local_file: "third-party-local-tools",
  get_current_omo_slim_provider_id: "third-party-local-tools",
  disable_current_omo_slim: "third-party-local-tools",
  import_opencode_providers_from_live: "third-party-local-tools",
  get_opencode_live_provider_ids: "third-party-local-tools",
  auth_start_login: "third-party-local-tools",
  auth_poll_for_account: "third-party-local-tools",
  auth_list_accounts: "third-party-local-tools",
  auth_get_status: "third-party-local-tools",
  auth_remove_account: "third-party-local-tools",
  auth_set_default_account: "third-party-local-tools",
  auth_logout: "third-party-local-tools",
  copilot_start_device_flow: "third-party-local-tools",
  copilot_poll_for_auth: "third-party-local-tools",
  copilot_poll_for_account: "third-party-local-tools",
  copilot_list_accounts: "third-party-local-tools",
  copilot_remove_account: "third-party-local-tools",
  copilot_set_default_account: "third-party-local-tools",
  copilot_get_auth_status: "third-party-local-tools",
  copilot_logout: "third-party-local-tools",
  copilot_is_authenticated: "third-party-local-tools",
  copilot_get_token: "third-party-local-tools",
  copilot_get_token_for_account: "third-party-local-tools",
  copilot_get_models: "third-party-local-tools",
  copilot_get_models_for_account: "third-party-local-tools",
  copilot_get_usage: "usage",
  copilot_get_usage_for_account: "usage",
  get_subscription_quota: "usage",
  get_codex_oauth_quota: "usage",
  get_prompts: "third-party-local-tools",
  upsert_prompt: "third-party-local-tools",
  delete_prompt: "third-party-local-tools",
  enable_prompt: "third-party-local-tools",
  import_prompt_from_file: "third-party-local-tools",
  get_current_prompt_file_content: "third-party-local-tools",
  create_caveman_style_profile: "third-party-local-tools",
  get_claude_common_config_snippet: "third-party-local-tools",
  set_claude_common_config_snippet: "third-party-local-tools",
  get_common_config_snippet: "third-party-local-tools",
  set_common_config_snippet: "third-party-local-tools",
  pick_directory: "local-env-helpers",
  check_env_conflicts: "local-env-helpers",
  delete_env_vars: "local-env-helpers",
  restore_env_backup: "local-env-helpers",
  get_tool_versions: "local-env-helpers",
  get_skills_migration_result: "skills",
  get_installed_skills: "skills",
  import_from_deeplink_unified: "import-export",
  merge_deeplink_config: "import-export",
};

const RESOURCE_GROUPS: Record<string, CapabilityGroup> = {
  provider: "providers",
  prompt: "third-party-local-tools",
  mcp: "mcp",
  skill: "skills",
};

export function normalizeProfile(value: unknown): CcsWebProfile {
  if (value === undefined || value === null || value === "") {
    return FULL_PROFILE;
  }
  if (typeof value !== "string") {
    throw new Error(`Invalid CCS web profile: ${String(value)}`);
  }
  if (value === FULL_PROFILE) {
    return FULL_PROFILE;
  }
  if (value === SLIM_PROFILE) {
    return SLIM_PROFILE;
  }
  throw new Error(`Invalid CCS web profile: ${value}`);
}

export function getBakedProfile(): CcsWebProfile {
  return normalizeProfile(import.meta.env.VITE_CCS_WEB_PROFILE);
}

export function isSlimProfile(profile: CcsWebProfile = getBakedProfile()) {
  return profile === SLIM_PROFILE;
}

export function isCapabilityGroupEnabled(
  group: CapabilityGroup,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): boolean {
  if (manifest) {
    return !manifest.disabled_groups.includes(group);
  }
  return profile === FULL_PROFILE || !DISABLED_SLIM_GROUPS.has(group);
}

export function isViewEnabled(
  view: SlimAwareView,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): boolean {
  const group = VIEW_GROUPS[view];
  return group ? isCapabilityGroupEnabled(group, profile, manifest) : true;
}

export function isAppEnabled(
  app: SlimAwareApp,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): boolean {
  const group = APP_GROUPS[app];
  return group ? isCapabilityGroupEnabled(group, profile, manifest) : true;
}

export function coerceAppForProfile(
  app: SlimAwareApp,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): SlimAwareApp {
  return isAppEnabled(app, profile, manifest) ? app : "claude";
}

export function coerceViewForProfile(
  view: SlimAwareView,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): SlimAwareView {
  return isViewEnabled(view, profile, manifest) ? view : "providers";
}

export function isCommandEnabled(
  command: string,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): boolean {
  const group = COMMAND_GROUPS[command];
  return group ? isCapabilityGroupEnabled(group, profile, manifest) : true;
}

export function isDeepLinkResourceEnabled(
  resource: string | undefined,
  profile: CcsWebProfile = getBakedProfile(),
  manifest?: CapabilityManifest | null,
): boolean {
  const group = resource ? RESOURCE_GROUPS[resource] : undefined;
  return group ? isCapabilityGroupEnabled(group, profile, manifest) : false;
}

export function profileMatchesBuildInfo(
  bakedProfile: CcsWebProfile,
  serverProfile?: CcsWebProfile,
): boolean {
  return !serverProfile || bakedProfile === serverProfile;
}
