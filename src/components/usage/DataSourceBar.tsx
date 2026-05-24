import { useTranslation } from "react-i18next";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { usageApi } from "@/lib/api/usage";
import { usageKeys } from "@/lib/query/usage";
import { Database, FileText, RefreshCw, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { toast } from "sonner";

interface DataSourceBarProps {
  refreshIntervalMs: number;
}

const DATA_SOURCE_ICONS: Record<string, React.ReactNode> = {
  proxy: <Database className="h-3.5 w-3.5" />,
  session_log: <FileText className="h-3.5 w-3.5" />,
  codex_db: <Database className="h-3.5 w-3.5" />,
  codex_session: <FileText className="h-3.5 w-3.5" />,
  gemini_session: <FileText className="h-3.5 w-3.5" />,
};

export function DataSourceBar({ refreshIntervalMs }: DataSourceBarProps) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [syncing, setSyncing] = useState(false);

  const { data: sources = [] } = useQuery({
    queryKey: [...usageKeys.all, "data-sources"],
    queryFn: usageApi.getDataSourceBreakdown,
    refetchInterval: refreshIntervalMs > 0 ? refreshIntervalMs : false,
    refetchIntervalInBackground: false,
  });

  const handleSync = async () => {
    setSyncing(true);
    try {
      const result = await usageApi.syncSessionUsage();
      console.info("[DataSourceBar] Session sync result", result);
      if (result.errors.length > 0) {
        console.warn("[DataSourceBar] Session sync errors", result.errors);
      }

      queryClient.invalidateQueries({ queryKey: usageKeys.all });

      if (result.imported > 0) {
        toast.success(
          t("usage.sessionSync.imported", {
            count: result.imported,
            defaultValue: "Imported {{count}} records from session logs",
          }),
        );
      } else if (result.errors.length > 0) {
        toast.error(
          t("usage.sessionSync.completedWithErrors", {
            filesScanned: result.filesScanned,
            skipped: result.skipped,
            errors: result.errors.length,
            message: result.errors[0],
            defaultValue:
              "Scanned {{filesScanned}} files, skipped {{skipped}} records, {{errors}} errors: {{message}}",
          }),
        );
      } else if (result.filesScanned > 0) {
        toast.info(
          t("usage.sessionSync.noImport", {
            filesScanned: result.filesScanned,
            skipped: result.skipped,
            defaultValue:
              "Scanned {{filesScanned}} files, no new records imported, skipped {{skipped}} records",
          }),
        );
      } else {
        toast.info(
          t("usage.sessionSync.noFiles", {
            defaultValue: "No session log files found",
          }),
        );
      }
    } catch (error) {
      console.error("[DataSourceBar] Session sync failed", error);
      toast.error(
        t("usage.sessionSync.failed", {
          defaultValue: "Session sync failed",
        }),
      );
    } finally {
      setSyncing(false);
    }
  };

  const hasNonProxy = sources.some((s) => s.dataSource !== "proxy");

  return (
    <div className="flex items-center gap-3 text-xs text-muted-foreground bg-muted/30 rounded-lg px-4 py-2">
      <span className="font-medium text-foreground/70">
        {t("usage.dataSources", { defaultValue: "Data Sources" })}:
      </span>
      <div className="flex items-center gap-3 flex-wrap">
        {sources.length > 0 ? (
          sources.map((source) => (
            <div
              key={source.dataSource}
              className="flex items-center gap-1.5 bg-background/50 rounded-md px-2 py-1"
            >
              {DATA_SOURCE_ICONS[source.dataSource] ?? (
                <Database className="h-3.5 w-3.5" />
              )}
              <span>
                {t(`usage.dataSource.${source.dataSource}`, {
                  defaultValue: source.dataSource,
                })}
              </span>
              <span className="font-mono font-medium text-foreground/80">
                {source.requestCount.toLocaleString()}
              </span>
            </div>
          ))
        ) : (
          <span className="text-muted-foreground">
            {t("usage.noData", { defaultValue: "暂无数据" })}
          </span>
        )}
      </div>

      <div className="ml-auto">
        <Button
          variant="ghost"
          size="sm"
          className="h-7 px-2 text-xs"
          onClick={handleSync}
          disabled={syncing}
          title={t("usage.sessionSync.trigger", {
            defaultValue: "Sync session logs",
          })}
        >
          {syncing ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <RefreshCw className="h-3.5 w-3.5" />
          )}
          <span className="ml-1">
            {hasNonProxy
              ? t("usage.sessionSync.resync", { defaultValue: "Sync" })
              : t("usage.sessionSync.import", {
                  defaultValue: "Import Sessions",
                })}
          </span>
        </Button>
      </div>
    </div>
  );
}
