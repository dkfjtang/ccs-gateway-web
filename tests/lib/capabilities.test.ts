import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  isCapabilityGroupEnabled,
  coerceViewForProfile,
  coerceAppForProfile,
  isAppEnabled,
  isCommandEnabled,
  isDeepLinkResourceEnabled,
  isViewEnabled,
  normalizeProfile,
  profileMatchesBuildInfo,
  type CapabilityManifest,
  type CapabilityGroup,
} from "@/lib/capabilities";

const ALL_CAPABILITY_GROUPS: CapabilityGroup[] = [
  "auth",
  "providers",
  "proxy",
  "failover",
  "usage",
  "backup",
  "import-export",
  "sync",
  "settings-basic",
  "protocol",
  "desktop-helpers",
  "skills",
  "mcp",
  "sessions",
  "workspace",
  "daily-memory",
  "third-party-local-tools",
  "local-env-helpers",
  "auth-vault",
];

const RUST_CAPABILITY_GROUPS: Record<string, CapabilityGroup> = {
  Auth: "auth",
  Providers: "providers",
  Proxy: "proxy",
  Failover: "failover",
  Usage: "usage",
  Backup: "backup",
  ImportExport: "import-export",
  Sync: "sync",
  SettingsBasic: "settings-basic",
  Protocol: "protocol",
  DesktopHelpers: "desktop-helpers",
  Skills: "skills",
  Mcp: "mcp",
  Sessions: "sessions",
  Workspace: "workspace",
  DailyMemory: "daily-memory",
  ThirdPartyLocalTools: "third-party-local-tools",
  LocalEnvHelpers: "local-env-helpers",
  AuthVault: "auth-vault",
};

function rustSlimDisabledGroups(): CapabilityGroup[] {
  const source = readFileSync(
    resolve(process.cwd(), "crates/server/src/profile.rs"),
    "utf8",
  );
  const match = source.match(
    /pub const DISABLED_IN_SLIM_GROUPS:[\s\S]*?&\[(?<body>[\s\S]*?)\];/,
  );
  if (!match?.groups?.body) {
    throw new Error("Unable to find DISABLED_IN_SLIM_GROUPS in profile.rs");
  }

  return Array.from(
    match.groups.body.matchAll(/CapabilityGroup::([A-Za-z]+)/g),
    ([, name]) => {
      const group = RUST_CAPABILITY_GROUPS[name];
      if (!group) {
        throw new Error(`Unknown Rust capability group in test map: ${name}`);
      }
      return group;
    },
  ).sort();
}

describe("capabilities", () => {
  it("validates explicit profile values and defaults omitted profile to full", () => {
    expect(normalizeProfile("full")).toBe("full");
    expect(normalizeProfile("slim")).toBe("slim");
    expect(normalizeProfile(undefined)).toBe("full");
    expect(normalizeProfile("")).toBe("full");
    expect(() => normalizeProfile("unexpected")).toThrow(
      "Invalid CCS web profile",
    );
  });

  it("keeps retained A+B views enabled in slim and disables local workflow views", () => {
    expect(isViewEnabled("providers", "slim")).toBe(true);
    expect(isViewEnabled("settings", "slim")).toBe(true);
    expect(isViewEnabled("universal", "slim")).toBe(true);

    for (const view of [
      "prompts",
      "skills",
      "skillsDiscovery",
      "mcp",
      "agents",
      "sessions",
      "workspace",
      "openclawEnv",
      "openclawTools",
      "openclawAgents",
      "hermesMemory",
    ] as const) {
      expect(isViewEnabled(view, "slim")).toBe(false);
      expect(coerceViewForProfile(view, "slim")).toBe("providers");
      expect(isViewEnabled(view, "full")).toBe(true);
    }
  });

  it("hides third-party local tool apps in slim", () => {
    for (const app of ["claude-desktop", "opencode", "openclaw", "hermes"] as const) {
      expect(isAppEnabled(app, "slim")).toBe(false);
      expect(coerceAppForProfile(app, "slim")).toBe("claude");
      expect(isAppEnabled(app, "full")).toBe(true);
    }

    for (const app of ["claude", "codex", "gemini"] as const) {
      expect(isAppEnabled(app, "slim")).toBe(true);
      expect(coerceAppForProfile(app, "slim")).toBe(app);
    }
  });

  it("blocks disabled side-effect commands in slim", () => {
    for (const command of [
      "set_window_theme",
      "open_provider_terminal",
      "open_external",
      "update_tray_menu",
      "save_file_dialog",
      "open_file_dialog",
      "remove_provider_from_live_config",
      "get_openclaw_live_provider_ids",
      "get_hermes_model_config",
      "auth_start_login",
      "auth_list_accounts",
      "copilot_get_token",
      "copilot_get_token_for_account",
      "check_env_conflicts",
      "pick_directory",
      "get_tool_versions",
      "get_skills_migration_result",
      "get_installed_skills",
    ]) {
      expect(isCommandEnabled(command, "slim")).toBe(false);
      expect(isCommandEnabled(command, "full")).toBe(true);
    }

    expect(isCommandEnabled("get_providers", "slim")).toBe(true);
    expect(isCommandEnabled("get_coding_plan_quota", "slim")).toBe(true);
    expect(isCommandEnabled("get_balance", "slim")).toBe(true);
    expect(isCommandEnabled("get_model_pricing", "slim")).toBe(true);
    expect(isCommandEnabled("copilot_get_usage", "slim")).toBe(true);
    expect(isCommandEnabled("copilot_get_usage_for_account", "slim")).toBe(
      true,
    );
    expect(isCommandEnabled("get_subscription_quota", "slim")).toBe(true);
    expect(isCommandEnabled("get_codex_oauth_quota", "slim")).toBe(true);
  });

  it("keeps frontend and backend slim disabled groups aligned", () => {
    const frontendDisabled = ALL_CAPABILITY_GROUPS.filter(
      (group) => !isCapabilityGroupEnabled(group, "slim"),
    ).sort();

    expect(frontendDisabled).toEqual(rustSlimDisabledGroups());
  });

  it("keeps provider deeplinks and blocks prompt mcp skill deeplinks in slim", () => {
    expect(isDeepLinkResourceEnabled("provider", "slim")).toBe(true);
    expect(isDeepLinkResourceEnabled("prompt", "slim")).toBe(false);
    expect(isDeepLinkResourceEnabled("mcp", "slim")).toBe(false);
    expect(isDeepLinkResourceEnabled("skill", "slim")).toBe(false);
  });

  it("honors server capability manifest when provided", () => {
    const manifest: CapabilityManifest = {
      profile: "slim",
      enabled_groups: ["protocol", "providers"],
      disabled_groups: ["skills", "third-party-local-tools"],
    } as CapabilityManifest;

    expect(isViewEnabled("skills", "slim", manifest)).toBe(false);
    expect(isViewEnabled("prompts", "slim", manifest)).toBe(false);
    expect(isViewEnabled("providers", "slim", manifest)).toBe(true);
  });

  it("detects frontend backend profile drift", () => {
    expect(profileMatchesBuildInfo("slim", "slim")).toBe(true);
    expect(profileMatchesBuildInfo("full", "slim")).toBe(false);
    expect(profileMatchesBuildInfo("slim", undefined)).toBe(true);
  });
});
