import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { invoke, listen } from "@/lib/transport";
import {
  Plus,
  Settings,
  ArrowLeft,
  Book,
  Brain,
  Wrench,
  RefreshCw,
  History,
  BarChart2,
  Download,
  FolderArchive,
  Search,
  FolderOpen,
  KeyRound,
  Shield,
  Cpu,
  LayoutDashboard,
} from "lucide-react";
import type { OpenClawHealthWarning, Provider, VisibleApps } from "@/types";
import type { EnvConflict } from "@/types/env";
import { useProvidersQuery, useSettingsQuery } from "@/lib/query";
import type { AppId } from "@/lib/api/types";
import {
  providersApi,
  type ProviderSwitchEvent,
} from "@/lib/api/providers";
import { settingsApi } from "@/lib/api/settings";
import { usageApi } from "@/lib/api/usage";
import { checkAllEnvConflicts, checkEnvConflicts } from "@/lib/api/env";
import { useProviderActions } from "@/hooks/useProviderActions";
import { useProxyStatus } from "@/hooks/useProxyStatus";
import { useAutoCompact } from "@/hooks/useAutoCompact";
import { useUsageCacheBridge } from "@/hooks/useUsageCacheBridge";
import { useLastValidValue } from "@/hooks/useLastValidValue";
import { extractErrorMessage } from "@/utils/errorUtils";
import { isTextEditableTarget } from "@/utils/domUtils";
import { cn } from "@/lib/utils";
import { usageKeys } from "@/lib/query/usage";
import { hermesKeys, openclawKeys } from "@/lib/query/localToolKeys";
import { startBuildUpdateMonitor } from "@/lib/buildInfo";
import {
  coerceAppForProfile,
  coerceViewForProfile,
  getBakedProfile,
  isCapabilityGroupEnabled,
  isAppEnabled,
  isCommandEnabled,
} from "@/lib/capabilities";
import { AppSwitcher } from "@/components/AppSwitcher";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { UpdateBadge } from "@/components/UpdateBadge";
import { EnvWarningBanner } from "@/components/env/EnvWarningBanner";
import { ProxyToggle } from "@/components/proxy/ProxyToggle";
import { ClaudeDesktopRouteToggle } from "@/components/proxy/ClaudeDesktopRouteToggle";
import { FailoverToggle } from "@/components/proxy/FailoverToggle";
import { DeepLinkImportDialog } from "@/components/DeepLinkImportDialog";
import { LoginPage } from "@/components/LoginPage";
import { useAuth } from "@/contexts/AuthContext";
import { FirstRunNoticeDialog } from "@/components/FirstRunNoticeDialog";
import { McpIcon } from "@/components/BrandIcons";
import { Button } from "@/components/ui/button";
import {
  useDisableCurrentOmo,
  useDisableCurrentOmoSlim,
} from "@/lib/query/omo";

type View =
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

interface SyncStatusUpdatedPayload {
  source?: string;
  status?: string;
  error?: string;
}

const AddProviderDialog = lazy(async () => ({
  default: (await import("@/components/providers/AddProviderDialog"))
    .AddProviderDialog,
}));
const ProviderList = lazy(async () => ({
  default: (await import("@/components/providers/ProviderList")).ProviderList,
}));
const EditProviderDialog = lazy(async () => ({
  default: (await import("@/components/providers/EditProviderDialog"))
    .EditProviderDialog,
}));
const SettingsPage = lazy(async () => ({
  default: (await import("@/components/settings/SettingsPage")).SettingsPage,
}));
const PromptPanel = lazy(() => import("@/components/prompts/PromptPanel"));
const UnifiedMcpPanel = lazy(() => import("@/components/mcp/UnifiedMcpPanel"));
const SkillsPage = lazy(async () => ({
  default: (await import("@/components/skills/SkillsPage")).SkillsPage,
}));
const UnifiedSkillsPanel = lazy(
  () => import("@/components/skills/UnifiedSkillsPanel"),
);
const AgentsPanel = lazy(async () => ({
  default: (await import("@/components/agents/AgentsPanel")).AgentsPanel,
}));
const UniversalProviderPanel = lazy(async () => ({
  default: (await import("@/components/universal/UniversalProviderPanel"))
    .UniversalProviderPanel,
}));
const SessionManagerPage = lazy(async () => ({
  default: (await import("@/components/sessions/SessionManagerPage"))
    .SessionManagerPage,
}));
const WorkspaceFilesPanel = lazy(
  () => import("@/components/workspace/WorkspaceFilesPanel"),
);
const EnvPanel = lazy(() => import("@/components/openclaw/EnvPanel"));
const ToolsPanel = lazy(() => import("@/components/openclaw/ToolsPanel"));
const AgentsDefaultsPanel = lazy(
  () => import("@/components/openclaw/AgentsDefaultsPanel"),
);
const UsageScriptModal = lazy(() => import("@/components/UsageScriptModal"));
const HermesMemoryPanel = lazy(
  () => import("@/components/hermes/HermesMemoryPanel"),
);
const OpenClawHealthBanner = lazy(
  () => import("@/components/openclaw/OpenClawHealthBanner"),
);

const DEFAULT_DRAG_BAR_HEIGHT = 0;
const HEADER_HEIGHT = 64; // px

const STORAGE_KEY = "cc-switch-last-app";
const VALID_APPS: AppId[] = [
  "claude",
  "claude-desktop",
  "codex",
  "gemini",
  "opencode",
  "openclaw",
  "hermes",
];

const getInitialApp = (): AppId => {
  const saved = localStorage.getItem(STORAGE_KEY) as AppId | null;
  if (saved && VALID_APPS.includes(saved)) {
    return coerceAppForProfile(saved) as AppId;
  }
  return "claude";
};

const VIEW_STORAGE_KEY = "cc-switch-last-view";
const VALID_VIEWS: View[] = [
  "providers",
  "settings",
  "prompts",
  "skills",
  "skillsDiscovery",
  "mcp",
  "agents",
  "universal",
  "sessions",
  "workspace",
  "openclawEnv",
  "openclawTools",
  "openclawAgents",
  "hermesMemory",
];

const getInitialView = (): View => {
  const saved = localStorage.getItem(VIEW_STORAGE_KEY) as View | null;
  if (saved && VALID_VIEWS.includes(saved)) {
    return coerceViewForProfile(saved);
  }
  return "providers";
};

const lazyContentFallback = (
  <div className="flex min-h-[240px] items-center justify-center text-sm text-muted-foreground">
    Loading...
  </div>
);

