import {
  useCallback,
  useEffect,
  lazy,
  useMemo,
  useRef,
  Suspense,
  useState,
  type ComponentProps,
} from "react";
import { AlertTriangle, Search, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { Provider } from "@/types";
import type { AppId } from "@/lib/api";
import { providersApi } from "@/lib/api/providers";
import {
  useOpenClawLiveProviderIds,
  useOpenClawDefaultModel,
} from "@/hooks/useOpenClaw";
import {
  useHermesLiveProviderIds,
  useHermesModelConfig,
} from "@/hooks/useHermes";
import { useStreamCheck } from "@/hooks/useStreamCheck";
import { ProviderCard } from "@/components/providers/ProviderCard";
import { ProviderEmptyState } from "@/components/providers/ProviderEmptyState";
import {
  useAutoFailoverEnabled,
  useFailoverQueue,
  useAddToFailoverQueue,
  useRemoveFromFailoverQueue,
} from "@/lib/query/failover";
import {
  useCurrentOmoProviderId,
  useCurrentOmoSlimProviderId,
} from "@/lib/query/omo";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { settingsApi } from "@/lib/api/settings";
import { toast } from "sonner";

const ProviderListDnd = lazy(async () => ({
  default: (await import("@/components/providers/ProviderListDnd"))
    .ProviderListDnd,
}));

export type ProviderCardItemProps = ComponentProps<typeof ProviderCard>;

interface ProviderListProps {
  providers: Record<string, Provider>;
  currentProviderId: string;
  appId: AppId;
  onSwitch: (provider: Provider) => void;
  onEdit: (provider: Provider) => void;
  onDelete: (provider: Provider) => void;
  onRemoveFromConfig?: (provider: Provider) => void;
  onDisableOmo?: () => void;
  onDisableOmoSlim?: () => void;
  onDuplicate: (provider: Provider) => void;
  onConfigureUsage?: (provider: Provider) => void;
  onOpenWebsite: (url: string) => void;
  onOpenTerminal?: (provider: Provider) => void;
  onCreate?: () => void;
  isLoading?: boolean;
  isProxyRunning?: boolean; // 代理服务运行状态
  isProxyTakeover?: boolean; // 代理接管模式（Live配置已被接管）
  activeProviderId?: string; // 代理当前实际使用的供应商 ID（用于故障转移模式下标注绿色边框）
  onSetAsDefault?: (provider: Provider) => void; // OpenClaw: set as default model
  desktopHelpersEnabled?: boolean;
  thirdPartyLocalToolsEnabled?: boolean;
  usageCapabilitiesEnabled?: boolean;
}

export function ProviderList({
  providers,
  currentProviderId,
  appId,
  onSwitch,
  onEdit,
  onDelete,
  onRemoveFromConfig,
  onDisableOmo,
  onDisableOmoSlim,
  onDuplicate,
  onConfigureUsage,
  onOpenWebsite,
  onOpenTerminal,
  onCreate,
  isLoading = false,
  isProxyRunning = false,
  isProxyTakeover = false,
  activeProviderId,
  onSetAsDefault,
  desktopHelpersEnabled = true,
  thirdPartyLocalToolsEnabled = true,
  usageCapabilitiesEnabled = true,
}: ProviderListProps) {
  const { t, i18n } = useTranslation();
  const { checkProvider, isChecking } = useStreamCheck(appId);
  const localToolQueriesEnabled = thirdPartyLocalToolsEnabled;
  const sortedProviders = useMemo(() => {
    const locale = i18n.language === "zh" ? "zh-CN" : "en-US";
    return Object.values(providers).sort((a, b) => {
      if (a.sortIndex !== undefined && b.sortIndex !== undefined) {
        return a.sortIndex - b.sortIndex;
      }
      if (a.sortIndex !== undefined) return -1;
      if (b.sortIndex !== undefined) return 1;

      const timeA = a.createdAt ?? 0;
      const timeB = b.createdAt ?? 0;
      if (timeA && timeB && timeA !== timeB) {
        return timeA - timeB;
      }

      return a.name.localeCompare(b.name, locale);
    });
  }, [providers, i18n.language]);

  const { data: opencodeLiveIds } = useQuery({
    queryKey: ["opencodeLiveProviderIds"],
    queryFn: () => providersApi.getOpenCodeLiveProviderIds(),
    enabled: localToolQueriesEnabled && appId === "opencode",
  });

  // OpenClaw: 查询 live 配置中的供应商 ID 列表，用于判断 isInConfig
  const { data: openclawLiveIds } = useOpenClawLiveProviderIds(
    localToolQueriesEnabled && appId === "openclaw",
  );

  // Hermes: 查询 live 配置中的供应商 ID 列表，用于判断 isInConfig
  const { data: hermesLiveIds } = useHermesLiveProviderIds(
    localToolQueriesEnabled && appId === "hermes",
  );

  // Hermes: 读取当前 model.provider，用于判断哪个供应商是"当前激活"（高亮）
  const { data: hermesModelConfig } = useHermesModelConfig(
    localToolQueriesEnabled && appId === "hermes",
  );
  const hermesCurrentProviderId = hermesModelConfig?.provider;

  // 判断供应商是否已添加到配置（累加模式应用：OpenCode/OpenClaw/Hermes）
  const isProviderInConfig = useCallback(
    (providerId: string): boolean => {
      if (appId === "opencode") {
        return opencodeLiveIds?.includes(providerId) ?? false;
      }
      if (appId === "openclaw") {
        return openclawLiveIds?.includes(providerId) ?? false;
      }
      if (appId === "hermes") {
        return hermesLiveIds?.includes(providerId) ?? false;
      }
      return true; // 其他应用始终返回 true
    },
    [appId, opencodeLiveIds, openclawLiveIds, hermesLiveIds],
  );

  // OpenClaw: query default model to determine which provider is default
  const { data: openclawDefaultModel } = useOpenClawDefaultModel(
    localToolQueriesEnabled && appId === "openclaw",
  );

  const isProviderDefaultModel = useCallback(
    (providerId: string): boolean => {
      if (appId !== "openclaw" || !openclawDefaultModel?.primary) return false;
      return openclawDefaultModel.primary.startsWith(providerId + "/");
    },
    [appId, openclawDefaultModel],
  );

  // 故障转移相关
  const { data: isAutoFailoverEnabled } = useAutoFailoverEnabled(appId);
  // Queue membership only affects the failover control UI when proxy takeover
  // and auto failover are both active. Keep the proxy runtime path unchanged
  // while avoiding an invisible queue request during normal provider browsing.
  const shouldFetchFailoverQueue =
    isProxyTakeover === true && isAutoFailoverEnabled === true;
  const { data: failoverQueue } = useFailoverQueue(appId, {
    enabled: shouldFetchFailoverQueue,
  });
  const addToQueue = useAddToFailoverQueue();
  const removeFromQueue = useRemoveFromFailoverQueue();

  const isFailoverModeActive = shouldFetchFailoverQueue;

  const isOpenCode = appId === "opencode";
  const { data: currentOmoId } = useCurrentOmoProviderId(
    localToolQueriesEnabled && isOpenCode,
  );
  const { data: currentOmoSlimId } = useCurrentOmoSlimProviderId(
    localToolQueriesEnabled && isOpenCode,
  );

  const getFailoverPriority = useCallback(
    (providerId: string): number | undefined => {
      if (!isFailoverModeActive || !failoverQueue) return undefined;
      const index = failoverQueue.findIndex(
        (item) => item.providerId === providerId,
      );
      return index >= 0 ? index + 1 : undefined;
    },
    [isFailoverModeActive, failoverQueue],
  );

  const isInFailoverQueue = useCallback(
    (providerId: string): boolean => {
      if (!isFailoverModeActive || !failoverQueue) return false;
      return failoverQueue.some((item) => item.providerId === providerId);
    },
    [isFailoverModeActive, failoverQueue],
  );

  const handleToggleFailover = useCallback(
    (providerId: string, enabled: boolean) => {
      if (enabled) {
        addToQueue.mutate({ appType: appId, providerId });
      } else {
        removeFromQueue.mutate({ appType: appId, providerId });
      }
    },
    [appId, addToQueue, removeFromQueue],
  );

  const [searchTerm, setSearchTerm] = useState("");
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [showStreamCheckConfirm, setShowStreamCheckConfirm] = useState(false);
  const [pendingTestProvider, setPendingTestProvider] =
    useState<Provider | null>(null);
  const { data: claudeDesktopStatus } = useQuery({
    queryKey: ["claudeDesktopStatus"],
    queryFn: () => providersApi.getClaudeDesktopStatus(),
    enabled: localToolQueriesEnabled && appId === "claude-desktop",
    refetchInterval:
      localToolQueriesEnabled && appId === "claude-desktop" ? 5000 : false,
  });

  // Query settings for streamCheckConfirmed flag
  const { data: settings } = useQuery({
    queryKey: ["settings"],
    queryFn: () => settingsApi.get(),
  });

  const handleTest = useCallback(
    (provider: Provider) => {
      if (!settings?.streamCheckConfirmed) {
        setPendingTestProvider(provider);
        setShowStreamCheckConfirm(true);
      } else {
        checkProvider(provider.id, provider.name);
      }
    },
    [checkProvider, settings?.streamCheckConfirmed],
  );

  const handleStreamCheckConfirm = async () => {
    setShowStreamCheckConfirm(false);
    try {
      if (settings) {
        const { webdavSync: _, s3Sync: _s3Sync, ...rest } = settings;
        await settingsApi.save({ ...rest, streamCheckConfirmed: true });
        await queryClient.invalidateQueries({ queryKey: ["settings"] });
      }
    } catch (error) {
      console.error("Failed to save stream check confirmed:", error);
    }
    if (pendingTestProvider) {
      checkProvider(pendingTestProvider.id, pendingTestProvider.name);
      setPendingTestProvider(null);
    }
  };

  // Import current live config as default provider
  const queryClient = useQueryClient();
  const importMutation = useMutation({
    mutationFn: async (): Promise<boolean> => {
      if (!thirdPartyLocalToolsEnabled) {
        return providersApi.importDefault(appId);
      }
      if (appId === "opencode") {
        const count = await providersApi.importOpenCodeFromLive();
        return count > 0;
      }
      if (appId === "openclaw") {
        const count = await providersApi.importOpenClawFromLive();
        return count > 0;
      }
      if (appId === "hermes") {
        const count = await providersApi.importHermesFromLive();
        return count > 0;
      }
      if (appId === "claude-desktop") {
        const count = await providersApi.importClaudeDesktopFromClaude();
        return count > 0;
      }
      return providersApi.importDefault(appId);
    },
    onSuccess: (imported) => {
      if (imported) {
        queryClient.invalidateQueries({ queryKey: ["providers", appId] });
        if (appId === "claude-desktop") {
          queryClient.invalidateQueries({ queryKey: ["claudeDesktopStatus"] });
        }
        toast.success(t("provider.importCurrentDescription"));
      } else {
        toast.info(t("provider.noProviders"));
      }
    },
    onError: (error: Error) => {
      toast.error(error.message);
    },
  });

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase();
      if ((event.metaKey || event.ctrlKey) && key === "f") {
        event.preventDefault();
        setIsSearchOpen(true);
        return;
      }

      if (key === "escape") {
        setIsSearchOpen(false);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  useEffect(() => {
    if (isSearchOpen) {
      const frame = requestAnimationFrame(() => {
        searchInputRef.current?.focus();
        searchInputRef.current?.select();
      });
      return () => cancelAnimationFrame(frame);
    }
  }, [isSearchOpen]);

  const filteredProviders = useMemo(() => {
    const keyword = searchTerm.trim().toLowerCase();
    if (!keyword) return sortedProviders;
    return sortedProviders.filter((provider) => {
      const fields = [provider.name, provider.notes, provider.websiteUrl];
      return fields.some((field) =>
        field?.toString().toLowerCase().includes(keyword),
      );
    });
  }, [searchTerm, sortedProviders]);
  const isFilteringProviders = searchTerm.trim().length > 0;

  const claudeDesktopStatusMessages = useMemo(() => {
    if (appId !== "claude-desktop" || !claudeDesktopStatus) return [];

    const messages: string[] = [];
    if (!claudeDesktopStatus.supported) {
      messages.push(
        t("claudeDesktop.statusUnsupported", {
          defaultValue: "当前平台暂不支持 Claude Desktop 3P 配置写入。",
        }),
      );
      return messages;
    }

    if (claudeDesktopStatus.staleRawModels) {
      messages.push(
        t("claudeDesktop.statusStaleRawModels", {
          defaultValue:
            "Claude Desktop profile 中存在非 claude-* 模型名，新版 Claude Desktop 可能拒绝加载；重新切换当前供应商可修复。",
        }),
      );
    }
    if (claudeDesktopStatus.missingRouteMappings) {
      messages.push(
        t("claudeDesktop.statusMissingRouteMappings", {
          defaultValue:
            "当前供应商启用了模型映射，但没有有效路由；请编辑供应商并补全至少一个模型映射。",
        }),
      );
    }
    if (
      claudeDesktopStatus.mode === "proxy" &&
      !claudeDesktopStatus.gatewayTokenConfigured
    ) {
      messages.push(
        t("claudeDesktop.statusGatewayTokenMissing", {
          defaultValue:
            "当前本地路由 token 尚未生成；重新切换该供应商会写入新的本地 token。",
        }),
      );
    }

    const expected = claudeDesktopStatus.expectedBaseUrl?.replace(/\/+$/, "");
    const actual = claudeDesktopStatus.actualBaseUrl?.replace(/\/+$/, "");
    if (expected && actual && expected !== actual) {
      messages.push(
        t("claudeDesktop.statusBaseUrlMismatch", {
          expected,
          actual,
          defaultValue:
            "Claude Desktop profile 指向的地址与当前供应商不一致；当前为 {{actual}}，应为 {{expected}}。重新切换当前供应商可修复。",
        }),
      );
    }

    return messages;
  }, [appId, claudeDesktopStatus, t]);

  const getProviderCardProps = useCallback(
    (provider: Provider): ProviderCardItemProps => {
      const isOmo = provider.category === "omo";
      const isOmoSlim = provider.category === "omo-slim";
      const isOmoCurrent = isOmo && provider.id === (currentOmoId || "");
      const isOmoSlimCurrent =
        isOmoSlim && provider.id === (currentOmoSlimId || "");
      const isHermesCurrent =
        appId === "hermes" && hermesCurrentProviderId === provider.id;

      return {
        provider,
        isCurrent: isOmo
          ? isOmoCurrent
          : isOmoSlim
            ? isOmoSlimCurrent
            : appId === "hermes"
              ? isHermesCurrent
              : provider.id === currentProviderId,
        appId,
        isInConfig: localToolQueriesEnabled
          ? isProviderInConfig(provider.id)
          : true,
        isOmo,
        isOmoSlim,
        onSwitch,
        onEdit,
        onDelete,
        onRemoveFromConfig,
        onDisableOmo,
        onDisableOmoSlim,
        onDuplicate,
        onConfigureUsage: onConfigureUsage ?? (() => undefined),
        onOpenWebsite,
        onOpenTerminal,
        onTest: handleTest,
        isTesting: isChecking(provider.id),
        isProxyRunning,
        isProxyTakeover,
        isAutoFailoverEnabled: isFailoverModeActive,
        failoverPriority: getFailoverPriority(provider.id),
        isInFailoverQueue: isInFailoverQueue(provider.id),
        onToggleFailover: (enabled) => handleToggleFailover(provider.id, enabled),
        activeProviderId,
        isDefaultModel: !localToolQueriesEnabled
          ? false
          : appId === "hermes"
            ? isHermesCurrent
            : isProviderDefaultModel(provider.id),
        onSetAsDefault: onSetAsDefault
          ? () => onSetAsDefault(provider)
          : undefined,
        usageCapabilitiesEnabled,
      };
    },
    [
      activeProviderId,
      appId,
      currentOmoId,
      currentOmoSlimId,
      currentProviderId,
      failoverQueue,
      getFailoverPriority,
      handleTest,
      handleToggleFailover,
      hermesCurrentProviderId,
      isChecking,
      isFailoverModeActive,
      isInFailoverQueue,
      isProviderDefaultModel,
      isProviderInConfig,
      isProxyRunning,
      isProxyTakeover,
      localToolQueriesEnabled,
      onConfigureUsage,
      onDelete,
      onDisableOmo,
      onDisableOmoSlim,
      onDuplicate,
      onEdit,
      onOpenTerminal,
      onOpenWebsite,
      onRemoveFromConfig,
      onSetAsDefault,
      onSwitch,
      usageCapabilitiesEnabled,
    ],
  );

  const renderPlainProviderList = () => (
    <div className="space-y-3">
      {filteredProviders.map((provider) => (
        <ProviderCard key={provider.id} {...getProviderCardProps(provider)} />
      ))}
    </div>
  );

  const renderProviderList = () => {
    if (desktopHelpersEnabled && !isFilteringProviders) {
      return (
        <Suspense fallback={renderPlainProviderList()}>
          <ProviderListDnd
            providers={providers}
            appId={appId}
            desktopHelpersEnabled={desktopHelpersEnabled}
            filteredProviders={filteredProviders}
            getItemProps={getProviderCardProps}
          />
        </Suspense>
      );
    }

    return renderPlainProviderList();
  };

  if (isLoading) {
    return (
      <div className="space-y-3">
        {[0, 1, 2].map((index) => (
          <div
            key={index}
            className="w-full border border-dashed rounded-lg h-28 border-muted-foreground/40 bg-muted/40"
          />
        ))}
      </div>
    );
  }

  if (sortedProviders.length === 0) {
    return (
      <ProviderEmptyState
        appId={appId}
        onCreate={onCreate}
        onImport={
          thirdPartyLocalToolsEnabled ||
          (appId !== "opencode" &&
            appId !== "openclaw" &&
            appId !== "hermes" &&
            appId !== "claude-desktop")
            ? () => importMutation.mutate()
            : undefined
        }
      />
    );
  }

  return (
    <div className="mt-4 space-y-4">
      {claudeDesktopStatusMessages.length > 0 && (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-900 dark:text-amber-200">
          <div className="flex items-center gap-2 font-medium">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            {t("claudeDesktop.statusTitle", {
              defaultValue: "Claude Desktop 配置需要检查",
            })}
          </div>
          <ul className="mt-2 space-y-1 text-xs leading-relaxed">
            {claudeDesktopStatusMessages.map((message) => (
              <li key={message}>{message}</li>
            ))}
          </ul>
        </div>
      )}
      {isSearchOpen && (
        <div
          key="provider-search"
          className="fixed left-1/2 top-[6.5rem] z-40 w-[min(90vw,26rem)] -translate-x-1/2 animate-fade-in sm:right-6 sm:left-auto sm:translate-x-0"
        >
          <div className="p-4 space-y-3 border shadow-md rounded-2xl border-white/10 bg-background/95 shadow-black/20 backdrop-blur-md">
            <div className="relative flex items-center gap-2">
              <Search className="absolute w-4 h-4 -translate-y-1/2 pointer-events-none left-3 top-1/2 text-muted-foreground" />
              <Input
                ref={searchInputRef}
                value={searchTerm}
                onChange={(event) => setSearchTerm(event.target.value)}
                placeholder={t("provider.searchPlaceholder", {
                  defaultValue: "Search name, notes, or URL...",
                })}
                aria-label={t("provider.searchAriaLabel", {
                  defaultValue: "Search providers",
                })}
                className="pr-16 pl-9"
              />
              {searchTerm && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="absolute text-xs -translate-y-1/2 right-11 top-1/2"
                  onClick={() => setSearchTerm("")}
                >
                  {t("common.clear", { defaultValue: "Clear" })}
                </Button>
              )}
              <Button
                variant="ghost"
                size="icon"
                className="ml-auto"
                onClick={() => setIsSearchOpen(false)}
                aria-label={t("provider.searchCloseAriaLabel", {
                  defaultValue: "Close provider search",
                })}
              >
                <X className="w-4 h-4" />
              </Button>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] text-muted-foreground">
              <span>
                {t("provider.searchScopeHint", {
                  defaultValue: "Matches provider name, notes, and URL.",
                })}
              </span>
              <span>
                {t("provider.searchCloseHint", {
                  defaultValue: "Press Esc to close",
                })}
              </span>
            </div>
          </div>
        </div>
      )}

      {filteredProviders.length === 0 ? (
        <div className="px-6 py-8 text-sm text-center border border-dashed rounded-lg border-border text-muted-foreground">
          {t("provider.noSearchResults", {
            defaultValue: "No providers match your search.",
          })}
        </div>
      ) : (
        renderProviderList()
      )}

      <ConfirmDialog
        isOpen={showStreamCheckConfirm}
        variant="info"
        title={t("confirm.streamCheck.title")}
        message={t("confirm.streamCheck.message")}
        confirmText={t("confirm.streamCheck.confirm")}
        onConfirm={() => void handleStreamCheckConfirm()}
        onCancel={() => {
          setShowStreamCheckConfirm(false);
          setPendingTestProvider(null);
        }}
      />
    </div>
  );
}
