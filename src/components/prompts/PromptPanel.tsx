import React, { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { FileText } from "lucide-react";
import { toast } from "sonner";
import { promptsApi, type AppId } from "@/lib/api";
import { usePromptActions } from "@/hooks/usePromptActions";
import PromptListItem from "./PromptListItem";
import PromptFormPanel from "./PromptFormPanel";
import { ConfirmDialog } from "../ConfirmDialog";

const CAVEMAN_PROFILE_IDS = [
  "caveman-lite",
  "caveman-full",
  "caveman-ultra",
] as const;

type CavemanProfileId = (typeof CAVEMAN_PROFILE_IDS)[number];
type CavemanProfile = "lite" | "full" | "ultra";

const isCavemanProfileId = (id: string): id is CavemanProfileId =>
  CAVEMAN_PROFILE_IDS.includes(id as CavemanProfileId);

interface PromptPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  appId: AppId;
}

export interface PromptPanelHandle {
  openAdd: () => void;
}

const PromptPanel = React.forwardRef<PromptPanelHandle, PromptPanelProps>(
  ({ open, appId }, ref) => {
    const { t } = useTranslation();
    const [isFormOpen, setIsFormOpen] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [creatingCavemanProfile, setCreatingCavemanProfile] =
      useState<CavemanProfile | null>(null);
    const [confirmDialog, setConfirmDialog] = useState<{
      isOpen: boolean;
      titleKey: string;
      messageKey: string;
      messageParams?: Record<string, unknown>;
      onConfirm: () => void;
    } | null>(null);

    const {
      prompts,
      loading,
      reload,
      savePrompt,
      deletePrompt,
      toggleEnabled,
    } = usePromptActions(appId);

    useEffect(() => {
      if (open) reload();
    }, [open, reload]);

    // Listen for prompt import events from deep link
    useEffect(() => {
      const handlePromptImported = (event: Event) => {
        const customEvent = event as CustomEvent;
        // Reload if the import is for this app
        if (customEvent.detail?.app === appId) {
          reload();
        }
      };

      window.addEventListener("prompt-imported", handlePromptImported);
      return () => {
        window.removeEventListener("prompt-imported", handlePromptImported);
      };
    }, [appId, reload]);

    const handleAdd = () => {
      setEditingId(null);
      setIsFormOpen(true);
    };

    const activateCavemanProfile = async (profile: CavemanProfile) => {
      const id = `caveman-${profile}`;
      if (creatingCavemanProfile) return;

      setCreatingCavemanProfile(profile);
      try {
        if (!prompts[id]) {
          await promptsApi.createCavemanStyleProfile(appId, profile);
        }
        await promptsApi.enablePrompt(appId, id);
        await reload();
        toast.success(t("prompts.caveman.enableSuccess"), {
          closeButton: true,
        });
      } catch (error) {
        console.error("Failed to create Caveman style profile:", error);
        toast.error(t("prompts.caveman.enableFailed"));
      } finally {
        setCreatingCavemanProfile(null);
      }
    };

    const turnOffCaveman = async () => {
      const active = Object.values(prompts).find(
        (prompt) => prompt.enabled && isCavemanProfileId(prompt.id),
      );
      if (!active || creatingCavemanProfile) return;
      try {
        await toggleEnabled(active.id, false);
      } catch (error) {
        console.error("Failed to turn off Caveman style profile:", error);
      }
    };

    React.useImperativeHandle(ref, () => ({
      openAdd: handleAdd,
    }));

    const handleEdit = (id: string) => {
      setEditingId(id);
      setIsFormOpen(true);
    };

    const handleDelete = (id: string) => {
      const prompt = prompts[id];
      setConfirmDialog({
        isOpen: true,
        titleKey: "prompts.confirm.deleteTitle",
        messageKey: "prompts.confirm.deleteMessage",
        messageParams: { name: prompt?.name },
        onConfirm: async () => {
          try {
            await deletePrompt(id);
            setConfirmDialog(null);
          } catch (e) {
            // Error handled by hook
          }
        },
      });
    };

    const promptEntries = useMemo(() => Object.entries(prompts), [prompts]);

    const enabledPrompt = promptEntries.find(([_, p]) => p.enabled);
    const activeCavemanProfile = promptEntries.find(
      ([id, prompt]) => isCavemanProfileId(id) && prompt.enabled,
    );
    const cavemanProfiles = (["lite", "full", "ultra"] as const).map(
      (profile) => ({
        profile,
        labelKey: `prompts.caveman.create${profile[0].toUpperCase()}${profile.slice(1)}`,
        exists: Boolean(prompts[`caveman-${profile}`]),
        active: activeCavemanProfile?.[0] === `caveman-${profile}`,
      }),
    );

    return (
      <div className="flex flex-col flex-1 min-h-0 px-6">
        <div className="flex-shrink-0 py-4 glass rounded-xl border border-white/10 mb-4 px-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="text-sm text-muted-foreground">
              {t("prompts.count", { count: promptEntries.length })} ·{" "}
              {enabledPrompt
                ? t("prompts.enabledName", { name: enabledPrompt[1].name })
                : t("prompts.noneEnabled")}
              {" · "}
              {activeCavemanProfile
                ? t("prompts.caveman.active", {
                    mode: activeCavemanProfile[1].name,
                  })
                : t("prompts.caveman.off")}
            </div>
            <div className="flex flex-wrap gap-2">
              {cavemanProfiles.map(({ profile, labelKey, exists, active }) => {
                const isCreating = creatingCavemanProfile === profile;
                return (
                  <button
                    key={profile}
                    type="button"
                    className={`rounded-md border px-2 py-1 text-xs transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
                      active
                        ? "border-emerald-500/50 bg-emerald-500/10 text-emerald-600 dark:text-emerald-300"
                        : "border-white/10 text-muted-foreground hover:text-foreground"
                    }`}
                    disabled={creatingCavemanProfile !== null}
                    onClick={() => activateCavemanProfile(profile)}
                  >
                    {active
                      ? t("prompts.caveman.enabled", { name: t(labelKey) })
                      : isCreating
                        ? t("prompts.caveman.creating", { name: t(labelKey) })
                        : exists
                          ? t("prompts.caveman.useExisting", {
                              name: t(labelKey),
                            })
                          : t(labelKey)}
                  </button>
                );
              })}
              <button
                type="button"
                className="rounded-md border border-white/10 px-2 py-1 text-xs text-muted-foreground transition-colors hover:text-foreground disabled:cursor-not-allowed disabled:opacity-60"
                disabled={!activeCavemanProfile || creatingCavemanProfile !== null}
                onClick={turnOffCaveman}
              >
                {t("prompts.caveman.turnOff")}
              </button>
            </div>
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            {t("prompts.caveman.description")}
          </p>
        </div>

        <div className="flex-1 overflow-y-auto pb-16">
          {loading ? (
            <div className="text-center py-12 text-muted-foreground">
              {t("prompts.loading")}
            </div>
          ) : promptEntries.length === 0 ? (
            <div className="text-center py-12">
              <div className="w-16 h-16 mx-auto mb-4 bg-muted rounded-full flex items-center justify-center">
                <FileText size={24} className="text-muted-foreground" />
              </div>
              <h3 className="text-lg font-medium text-foreground mb-2">
                {t("prompts.empty")}
              </h3>
              <p className="text-muted-foreground text-sm">
                {t("prompts.emptyDescription")}
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {promptEntries.map(([id, prompt]) => (
                <PromptListItem
                  key={id}
                  id={id}
                  prompt={prompt}
                  onToggle={toggleEnabled}
                  onEdit={handleEdit}
                  onDelete={handleDelete}
                />
              ))}
            </div>
          )}
        </div>

        {isFormOpen && (
          <PromptFormPanel
            appId={appId}
            editingId={editingId || undefined}
            initialData={editingId ? prompts[editingId] : undefined}
            onSave={savePrompt}
            onClose={() => setIsFormOpen(false)}
          />
        )}

        {confirmDialog && (
          <ConfirmDialog
            isOpen={confirmDialog.isOpen}
            title={t(confirmDialog.titleKey)}
            message={t(confirmDialog.messageKey, confirmDialog.messageParams)}
            onConfirm={confirmDialog.onConfirm}
            onCancel={() => setConfirmDialog(null)}
          />
        )}
      </div>
    );
  },
);

PromptPanel.displayName = "PromptPanel";

export default PromptPanel;