function App() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const { isLoading: authLoading, isAuthenticated, authEnabled } = useAuth();
  const profile = getBakedProfile();
  const desktopHelpersEnabled = isCapabilityGroupEnabled(
    "desktop-helpers",
    profile,
  );
  const skillsEnabled = isCapabilityGroupEnabled("skills", profile);
  const mcpEnabled = isCapabilityGroupEnabled("mcp", profile);
  const sessionsEnabled = isCapabilityGroupEnabled("sessions", profile);
  const localEnvHelpersEnabled = isCapabilityGroupEnabled(
    "local-env-helpers",
    profile,
  );
  const thirdPartyLocalToolsEnabled = isCapabilityGroupEnabled(
    "third-party-local-tools",
    profile,
  );
  const usageCapabilitiesEnabled = isCapabilityGroupEnabled("usage", profile);

  const [activeApp, setActiveApp] = useState<AppId>(getInitialApp);
  const [currentView, setCurrentView] = useState<View>(getInitialView);
  const [settingsDefaultTab, setSettingsDefaultTab] = useState("general");
  const [isAddOpen, setIsAddOpen] = useState(false);
  const setProfiledActiveApp = useCallback(
    (app: AppId) => {
      setActiveApp(coerceAppForProfile(app, profile) as AppId);
    },
    [profile],
  );

  useEffect(() => {
    const coercedView = coerceViewForProfile(currentView, profile);
    if (coercedView !== currentView) {
      setCurrentView(coercedView);
      return;
    }
    localStorage.setItem(VIEW_STORAGE_KEY, coercedView);
  }, [currentView, profile]);

  const { data: settingsData } = useSettingsQuery();
  const dragBarHeight = DEFAULT_DRAG_BAR_HEIGHT;
  const contentTopOffset = dragBarHeight + HEADER_HEIGHT;
  const configuredVisibleApps: VisibleApps = settingsData?.visibleApps ?? {
    claude: true,
    "claude-desktop": true,
    codex: true,
    gemini: true,
    opencode: true,
    openclaw: true,
    hermes: true,
  };
  const visibleApps: VisibleApps = useMemo(
    () => ({
      claude: configuredVisibleApps.claude && isAppEnabled("claude", profile),
      "claude-desktop":
        configuredVisibleApps["claude-desktop"] &&
        isAppEnabled("claude-desktop", profile),
      codex: configuredVisibleApps.codex && isAppEnabled("codex", profile),
      gemini: configuredVisibleApps.gemini && isAppEnabled("gemini", profile),
      opencode:
        configuredVisibleApps.opencode && isAppEnabled("opencode", profile),
      openclaw:
        configuredVisibleApps.openclaw && isAppEnabled("openclaw", profile),
      hermes: configuredVisibleApps.hermes && isAppEnabled("hermes", profile),
    }),
    [configuredVisibleApps, profile],
  );

  const getFirstVisibleApp = useCallback((): AppId => {
    if (visibleApps.claude) return "claude";
    if (visibleApps["claude-desktop"]) return "claude-desktop";
    if (visibleApps.codex) return "codex";
    if (visibleApps.gemini) return "gemini";
    if (visibleApps.opencode) return "opencode";
    if (visibleApps.openclaw) return "openclaw";
    if (visibleApps.hermes) return "hermes";
    return "claude"; // fallback
  }, [visibleApps]);

  useEffect(() => {
    if (!visibleApps[activeApp]) {
      setProfiledActiveApp(getFirstVisibleApp());
    }
  }, [visibleApps, activeApp, setProfiledActiveApp, getFirstVisibleApp]);

  // Fallback from sessions view when switching to an app without session support
  useEffect(() => {
    if (
      currentView === "sessions" &&
      activeApp !== "claude" &&
      activeApp !== "codex" &&
      activeApp !== "opencode" &&
      activeApp !== "openclaw" &&
      activeApp !== "gemini" &&
      activeApp !== "hermes"
    ) {
      setCurrentView("providers");
    }
  }, [activeApp, currentView]);

  const [editingProvider, setEditingProvider] = useState<Provider | null>(null);
  const [usageProvider, setUsageProvider] = useState<Provider | null>(null);
  const [confirmAction, setConfirmAction] = useState<{
    provider: Provider;
    action: "remove" | "delete";
  } | null>(null);
  const [envConflicts, setEnvConflicts] = useState<EnvConflict[]>([]);
  const [showEnvBanner, setShowEnvBanner] = useState(false);
  const [profileMismatchMessage, setProfileMismatchMessage] = useState<
    string | null
  >(null);

  const effectiveEditingProvider = useLastValidValue(editingProvider);
  const effectiveUsageProvider = useLastValidValue(usageProvider);

  const toolbarRef = useRef<HTMLDivElement>(null);
  const isToolbarCompact = useAutoCompact(toolbarRef);

  useUsageCacheBridge();

  useEffect(() => {
    return startBuildUpdateMonitor({
      onUpdateAvailable: () => {
        toast.info(
          t("buildUpdate.available", {
            defaultValue: "检测到本机服务已更新，刷新页面后生效。",
          }),
          {
            closeButton: true,
            duration: Infinity,
            action: {
              label: t("buildUpdate.reload", { defaultValue: "刷新" }),
              onClick: () => window.location.reload(),
            },
          },
        );
      },
      onProfileMismatch: setProfileMismatchMessage,
    });
  }, [t]);

  const promptPanelRef = useRef<any>(null);
  const mcpPanelRef = useRef<any>(null);
  const skillsPageRef = useRef<any>(null);
  const unifiedSkillsPanelRef = useRef<any>(null);
  const addActionButtonClass =
    "bg-orange-500 hover:bg-orange-600 dark:bg-orange-500 dark:hover:bg-orange-600 text-white shadow-lg shadow-orange-500/30 dark:shadow-orange-500/40 rounded-full w-8 h-8";

  const {
    isRunning: isProxyRunning,
    takeoverStatus,
    status: proxyStatus,
  } = useProxyStatus();
  const isCurrentAppTakeoverActive = takeoverStatus?.[activeApp] || false;
  const activeProviderId = useMemo(() => {
    const target = proxyStatus?.active_targets?.find(
      (t) => t.app_type === activeApp,
    );
    return target?.provider_id;
  }, [proxyStatus?.active_targets, activeApp]);

  const { data, isLoading, refetch } = useProvidersQuery(activeApp, {
    isProxyRunning,
  });
  const providers = useMemo(() => data?.providers ?? {}, [data]);
  const currentProviderId = data?.currentProviderId ?? "";
  const isOpenClawView =
    thirdPartyLocalToolsEnabled &&
    activeApp === "openclaw" &&
    (currentView === "providers" ||
      currentView === "workspace" ||
      currentView === "sessions" ||
      currentView === "openclawEnv" ||
      currentView === "openclawTools" ||
      currentView === "openclawAgents");
  const { data: openclawHealthWarnings = [] } = useQuery<
    OpenClawHealthWarning[]
  >({
    queryKey: openclawKeys.health,
    queryFn: async () => {
      const { openclawApi } = await import("@/lib/api/openclaw");
      return openclawApi.scanHealth();
    },
    staleTime: 30_000,
    enabled: isOpenClawView,
  });
  const hasSkillsSupport = skillsEnabled && activeApp !== "claude-desktop";
  const hasSessionSupport =
    sessionsEnabled &&
    (activeApp === "claude" ||
      activeApp === "codex" ||
      activeApp === "opencode" ||
      activeApp === "openclaw" ||
      activeApp === "gemini" ||
      activeApp === "hermes");
  const promptsEnabled = thirdPartyLocalToolsEnabled;
  const workspaceEnabled = isCapabilityGroupEnabled("workspace", profile);

  const {
    addProvider,
    updateProvider,
    switchProvider,
    deleteProvider,
    saveUsageScript,
    setAsDefaultModel,
  } = useProviderActions(
    activeApp,
    isProxyRunning,
    isProxyRunning && isCurrentAppTakeoverActive,
    { desktopHelpersEnabled, thirdPartyLocalToolsEnabled },
  );

  const disableOmoMutation = useDisableCurrentOmo();
  const handleDisableOmo = () => {
    if (!thirdPartyLocalToolsEnabled) {
      return;
    }
    disableOmoMutation.mutate(undefined, {
      onSuccess: () => {
        toast.success(t("omo.disabled", { defaultValue: "OMO 已停用" }));
      },
      onError: (error: Error) => {
        toast.error(
          t("omo.disableFailed", {
            defaultValue: "停用 OMO 失败: {{error}}",
            error: extractErrorMessage(error),
          }),
        );
      },
    });
  };

  const disableOmoSlimMutation = useDisableCurrentOmoSlim();
  const handleDisableOmoSlim = () => {
    if (!thirdPartyLocalToolsEnabled) {
      return;
    }
    disableOmoSlimMutation.mutate(undefined, {
      onSuccess: () => {
        toast.success(t("omo.disabled", { defaultValue: "OMO 已停用" }));
      },
      onError: (error: Error) => {
        toast.error(
          t("omo.disableFailed", {
            defaultValue: "停用 OMO 失败: {{error}}",
            error: extractErrorMessage(error),
          }),
        );
      },
    });
  };

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;

    const setupListener = async () => {
      try {
        unsubscribe = await providersApi.onSwitched(
          async (event: ProviderSwitchEvent) => {
            if (event.appType === activeApp) {
              await refetch();
            }
          },
        );
      } catch (error) {
        console.error("[App] Failed to subscribe provider switch event", error);
      }
    };

    setupListener();
    return () => {
      unsubscribe?.();
    };
  }, [activeApp, refetch]);

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;

    const setupListener = async () => {
      try {
        unsubscribe = await listen("universal-provider-synced", async () => {
          await queryClient.invalidateQueries({ queryKey: ["providers"] });
          if (!desktopHelpersEnabled) {
            return;
          }
          try {
            await providersApi.updateTrayMenu();
          } catch (error) {
            console.error("[App] Failed to update tray menu", error);
          }
        });
      } catch (error) {
        console.error(
          "[App] Failed to subscribe universal-provider-synced event",
          error,
        );
      }
    };

    setupListener();
    return () => {
      unsubscribe?.();
    };
  }, [desktopHelpersEnabled, queryClient]);

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;
    let active = true;

    const setupListener = async () => {
      try {
        const off = await listen<SyncStatusUpdatedPayload>(
          "webdav-sync-status-updated",
          async (payload) => {
            await queryClient.invalidateQueries({ queryKey: ["settings"] });

            if (payload.source !== "auto" || payload.status !== "error") {
              return;
            }

            toast.error(
              t("settings.webdavSync.autoSyncFailedToast", {
                error: payload.error || t("common.unknown"),
              }),
            );
          },
        );
        if (!active) {
          off();
          return;
        }
        unsubscribe = off;
      } catch (error) {
        console.error(
          "[App] Failed to subscribe webdav-sync-status-updated event",
          error,
        );
      }
    };

    void setupListener();
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [queryClient, t]);

  useEffect(() => {
    let unsubscribe: (() => void) | undefined;
    let active = true;

    const setupListener = async () => {
      try {
        const off = await listen<SyncStatusUpdatedPayload>(
          "s3-sync-status-updated",
          async (payload) => {
            await queryClient.invalidateQueries({ queryKey: ["settings"] });

            if (payload.source !== "auto" || payload.status !== "error") {
              return;
            }

            toast.error(
              t("settings.s3Sync.autoSyncFailedToast", {
                error: payload.error || t("common.unknown"),
              }),
            );
          },
        );
        if (!active) {
          off();
          return;
        }
        unsubscribe = off;
      } catch (error) {
        console.error(
          "[App] Failed to subscribe s3-sync-status-updated event",
          error,
        );
      }
    };

    void setupListener();
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [queryClient, t]);

  // Listen for proxy-official-warning: warn when takeover is enabled with an official provider
  useEffect(() => {
    let unsubscribe: (() => void) | undefined;

    const setup = async () => {
      unsubscribe = await listen(
        "proxy-official-warning",
        (payload: { appType: string; providerName: string }) => {
          const { providerName } = payload;
          toast.warning(
            t("notifications.proxyOfficialWarning", {
              name: providerName,
              defaultValue: `当前供应商 ${providerName} 是官方供应商，建议切换到第三方供应商后再使用代理接管`,
            }),
            { duration: 8000 },
          );
        },
      );
    };

    void setup();
    return () => {
      unsubscribe?.();
    };
  }, [t]);

  useEffect(() => {
    if (!localEnvHelpersEnabled) {
      return;
    }

    const checkEnvOnStartup = async () => {
      try {
        const allConflicts = await checkAllEnvConflicts();
        const flatConflicts = Object.values(allConflicts).flat();

        if (flatConflicts.length > 0) {
          setEnvConflicts(flatConflicts);
          const dismissed = sessionStorage.getItem("env_banner_dismissed");
          if (!dismissed) {
            setShowEnvBanner(true);
          }
        }
      } catch (error) {
        console.error(
          "[App] Failed to check environment conflicts on startup:",
          error,
        );
      }
    };

    checkEnvOnStartup();
  }, [localEnvHelpersEnabled]);

  useEffect(() => {
    const checkMigration = async () => {
      try {
        const migrated = await invoke<boolean>("get_migration_result");
        if (migrated) {
          toast.success(
            t("migration.success", { defaultValue: "配置迁移成功" }),
            { closeButton: true },
          );
        }
      } catch (error) {
        console.error("[App] Failed to check migration result:", error);
      }
    };

    checkMigration();
  }, [t]);

  useEffect(() => {
    if (!skillsEnabled) {
      return;
    }

    const checkSkillsMigration = async () => {
      try {
        const result = await invoke<{ count: number; error?: string } | null>(
          "get_skills_migration_result",
        );
        if (result?.error) {
          toast.error(t("migration.skillsFailed"), {
            description: t("migration.skillsFailedDescription"),
            closeButton: true,
          });
          console.error("[App] Skills SSOT migration failed:", result.error);
          return;
        }
        if (result && result.count > 0) {
          toast.success(t("migration.skillsSuccess", { count: result.count }), {
            closeButton: true,
          });
          await queryClient.invalidateQueries({ queryKey: ["skills"] });
        }
      } catch (error) {
        console.error("[App] Failed to check skills migration result:", error);
      }
    };

    checkSkillsMigration();
  }, [skillsEnabled, t, queryClient]);

  useEffect(() => {
    if (!localEnvHelpersEnabled) {
      return;
    }

    const checkEnvOnSwitch = async () => {
      try {
        const conflicts = await checkEnvConflicts(activeApp);

        if (conflicts.length > 0) {
          setEnvConflicts((prev) => {
            const existingKeys = new Set(
              prev.map((c) => `${c.varName}:${c.sourcePath}`),
            );
            const newConflicts = conflicts.filter(
              (c) => !existingKeys.has(`${c.varName}:${c.sourcePath}`),
            );
            return [...prev, ...newConflicts];
          });
          const dismissed = sessionStorage.getItem("env_banner_dismissed");
          if (!dismissed) {
            setShowEnvBanner(true);
          }
        }
      } catch (error) {
        console.error(
          "[App] Failed to check environment conflicts on app switch:",
          error,
        );
      }
    };

    checkEnvOnSwitch();
  }, [activeApp, localEnvHelpersEnabled]);

  const currentViewRef = useRef(currentView);

  useEffect(() => {
    currentViewRef.current = currentView;
  }, [currentView]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "," && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        setCurrentView("settings");
        return;
      }

      if (event.key !== "Escape" || event.defaultPrevented) return;

      if (document.body.style.overflow === "hidden") return;

      const view = currentViewRef.current;
      if (view === "providers") return;

      if (isTextEditableTarget(event.target)) return;

      event.preventDefault();
      setCurrentView(view === "skillsDiscovery" ? "skills" : "providers");
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, []);

  const [launchDashboardOpen, setLaunchDashboardOpen] = useState(false);
  const [isRefreshingAllUsage, setIsRefreshingAllUsage] = useState(false);
  const openHermesWebUI = useCallback(
    async (path?: string) => {
      if (!thirdPartyLocalToolsEnabled) {
        return;
      }
      try {
        const { hermesApi } = await import("@/lib/api/hermes");
        await hermesApi.openWebUI(path);
      } catch (error) {
        const detail = extractErrorMessage(error);
        if (detail === "hermes_web_offline") {
          setLaunchDashboardOpen(true);
          return;
        }
        toast.error(t("hermes.webui.openFailed"), {
          description: detail || undefined,
        });
      }
    },
    [t, thirdPartyLocalToolsEnabled],
  );

  const usageRefreshTargets = useMemo(
    () =>
      Object.values(providers).filter(
        (provider) => provider.meta?.usage_script?.enabled,
      ),
    [providers],
  );

  const shouldShowRefreshAllUsageButton =
    currentView === "providers" && usageRefreshTargets.length > 0;

  const handleRefreshAllUsage = async () => {
    if (usageRefreshTargets.length === 0 || isRefreshingAllUsage) {
      return;
    }

    setIsRefreshingAllUsage(true);
    try {
      const results = await Promise.allSettled(
        usageRefreshTargets.map(async (provider) => {
          const usage = await usageApi.query(provider.id, activeApp);
          queryClient.setQueryData(usageKeys.script(provider.id, activeApp), usage);
          return provider.name;
        }),
      );

      const successCount = results.filter(
        (result) => result.status === "fulfilled",
      ).length;
      const failedResults = results.filter(
        (result): result is PromiseRejectedResult => result.status === "rejected",
      );

      if (failedResults.length === 0) {
        toast.success(
          t("usage.refreshAllSuccess", {
            count: successCount,
            defaultValue: `已刷新 ${successCount} 个自定义计费`,
          }),
        );
        return;
      }

      const firstError = failedResults[0]?.reason;
      const errorMessage =
        firstError instanceof Error
          ? firstError.message
          : t("common.operationFailed");

      if (successCount > 0) {
        toast.warning(
          t("usage.refreshAllPartial", {
            success: successCount,
            failed: failedResults.length,
            error: errorMessage,
            defaultValue: `已刷新 ${successCount} 个自定义计费，${failedResults.length} 个失败：${errorMessage}`,
          }),
        );
        return;
      }

      toast.error(
        t("usage.refreshAllFailed", {
          failed: failedResults.length,
          error: errorMessage,
          defaultValue: `刷新 ${failedResults.length} 个自定义计费失败：${errorMessage}`,
        }),
      );
    } finally {
      setIsRefreshingAllUsage(false);
    }
  };

  const handleOpenWebsite = async (url: string) => {
    try {
      await settingsApi.openExternal(url);
    } catch (error) {
      const detail =
        extractErrorMessage(error) ||
        t("notifications.openLinkFailed", {
          defaultValue: "链接打开失败",
        });
      toast.error(detail);
    }
  };

  const handleEditProvider = async ({
    provider,
    originalId,
  }: {
    provider: Provider;
    originalId?: string;
  }) => {
    await updateProvider(provider, originalId);
    setEditingProvider(null);
  };

  const handleConfirmAction = async () => {
    if (!confirmAction) return;
    const { provider, action } = confirmAction;

    if (action === "remove") {
      if (!thirdPartyLocalToolsEnabled) {
        setConfirmAction(null);
        return;
      }
      // Remove from live config only (for additive mode apps like OpenCode/OpenClaw)
      // Does NOT delete from database - provider remains in the list
      await providersApi.removeFromLiveConfig(provider.id, activeApp);
      // Invalidate queries to refresh the isInConfig state
      if (activeApp === "opencode") {
        await queryClient.invalidateQueries({
          queryKey: ["opencodeLiveProviderIds"],
        });
      } else if (activeApp === "openclaw") {
        await queryClient.invalidateQueries({
          queryKey: openclawKeys.liveProviderIds,
        });
        await queryClient.invalidateQueries({
          queryKey: openclawKeys.health,
        });
      } else if (activeApp === "hermes") {
        await queryClient.invalidateQueries({
          queryKey: hermesKeys.liveProviderIds,
        });
      }
      toast.success(
        t("notifications.removeFromConfigSuccess", {
          defaultValue: "已从配置移除",
        }),
        { closeButton: true },
      );
    } else {
      await deleteProvider(provider.id);
    }
    setConfirmAction(null);
  };

  const generateUniqueProviderCopyKey = (
    originalKey: string,
    existingKeys: string[],
  ): string => {
    const baseKey = `${originalKey}-copy`;

    if (!existingKeys.includes(baseKey)) {
      return baseKey;
    }

    let counter = 2;
    while (existingKeys.includes(`${baseKey}-${counter}`)) {
      counter++;
    }
    return `${baseKey}-${counter}`;
  };

  const handleDuplicateProvider = async (provider: Provider) => {
    const newSortIndex =
      provider.sortIndex !== undefined ? provider.sortIndex + 1 : undefined;

    const duplicatedProvider: Omit<Provider, "id" | "createdAt"> & {
      providerKey?: string;
      addToLive?: boolean;
    } = {
      name: `${provider.name} copy`,
      settingsConfig: JSON.parse(JSON.stringify(provider.settingsConfig)), // 深拷贝
      websiteUrl: provider.websiteUrl,
      category: provider.category,
      sortIndex: newSortIndex, // 复制原 sortIndex + 1
      meta: provider.meta
        ? JSON.parse(JSON.stringify(provider.meta))
        : undefined, // 深拷贝
      icon: provider.icon,
      iconColor: provider.iconColor,
    };

    if (
      thirdPartyLocalToolsEnabled &&
      (activeApp === "opencode" ||
        activeApp === "openclaw" ||
        activeApp === "hermes")
    ) {
      let liveProviderIds: string[] = [];
      try {
        liveProviderIds =
          activeApp === "opencode"
            ? await queryClient.ensureQueryData({
                queryKey: ["opencodeLiveProviderIds"],
                queryFn: () => providersApi.getOpenCodeLiveProviderIds(),
              })
            : activeApp === "openclaw"
              ? await queryClient.ensureQueryData({
                  queryKey: openclawKeys.liveProviderIds,
                  queryFn: () => providersApi.getOpenClawLiveProviderIds(),
                })
              : await queryClient.ensureQueryData({
                  queryKey: hermesKeys.liveProviderIds,
                  queryFn: () => providersApi.getHermesLiveProviderIds(),
                });
      } catch (error) {
        console.error(
          "[App] Failed to load live provider IDs for duplication",
          error,
        );
        const errorMessage = extractErrorMessage(error);
        toast.error(
          t("provider.duplicateLiveIdsLoadFailed", {
            defaultValue: "读取配置中的供应商标识失败，请先修复配置后再试",
          }) + (errorMessage ? `: ${errorMessage}` : ""),
        );
        return;
      }
      const existingKeys = Array.from(
        new Set([...Object.keys(providers), ...liveProviderIds]),
      );
      duplicatedProvider.providerKey = generateUniqueProviderCopyKey(
        provider.id,
        existingKeys,
      );
      duplicatedProvider.addToLive = false;
    }

    if (provider.sortIndex !== undefined) {
      const updates = Object.values(providers)
        .filter(
          (p) =>
            p.sortIndex !== undefined &&
            p.sortIndex >= newSortIndex! &&
            p.id !== provider.id,
        )
        .map((p) => ({
          id: p.id,
          sortIndex: p.sortIndex! + 1,
        }));

      if (updates.length > 0) {
        try {
          await providersApi.updateSortOrder(updates, activeApp);
        } catch (error) {
          console.error("[App] Failed to update sort order", error);
          toast.error(
            t("provider.sortUpdateFailed", {
              defaultValue: "排序更新失败",
            }),
          );
          return; // 如果排序更新失败，不继续添加
        }
      }
    }

    await addProvider(duplicatedProvider);
  };

  const handleOpenTerminal = async (provider: Provider) => {
    if (
      !desktopHelpersEnabled ||
      !isCommandEnabled("open_provider_terminal", profile)
    ) {
      return;
    }

    try {
      const selectedDir = await settingsApi.pickDirectory();
      if (!selectedDir) {
        return;
      }

      await providersApi.openTerminal(provider.id, activeApp, {
        cwd: selectedDir,
      });
      toast.success(
        t("provider.terminalOpened", {
          defaultValue: "终端已打开",
        }),
      );
    } catch (error) {
      console.error("[App] Failed to open terminal", error);
      const errorMessage = extractErrorMessage(error);
      toast.error(
        t("provider.terminalOpenFailed", {
          defaultValue: "打开终端失败",
        }) + (errorMessage ? `: ${errorMessage}` : ""),
      );
    }
  };

  const handleImportSuccess = async () => {
    try {
      await queryClient.invalidateQueries({
        queryKey: ["providers"],
        refetchType: "all",
      });
      await queryClient.refetchQueries({
        queryKey: ["providers"],
        type: "all",
      });
    } catch (error) {
      console.error("[App] Failed to refresh providers after import", error);
      await refetch();
    }
    try {
      if (desktopHelpersEnabled) {
        await providersApi.updateTrayMenu();
      }
    } catch (error) {
      console.error("[App] Failed to refresh tray menu", error);
    }
  };

  const renderContent = () => {
    const effectiveView = coerceViewForProfile(currentView, profile) as View;
    const content = (() => {
      switch (effectiveView) {
        case "settings":
          return (
            <SettingsPage
              open={true}
              onOpenChange={() => setCurrentView("providers")}
              onImportSuccess={handleImportSuccess}
              defaultTab={settingsDefaultTab}
            />
          );
        case "prompts":
          return (
            <PromptPanel
              ref={promptPanelRef}
              open={true}
              onOpenChange={() => setCurrentView("providers")}
              appId={activeApp}
            />
          );
        case "hermesMemory":
          return <HermesMemoryPanel />;
        case "skills":
          return (
            <UnifiedSkillsPanel
              ref={unifiedSkillsPanelRef}
              onOpenDiscovery={() => setCurrentView("skillsDiscovery")}
              currentApp={activeApp === "openclaw" ? "claude" : activeApp}
            />
          );
        case "skillsDiscovery":
          return (
            <SkillsPage
              ref={skillsPageRef}
              initialApp={activeApp === "openclaw" ? "claude" : activeApp}
            />
          );
        case "mcp":
          return (
            <UnifiedMcpPanel
              ref={mcpPanelRef}
              onOpenChange={() => setCurrentView("providers")}
            />
          );
        case "agents":
          return (
            <AgentsPanel onOpenChange={() => setCurrentView("providers")} />
          );
        case "universal":
          return (
            <div className="px-6 pt-4">
              <UniversalProviderPanel />
            </div>
          );

        case "sessions":
          return <SessionManagerPage key={activeApp} appId={activeApp} />;
        case "workspace":
          return <WorkspaceFilesPanel />;
        case "openclawEnv":
          return <EnvPanel />;
        case "openclawTools":
          return <ToolsPanel />;
        case "openclawAgents":
          return <AgentsDefaultsPanel />;
        default:
          return (
            <div className="px-6 flex flex-col flex-1 min-h-0 overflow-hidden">
              <div className="flex-1 overflow-y-auto overflow-x-hidden pb-12 px-1">
                <div key={activeApp} className="space-y-4 animate-fade-in">
                  <ProviderList
                    providers={providers}
                    currentProviderId={currentProviderId}
                    appId={activeApp}
                    isLoading={isLoading}
                    isProxyRunning={isProxyRunning}
                    isProxyTakeover={
                      isProxyRunning && isCurrentAppTakeoverActive
                    }
                    activeProviderId={activeProviderId}
                    onSwitch={switchProvider}
                    onEdit={(provider) => {
                      setEditingProvider(provider);
                    }}
                    onDelete={(provider) =>
                      setConfirmAction({ provider, action: "delete" })
                    }
                    onRemoveFromConfig={
                      thirdPartyLocalToolsEnabled &&
                      (activeApp === "opencode" ||
                        activeApp === "openclaw" ||
                        activeApp === "hermes")
                        ? (provider) =>
                            setConfirmAction({ provider, action: "remove" })
                        : undefined
                    }
                    onDisableOmo={
                      thirdPartyLocalToolsEnabled && activeApp === "opencode"
                        ? handleDisableOmo
                        : undefined
                    }
                    onDisableOmoSlim={
                      thirdPartyLocalToolsEnabled && activeApp === "opencode"
                        ? handleDisableOmoSlim
                        : undefined
                    }
                    onDuplicate={handleDuplicateProvider}
                    onConfigureUsage={setUsageProvider}
                    onOpenWebsite={handleOpenWebsite}
                    onOpenTerminal={
                      desktopHelpersEnabled && activeApp === "claude"
                        ? handleOpenTerminal
                        : undefined
                    }
                    onCreate={() => setIsAddOpen(true)}
                    onSetAsDefault={
                      thirdPartyLocalToolsEnabled && activeApp === "openclaw"
                        ? setAsDefaultModel
                        : thirdPartyLocalToolsEnabled && activeApp === "hermes"
                          ? switchProvider
                          : undefined
                    }
                    desktopHelpersEnabled={desktopHelpersEnabled}
                    thirdPartyLocalToolsEnabled={thirdPartyLocalToolsEnabled}
                    usageCapabilitiesEnabled={usageCapabilitiesEnabled}
                  />
                </div>
              </div>
            </div>
          );
      }
    })();

    return (
      <div key={effectiveView} className="flex-1 min-h-0 animate-fade-in">
        <Suspense fallback={lazyContentFallback}>{content}</Suspense>
      </div>
    );
  };

  if (profileMismatchMessage) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-background p-6 text-foreground">
        <section className="max-w-xl rounded-lg border border-destructive/40 bg-card p-6 shadow-sm">
          <h1 className="text-lg font-semibold text-destructive">
            ccs-web profile mismatch
          </h1>
          <p className="mt-3 text-sm text-muted-foreground">
            The frontend build profile does not match the backend runtime
            profile. Rebuild or restart the service with a consistent
            CCS_WEB_PROFILE / VITE_CCS_WEB_PROFILE.
          </p>
          <pre className="mt-4 overflow-auto rounded-md bg-muted p-3 text-xs">
            {profileMismatchMessage}
          </pre>
        </section>
      </main>
    );
  }

  // Auth loading state
  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-4">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-blue-500 border-t-transparent" />
          <p className="text-sm text-muted-foreground">
            {t("auth.checking", { defaultValue: "Checking authentication..." })}
          </p>
        </div>
      </div>
    );
  }

  // Auth required but not authenticated
  if (authEnabled && !isAuthenticated) {
    return <LoginPage />;
  }

  return (
    <div
      className="flex flex-col h-screen overflow-hidden bg-background text-foreground selection:bg-primary/30 pb-4"
      style={{ overflowX: "hidden", paddingTop: contentTopOffset }}
    >
      {localEnvHelpersEnabled && showEnvBanner && envConflicts.length > 0 && (
        <EnvWarningBanner
          conflicts={envConflicts}
          onDismiss={() => {
            setShowEnvBanner(false);
            sessionStorage.setItem("env_banner_dismissed", "true");
          }}
          onDeleted={async () => {
            try {
              const allConflicts = await checkAllEnvConflicts();
              const flatConflicts = Object.values(allConflicts).flat();
              setEnvConflicts(flatConflicts);
              if (flatConflicts.length === 0) {
                setShowEnvBanner(false);
              }
            } catch (error) {
              console.error(
                "[App] Failed to re-check conflicts after deletion:",
                error,
              );
            }
          }}
        />
      )}

      <header
        className="fixed z-50 w-full transition-all duration-300 bg-background/80 backdrop-blur-md"
        style={{ top: dragBarHeight, height: HEADER_HEIGHT } as any}
      >
        <div className="flex h-full items-center justify-between gap-2 px-6">
          <div
            className="flex items-center gap-1"
            style={{ WebkitAppRegion: "no-drag" } as any}
          >
            {currentView !== "providers" ? (
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="icon"
                  onClick={() =>
                    setCurrentView(
                      currentView === "skillsDiscovery"
                        ? "skills"
                        : "providers",
                    )
                  }
                  className="mr-2 rounded-lg"
                >
                  <ArrowLeft className="w-4 h-4" />
                </Button>
                <h1 className="text-lg font-semibold">
                  {currentView === "settings" && t("settings.title")}
                  {currentView === "prompts" &&
                    t("prompts.title", { appName: t(`apps.${activeApp}`) })}
                  {currentView === "skills" && t("skills.title")}
                  {currentView === "skillsDiscovery" && t("skills.title")}
                  {currentView === "mcp" && t("mcp.unifiedPanel.title")}
                  {currentView === "agents" && t("agents.title")}
                  {currentView === "universal" &&
                    t("universalProvider.title", {
                      defaultValue: "统一供应商",
                    })}
                  {currentView === "sessions" && t("sessionManager.title")}
                  {currentView === "workspace" && t("workspace.title")}
                  {currentView === "openclawEnv" && t("openclaw.env.title")}
                  {currentView === "openclawTools" && t("openclaw.tools.title")}
                  {currentView === "openclawAgents" &&
                    t("openclaw.agents.title")}
                  {currentView === "hermesMemory" && t("hermes.memory.title")}
                </h1>
              </div>
            ) : (
              <div className="flex items-center gap-2">
                <div className="relative inline-flex items-center">
                  <a
                    href="https://github.com/dkfjtang/ccs-gateway-web"
                    target="_blank"
                    rel="noreferrer"
                    className={cn(
                      "text-xl font-semibold transition-colors",
                      isProxyRunning && isCurrentAppTakeoverActive
                        ? "text-emerald-500 hover:text-emerald-600 dark:text-emerald-400 dark:hover:text-emerald-300"
                        : "text-blue-500 hover:text-blue-600 dark:text-blue-400 dark:hover:text-blue-300",
                    )}
                  >
                    CC Switch
                  </a>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => {
                    setSettingsDefaultTab("general");
                    setCurrentView("settings");
                  }}
                  title={t("common.settings")}
                  className="hover:bg-black/5 dark:hover:bg-white/5"
                >
                  <Settings className="w-4 h-4" />
                </Button>
                <UpdateBadge
                  onClick={() => {
                    setSettingsDefaultTab("about");
                    setCurrentView("settings");
                  }}
                />
                {isCurrentAppTakeoverActive && (
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => {
                      setSettingsDefaultTab("usage");
                      setCurrentView("settings");
                    }}
                    title={t("usage.title", {
                      defaultValue: "使用统计",
                    })}
                    className="hover:bg-black/5 dark:hover:bg-white/5"
                  >
                    <BarChart2 className="w-4 h-4" />
                  </Button>
                )}
              </div>
            )}
          </div>

          <div className="flex flex-1 min-w-0 items-center justify-end gap-1.5">
            {currentView === "providers" &&
              (((activeApp !== "opencode" &&
                activeApp !== "openclaw" &&
                activeApp !== "hermes") ||
                shouldShowRefreshAllUsageButton) && (
                <div
                  className="flex shrink-0 items-center gap-1.5"
                  style={{ WebkitAppRegion: "no-drag" } as any}
                >
                  {activeApp !== "opencode" &&
                    activeApp !== "openclaw" &&
                    activeApp !== "hermes" && (
                      <>
                        {activeApp === "claude-desktop" &&
                        thirdPartyLocalToolsEnabled ? (
                          <ClaudeDesktopRouteToggle />
                        ) : (
                          settingsData?.enableLocalProxy && (
                            <ProxyToggle activeApp={activeApp} />
                          )
                        )}
                        {activeApp !== "claude-desktop" &&
                          settingsData?.enableFailoverToggle && (
                            <FailoverToggle activeApp={activeApp} />
                          )}
                      </>
                    )}
                  {shouldShowRefreshAllUsageButton && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => void handleRefreshAllUsage()}
                      disabled={isRefreshingAllUsage}
                      aria-label={t("usage.refreshAllUsage", {
                        defaultValue: "刷新全部自定义计费",
                      })}
                      className="h-8 rounded-lg border border-border/60 bg-muted/45 px-2 text-[11px] text-muted-foreground hover:text-foreground hover:bg-muted gap-1.5"
                      title={t("usage.refreshAllUsage", {
                        defaultValue: "刷新全部自定义计费",
                      })}
                    >
                      <RefreshCw
                        className={cn(
                          "w-4 h-4",
                          isRefreshingAllUsage && "animate-spin",
                        )}
                      />
                      <span className="text-[11px]">
                        {t("usage.refreshBillingShort", {
                          defaultValue: "刷新计费",
                        })}
                      </span>
                    </Button>
                  )}
                </div>
              ))}
            <div
              ref={toolbarRef}
              className="flex flex-1 min-w-0 overflow-x-hidden items-center py-4 pr-2"
            >
              <div
                className="flex shrink-0 items-center gap-1.5 ml-auto"
                style={{ WebkitAppRegion: "no-drag" } as any}
              >
                {currentView === "prompts" && promptsEnabled && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => promptPanelRef.current?.openAdd()}
                    className="hover:bg-black/5 dark:hover:bg-white/5"
                  >
                    <Plus className="w-4 h-4 mr-2" />
                    {t("prompts.add")}
                  </Button>
                )}
                {currentView === "mcp" && mcpEnabled && (
                  <>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => mcpPanelRef.current?.openImport()}
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <Download className="w-4 h-4 mr-2" />
                      {t("mcp.importExisting")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => mcpPanelRef.current?.openAdd()}
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <Plus className="w-4 h-4 mr-2" />
                      {t("mcp.addMcp")}
                    </Button>
                  </>
                )}
                {currentView === "skills" && skillsEnabled && (
                  <>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        unifiedSkillsPanelRef.current?.openRestoreFromBackup()
                      }
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <History className="w-4 h-4 mr-2" />
                      {t("skills.restoreFromBackup.button")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        unifiedSkillsPanelRef.current?.openInstallFromZip()
                      }
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <FolderArchive className="w-4 h-4 mr-2" />
                      {t("skills.installFromZip.button")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() =>
                        unifiedSkillsPanelRef.current?.openImport()
                      }
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <Download className="w-4 h-4 mr-2" />
                      {t("skills.import")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setCurrentView("skillsDiscovery")}
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <Search className="w-4 h-4 mr-2" />
                      {t("skills.discover")}
                    </Button>
                  </>
                )}
                {currentView === "skillsDiscovery" && skillsEnabled && (
                  <>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => skillsPageRef.current?.refresh()}
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <RefreshCw className="w-4 h-4 mr-2" />
                      {t("skills.refresh")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => skillsPageRef.current?.openRepoManager()}
                      className="hover:bg-black/5 dark:hover:bg-white/5"
                    >
                      <Settings className="w-4 h-4 mr-2" />
                      {t("skills.repoManager")}
                    </Button>
                  </>
                )}
                {currentView === "providers" && (
                  <>
                    <AppSwitcher
                      activeApp={activeApp}
                      onSwitch={setProfiledActiveApp}
                      visibleApps={visibleApps}
                      compact={isToolbarCompact}
                    />

                    <div className="flex items-center gap-1 p-1 bg-muted rounded-xl">
                      <div
                        key={
                          activeApp === "openclaw"
                            ? "openclaw"
                            : activeApp === "hermes"
                              ? "hermes"
                              : "default"
                        }
                        className="flex items-center gap-1 animate-fade-in"
                      >
                        {activeApp === "hermes" &&
                        thirdPartyLocalToolsEnabled ? (
                          <>
                            {skillsEnabled && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("skills")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("skills.manage")}
                              >
                                <Wrench className="w-4 h-4" />
                              </Button>
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setCurrentView("hermesMemory")}
                              className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                              title={t("hermes.memory.title")}
                            >
                              <Brain className="w-4 h-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => void openHermesWebUI()}
                              className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                              title={t("hermes.webui.open")}
                            >
                              <LayoutDashboard className="w-4 h-4" />
                            </Button>
                            {mcpEnabled && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("mcp")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("mcp.title")}
                              >
                                <McpIcon size={16} />
                              </Button>
                            )}
                          </>
                        ) : activeApp === "openclaw" &&
                          thirdPartyLocalToolsEnabled ? (
                          <>
                            {workspaceEnabled && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("workspace")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("workspace.manage")}
                              >
                                <FolderOpen className="w-4 h-4" />
                              </Button>
                            )}
                            {promptsEnabled && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("prompts")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("prompts.manage")}
                                aria-label={t("prompts.manage")}
                              >
                                <Book className="w-4 h-4" />
                              </Button>
                            )}
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setCurrentView("openclawEnv")}
                              className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                              title={t("openclaw.env.title")}
                            >
                              <KeyRound className="w-4 h-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setCurrentView("openclawTools")}
                              className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                              title={t("openclaw.tools.title")}
                            >
                              <Shield className="w-4 h-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => setCurrentView("openclawAgents")}
                              className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                              title={t("openclaw.agents.title")}
                            >
                              <Cpu className="w-4 h-4" />
                            </Button>
                            {sessionsEnabled && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("sessions")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("sessionManager.title")}
                              >
                                <History className="w-4 h-4" />
                              </Button>
                            )}
                          </>
                        ) : (
                          <>
                            {hasSkillsSupport && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("skills")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("skills.manage")}
                              >
                                <Wrench className="flex-shrink-0 w-4 h-4" />
                              </Button>
                            )}
                            {promptsEnabled &&
                              activeApp !== "claude-desktop" && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("prompts")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("prompts.manage")}
                                aria-label={t("prompts.manage")}
                              >
                                <Book className="w-4 h-4" />
                              </Button>
                            )}
                            {hasSessionSupport && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("sessions")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("sessionManager.title")}
                              >
                                <History className="flex-shrink-0 w-4 h-4" />
                              </Button>
                            )}
                            {mcpEnabled && activeApp !== "claude-desktop" && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setCurrentView("mcp")}
                                className="text-muted-foreground hover:text-foreground hover:bg-black/5 dark:hover:bg-white/5 w-8 px-2"
                                title={t("mcp.title")}
                              >
                                <McpIcon size={16} />
                              </Button>
                            )}
                          </>
                        )}
                      </div>
                    </div>

                    <Button
                      onClick={() => setIsAddOpen(true)}
                      size="icon"
                      className={`ml-2 ${addActionButtonClass}`}
                    >
                      <Plus className="w-5 h-5" />
                    </Button>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="flex-1 min-h-0 flex flex-col overflow-y-auto animate-fade-in">
        {isOpenClawView && openclawHealthWarnings.length > 0 && (
          <Suspense fallback={null}>
            <OpenClawHealthBanner warnings={openclawHealthWarnings} />
          </Suspense>
        )}
        {renderContent()}
      </main>

      <Suspense fallback={null}>
        {isAddOpen && (
          <AddProviderDialog
            open={isAddOpen}
            onOpenChange={setIsAddOpen}
            appId={activeApp}
            onSubmit={addProvider}
          />
        )}
      </Suspense>

      <Suspense fallback={null}>
        {editingProvider && (
          <EditProviderDialog
            open={Boolean(editingProvider)}
            provider={effectiveEditingProvider}
            onOpenChange={(open) => {
              if (!open) {
                setEditingProvider(null);
              }
            }}
            onSubmit={handleEditProvider}
            appId={activeApp}
            isProxyTakeover={isProxyRunning && isCurrentAppTakeoverActive}
          />
        )}
      </Suspense>

      <Suspense fallback={null}>
        {effectiveUsageProvider && (
          <UsageScriptModal
            key={effectiveUsageProvider.id}
            provider={effectiveUsageProvider}
            appId={activeApp}
            isOpen={Boolean(usageProvider)}
            onClose={() => setUsageProvider(null)}
            onSave={(script) => {
              if (usageProvider) {
                void saveUsageScript(usageProvider, script);
              }
            }}
          />
        )}
      </Suspense>

      <ConfirmDialog
        isOpen={Boolean(confirmAction)}
        title={
          confirmAction?.action === "remove"
            ? t("confirm.removeProvider")
            : t("confirm.deleteProvider")
        }
        message={
          confirmAction
            ? confirmAction.action === "remove"
              ? t("confirm.removeProviderMessage", {
                  name: confirmAction.provider.name,
                })
              : t("confirm.deleteProviderMessage", {
                  name: confirmAction.provider.name,
                })
            : ""
        }
        onConfirm={() => void handleConfirmAction()}
        onCancel={() => setConfirmAction(null)}
      />

      <ConfirmDialog
        isOpen={launchDashboardOpen}
        title={t("hermes.webui.launchConfirmTitle")}
        message={t("hermes.webui.launchConfirmMessage")}
        confirmText={t("hermes.webui.launchConfirmAction")}
        variant="info"
        onConfirm={() => {
          setLaunchDashboardOpen(false);
          void (async () => {
            try {
              const { hermesApi } = await import("@/lib/api/hermes");
              await hermesApi.launchDashboard();
              toast.success(t("hermes.webui.launching"));
            } catch (error) {
              toast.error(t("hermes.webui.launchFailed"), {
                description: extractErrorMessage(error) || undefined,
              });
            }
          })();
        }}
        onCancel={() => setLaunchDashboardOpen(false)}
      />

      <DeepLinkImportDialog />
      <FirstRunNoticeDialog />
    </div>
  );
}

export default App;
