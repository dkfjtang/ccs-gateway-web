import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  Loader2,
  Save,
  FolderSearch,
  Database,
  Cloud,
  ScrollText,
  HardDriveDownload,
  FlaskConical,
} from "lucide-react";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { settingsApi } from "@/lib/api";
import { LanguageSettings } from "@/components/settings/LanguageSettings";
import { ThemeSettings } from "@/components/settings/ThemeSettings";
import { AppVisibilitySettings } from "@/components/settings/AppVisibilitySettings";
import { ImportExportSection } from "@/components/settings/ImportExportSection";
import { useInstalledSkills } from "@/hooks/useSkills";
import { useSettings } from "@/hooks/useSettings";
import { useImportExport } from "@/hooks/useImportExport";
import { useTranslation } from "react-i18next";
import type { SettingsFormState } from "@/hooks/useSettings";
import { getBakedProfile, isCapabilityGroupEnabled } from "@/lib/capabilities";

const BackupListSection = lazy(() =>
  import("@/components/settings/BackupListSection").then((module) => ({
    default: module.BackupListSection,
  })),
);
const DirectorySettings = lazy(() =>
  import("@/components/settings/DirectorySettings").then((module) => ({
    default: module.DirectorySettings,
  })),
);
const ProxyTabContent = lazy(() =>
  import("@/components/settings/ProxyTabContent").then((module) => ({
    default: module.ProxyTabContent,
  })),
);
const SkillStorageLocationSettings = lazy(() =>
  import("@/components/settings/SkillStorageLocationSettings").then(
    (module) => ({
      default: module.SkillStorageLocationSettings,
    }),
  ),
);
const SkillSyncMethodSettings = lazy(() =>
  import("@/components/settings/SkillSyncMethodSettings").then((module) => ({
    default: module.SkillSyncMethodSettings,
  })),
);
const TerminalSettings = lazy(() =>
  import("@/components/settings/TerminalSettings").then((module) => ({
    default: module.TerminalSettings,
  })),
);
const WebdavSyncSection = lazy(() =>
  import("@/components/settings/WebdavSyncSection").then((module) => ({
    default: module.WebdavSyncSection,
  })),
);
const WindowSettings = lazy(() =>
  import("@/components/settings/WindowSettings").then((module) => ({
    default: module.WindowSettings,
  })),
);
const AboutSection = lazy(() =>
  import("@/components/settings/AboutSection").then((module) => ({
    default: module.AboutSection,
  })),
);
const ModelTestConfigPanel = lazy(() =>
  import("@/components/usage/ModelTestConfigPanel").then((module) => ({
    default: module.ModelTestConfigPanel,
  })),
);
const UsageDashboard = lazy(() =>
  import("@/components/usage/UsageDashboard").then((module) => ({
    default: module.UsageDashboard,
  })),
);
const LogConfigPanel = lazy(() =>
  import("@/components/settings/LogConfigPanel").then((module) => ({
    default: module.LogConfigPanel,
  })),
);
const AuthCenterPanel = lazy(() =>
  import("@/components/settings/AuthCenterPanel").then((module) => ({
    default: module.AuthCenterPanel,
  })),
);

interface SettingsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onImportSuccess?: () => void | Promise<void>;
  defaultTab?: string;
}

function SettingsPanelFallback() {
  return (
    <div className="flex min-h-28 items-center justify-center rounded-lg border border-border/50 bg-muted/20">
      <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
    </div>
  );
}

export function SettingsPage({
  open,
  onOpenChange,
  onImportSuccess,
  defaultTab = "general",
}: SettingsDialogProps) {
  const { t } = useTranslation();
  const profile = getBakedProfile();
  const localSettingsEnabled = isCapabilityGroupEnabled(
    "local-env-helpers",
    profile,
  );
  const desktopHelpersEnabled = isCapabilityGroupEnabled(
    "desktop-helpers",
    profile,
  );
  const skillsEnabled = isCapabilityGroupEnabled("skills", profile);
  const authCenterEnabled = isCapabilityGroupEnabled(
    "third-party-local-tools",
    profile,
  );
  const {
    settings,
    isLoading,
    isSaving,
    isPortable,
    appConfigDir,
    resolvedDirs,
    updateSettings,
    updateDirectory,
    updateAppConfigDir,
    browseDirectory,
    browseAppConfigDir,
    resetDirectory,
    resetAppConfigDir,
    saveSettings,
    autoSaveSettings,
    requiresRestart,
    acknowledgeRestart,
  } = useSettings({ localSettingsEnabled });

  const {
    importMode,
    selectedFile,
    status: importStatus,
    errorMessage,
    backupId,
    isImporting,
    isExporting,
    selectImportFile,
    setUploadFile,
    importConfig,
    exportConfig,
    clearSelection,
    resetStatus,
  } = useImportExport({ onImportSuccess });

  const { data: installedSkills } = useInstalledSkills({
    enabled: skillsEnabled,
  });

  const [activeTab, setActiveTab] = useState<string>("general");
  const [showRestartPrompt, setShowRestartPrompt] = useState(false);

  useEffect(() => {
    if (open) {
      setActiveTab(
        defaultTab === "auth" && !authCenterEnabled ? "general" : defaultTab,
      );
      resetStatus();
    }
  }, [open, resetStatus, defaultTab, authCenterEnabled]);

  useEffect(() => {
    if (activeTab === "auth" && !authCenterEnabled) {
      setActiveTab("general");
    }
  }, [activeTab, authCenterEnabled]);

  useEffect(() => {
    if (requiresRestart) {
      setShowRestartPrompt(true);
    }
  }, [requiresRestart]);

  const closeAfterSave = useCallback(() => {
    // 保存成功后关闭：不再重置语言，避免需要“保存两次”才生效
    acknowledgeRestart();
    clearSelection();
    resetStatus();
    onOpenChange(false);
  }, [acknowledgeRestart, clearSelection, onOpenChange, resetStatus]);

  const handleSave = useCallback(async () => {
    try {
      const result = await saveSettings(undefined, { silent: false });
      if (!result) return;
      if (result.requiresRestart) {
        setShowRestartPrompt(true);
        return;
      }
      closeAfterSave();
    } catch (error) {
      console.error("[SettingsPage] Failed to save settings", error);
    }
  }, [closeAfterSave, saveSettings]);

  const handleRestartLater = useCallback(() => {
    setShowRestartPrompt(false);
    closeAfterSave();
  }, [closeAfterSave]);

  const handleRestartNow = useCallback(async () => {
    setShowRestartPrompt(false);
    if (import.meta.env.DEV) {
      toast.success(t("settings.devModeRestartHint"), { closeButton: true });
      closeAfterSave();
      return;
    }

    try {
      await settingsApi.restart();
    } catch (error) {
      console.error("[SettingsPage] Failed to restart app", error);
      toast.error(t("settings.restartFailed"));
    } finally {
      closeAfterSave();
    }
  }, [closeAfterSave, t]);

  // 通用设置即时保存（无需手动点击）
  // 使用 autoSaveSettings 避免误触发系统 API（开机自启、Claude 插件等）
  const handleAutoSave = useCallback(
    async (updates: Partial<SettingsFormState>) => {
      if (!settings) return;
      updateSettings(updates);
      try {
        await autoSaveSettings(updates);
      } catch (error) {
        console.error("[SettingsPage] Failed to autosave settings", error);
        toast.error(
          t("settings.saveFailedGeneric", {
            defaultValue: "保存失败，请重试",
          }),
        );
      }
    },
    [autoSaveSettings, settings, t, updateSettings],
  );

  const isBusy = useMemo(() => isLoading && !settings, [isLoading, settings]);

  return (
    <div className="flex flex-col h-full overflow-hidden px-6">
      {isBusy ? (
        <div className="flex flex-1 items-center justify-center">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : (
        <Tabs
          value={activeTab}
          onValueChange={setActiveTab}
          className="flex flex-col h-full"
        >
          <TabsList
            className={`grid w-full ${
              authCenterEnabled ? "grid-cols-6" : "grid-cols-5"
            } mb-6 glass rounded-lg`}
          >
            <TabsTrigger value="general">
              {t("settings.tabGeneral")}
            </TabsTrigger>
            <TabsTrigger value="proxy">{t("settings.tabProxy")}</TabsTrigger>
            {authCenterEnabled && (
              <TabsTrigger value="auth">
                {t("settings.tabAuth", { defaultValue: "认证" })}
              </TabsTrigger>
            )}
            <TabsTrigger value="advanced">
              {t("settings.tabAdvanced")}
            </TabsTrigger>
            <TabsTrigger value="usage">{t("usage.title")}</TabsTrigger>
            <TabsTrigger value="about">{t("common.about")}</TabsTrigger>
          </TabsList>

          <div className="flex-1 min-h-0 flex flex-col">
            <div className="flex-1 overflow-y-auto overflow-x-hidden pr-2">
              <TabsContent value="general" className="space-y-6 mt-0">
                {settings ? (
                  <div className="space-y-6 animate-fade-in">
                    <LanguageSettings
                      value={settings.language}
                      onChange={(lang) => handleAutoSave({ language: lang })}
                    />
                    <ThemeSettings />
                    <AppVisibilitySettings
                      settings={settings}
                      onChange={handleAutoSave}
                    />
                    {skillsEnabled && (
                      <>
                        <Suspense fallback={<SettingsPanelFallback />}>
                          <SkillStorageLocationSettings
                            value={
                              settings.skillStorageLocation ?? "cc_switch"
                            }
                            installedCount={installedSkills?.length ?? 0}
                            onMigrated={(location) =>
                              updateSettings({ skillStorageLocation: location })
                            }
                          />
                          <SkillSyncMethodSettings
                            value={settings.skillSyncMethod ?? "auto"}
                            onChange={(method) =>
                              handleAutoSave({ skillSyncMethod: method })
                            }
                          />
                        </Suspense>
                      </>
                    )}
                    {desktopHelpersEnabled && (
                      <Suspense fallback={<SettingsPanelFallback />}>
                        <WindowSettings
                          settings={settings}
                          onChange={handleAutoSave}
                        />
                      </Suspense>
                    )}
                    {localSettingsEnabled && (
                      <Suspense fallback={<SettingsPanelFallback />}>
                        <TerminalSettings
                          value={settings.preferredTerminal}
                          onChange={(terminal) =>
                            handleAutoSave({ preferredTerminal: terminal })
                          }
                        />
                      </Suspense>
                    )}
                  </div>
                ) : null}
              </TabsContent>

              <TabsContent value="proxy" className="space-y-6 mt-0 pb-4">
                {settings ? (
                  <Suspense fallback={<SettingsPanelFallback />}>
                    <ProxyTabContent
                      settings={settings}
                      onAutoSave={handleAutoSave}
                    />
                  </Suspense>
                ) : null}
              </TabsContent>

              {authCenterEnabled && (
                <TabsContent value="auth" className="space-y-6 mt-0 pb-4">
                  <div className="space-y-6 animate-fade-in">
                    <Suspense fallback={<SettingsPanelFallback />}>
                      <AuthCenterPanel />
                    </Suspense>
                  </div>
                </TabsContent>
              )}

              <TabsContent value="advanced" className="space-y-6 mt-0 pb-4">
                {settings ? (
                  <div className="space-y-4 animate-fade-in">
                    <Accordion
                      type="multiple"
                      defaultValue={[]}
                      className="w-full space-y-4"
                    >
                      {localSettingsEnabled && (
                        <AccordionItem
                          value="directory"
                          className="rounded-xl glass-card overflow-hidden"
                        >
                          <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                            <div className="flex items-center gap-3">
                              <FolderSearch className="h-5 w-5 text-primary" />
                              <div className="text-left">
                                <h3 className="text-base font-semibold">
                                  {t("settings.advanced.configDir.title")}
                                </h3>
                                <p className="text-sm text-muted-foreground font-normal">
                                  {t("settings.advanced.configDir.description")}
                                </p>
                              </div>
                            </div>
                          </AccordionTrigger>
                          <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                            <Suspense fallback={<SettingsPanelFallback />}>
                              <DirectorySettings
                                appConfigDir={appConfigDir}
                                resolvedDirs={resolvedDirs}
                                onAppConfigChange={updateAppConfigDir}
                                onBrowseAppConfig={browseAppConfigDir}
                                onResetAppConfig={resetAppConfigDir}
                                claudeDir={settings.claudeConfigDir}
                                codexDir={settings.codexConfigDir}
                                geminiDir={settings.geminiConfigDir}
                                opencodeDir={settings.opencodeConfigDir}
                                openclawDir={settings.openclawConfigDir}
                                hermesDir={settings.hermesConfigDir}
                                onDirectoryChange={updateDirectory}
                                onBrowseDirectory={browseDirectory}
                                onResetDirectory={resetDirectory}
                              />
                            </Suspense>
                          </AccordionContent>
                        </AccordionItem>
                      )}

                      <AccordionItem
                        value="data"
                        className="rounded-xl glass-card overflow-hidden"
                      >
                        <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                          <div className="flex items-center gap-3">
                            <Database className="h-5 w-5 text-blue-500" />
                            <div className="text-left">
                              <h3 className="text-base font-semibold">
                                {t("settings.advanced.data.title")}
                              </h3>
                              <p className="text-sm text-muted-foreground font-normal">
                                {t("settings.advanced.data.description")}
                              </p>
                            </div>
                          </div>
                        </AccordionTrigger>
                        <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                          <ImportExportSection
                            importMode={importMode}
                            status={importStatus}
                            selectedFile={selectedFile}
                            errorMessage={errorMessage}
                            backupId={backupId}
                            isImporting={isImporting}
                            isExporting={isExporting}
                            onSelectFile={selectImportFile}
                            onSelectUploadFile={setUploadFile}
                            onImport={importConfig}
                            onExport={exportConfig}
                            onClear={clearSelection}
                          />
                        </AccordionContent>
                      </AccordionItem>

                      <AccordionItem
                        value="backup"
                        className="rounded-xl glass-card overflow-hidden"
                      >
                        <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                          <div className="flex items-center gap-3">
                            <HardDriveDownload className="h-5 w-5 text-amber-500" />
                            <div className="text-left">
                              <h3 className="text-base font-semibold">
                                {t("settings.advanced.backup.title", {
                                  defaultValue: "Backup & Restore",
                                })}
                              </h3>
                              <p className="text-sm text-muted-foreground font-normal">
                                {t("settings.advanced.backup.description", {
                                  defaultValue:
                                    "Manage automatic backups, view and restore database snapshots",
                                })}
                              </p>
                            </div>
                          </div>
                        </AccordionTrigger>
                        <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                          <Suspense fallback={<SettingsPanelFallback />}>
                            <BackupListSection
                              backupIntervalHours={
                                settings.backupIntervalHours
                              }
                              backupRetainCount={settings.backupRetainCount}
                              onSettingsChange={(updates) =>
                                handleAutoSave(updates)
                              }
                            />
                          </Suspense>
                        </AccordionContent>
                      </AccordionItem>

                      <AccordionItem
                        value="cloudSync"
                        className="rounded-xl glass-card overflow-hidden"
                      >
                        <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                          <div className="flex items-center gap-3">
                            <Cloud className="h-5 w-5 text-blue-500" />
                            <div className="text-left">
                              <h3 className="text-base font-semibold">
                                {t("settings.advanced.cloudSync.title")}
                              </h3>
                              <p className="text-sm text-muted-foreground font-normal">
                                {t("settings.advanced.cloudSync.description")}
                              </p>
                            </div>
                          </div>
                        </AccordionTrigger>
                        <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                          <Suspense fallback={<SettingsPanelFallback />}>
                            <WebdavSyncSection
                              config={settings?.webdavSync}
                              s3Config={settings?.s3Sync}
                              settings={settings}
                              onAutoSave={handleAutoSave}
                            />
                          </Suspense>
                        </AccordionContent>
                      </AccordionItem>

                      <AccordionItem
                        value="test"
                        className="rounded-xl glass-card overflow-hidden"
                      >
                        <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                          <div className="flex items-center gap-3">
                            <FlaskConical className="h-5 w-5 text-emerald-500" />
                            <div className="text-left">
                              <h3 className="text-base font-semibold">
                                {t("settings.advanced.modelTest.title")}
                              </h3>
                              <p className="text-sm text-muted-foreground font-normal">
                                {t("settings.advanced.modelTest.description")}
                              </p>
                            </div>
                          </div>
                        </AccordionTrigger>
                        <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                          <Suspense fallback={<SettingsPanelFallback />}>
                            <ModelTestConfigPanel />
                          </Suspense>
                        </AccordionContent>
                      </AccordionItem>

                      <AccordionItem
                        value="logConfig"
                        className="rounded-xl glass-card overflow-hidden"
                      >
                        <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
                          <div className="flex items-center gap-3">
                            <ScrollText className="h-5 w-5 text-cyan-500" />
                            <div className="text-left">
                              <h3 className="text-base font-semibold">
                                {t("settings.advanced.logConfig.title")}
                              </h3>
                              <p className="text-sm text-muted-foreground font-normal">
                                {t("settings.advanced.logConfig.description")}
                              </p>
                            </div>
                          </div>
                        </AccordionTrigger>
                        <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
                          <Suspense fallback={<SettingsPanelFallback />}>
                            <LogConfigPanel />
                          </Suspense>
                        </AccordionContent>
                      </AccordionItem>
                    </Accordion>
                  </div>
                ) : null}
              </TabsContent>

              <TabsContent value="about" className="mt-0">
                <Suspense fallback={<SettingsPanelFallback />}>
                  <AboutSection
                    isPortable={isPortable}
                    localEnvCheckEnabled={localSettingsEnabled}
                  />
                </Suspense>
              </TabsContent>

              <TabsContent value="usage" className="mt-0">
                <Suspense fallback={<SettingsPanelFallback />}>
                  <UsageDashboard />
                </Suspense>
              </TabsContent>
            </div>

            {activeTab === "advanced" && settings && (
              <div
                className="flex-shrink-0 pt-4 border-t border-border-default"
                style={{ backgroundColor: "hsl(var(--background))" }}
              >
                <div className="px-6 flex items-center justify-end gap-3">
                  <Button onClick={handleSave} disabled={isSaving}>
                    {isSaving ? (
                      <span className="inline-flex items-center gap-2">
                        <Loader2 className="h-4 w-4 animate-spin" />
                        {t("settings.saving")}
                      </span>
                    ) : (
                      <>
                        <Save className="mr-2 h-4 w-4" />
                        {t("common.save")}
                      </>
                    )}
                  </Button>
                </div>
              </div>
            )}
          </div>
        </Tabs>
      )}

      <Dialog
        open={showRestartPrompt}
        onOpenChange={(open) => !open && handleRestartLater()}
      >
        <DialogContent zIndex="alert" className="max-w-md glass border-border">
          <DialogHeader>
            <DialogTitle>{t("settings.restartRequired")}</DialogTitle>
          </DialogHeader>
          <div className="px-6">
            <p className="text-sm text-muted-foreground">
              {t("settings.restartRequiredMessage")}
            </p>
          </div>
          <DialogFooter>
            <Button
              variant="ghost"
              onClick={handleRestartLater}
              className="hover:bg-muted/50"
            >
              {t("settings.restartLater")}
            </Button>
            <Button
              onClick={handleRestartNow}
              className="bg-primary hover:bg-primary/90"
            >
              {t("settings.restartNow")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
