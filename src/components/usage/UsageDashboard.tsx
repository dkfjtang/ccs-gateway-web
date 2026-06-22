import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { UsageHero } from "./UsageHero";
import { UsageSummaryCards } from "./UsageSummaryCards";
import { UsageTrendChart } from "./UsageTrendChart";
import { RequestLogTable } from "./RequestLogTable";
import { ProviderStatsTable } from "./ProviderStatsTable";
import { ModelStatsTable } from "./ModelStatsTable";
import { DataSourceBar } from "./DataSourceBar";
import {
  KNOWN_APP_TYPES,
  type AppType,
  type AppTypeFilter,
  type UsageRangeSelection,
} from "@/types/usage";
import { motion } from "framer-motion";
import {
  BarChart3,
  ListFilter,
  Activity,
  RefreshCw,
  Coins,
  LayoutGrid,
} from "lucide-react";
import { ProviderIcon } from "@/components/ProviderIcon";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useQueryClient } from "@tanstack/react-query";
import { usageKeys, useModelStats, useProviderStats } from "@/lib/query/usage";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { PricingConfigPanel } from "@/components/usage/PricingConfigPanel";
import { cn } from "@/lib/utils";
import { getLocaleFromLanguage } from "./format";
import { getUsageRangePresetLabel, resolveUsageRange } from "@/lib/usageRange";
import { UsageDateRangePicker } from "./UsageDateRangePicker";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const APP_FILTER_OPTIONS: AppTypeFilter[] = ["all", ...KNOWN_APP_TYPES];
const DEFAULT_REFRESH_INTERVAL_MS = 5000;
const REFRESH_INTERVAL_OPTIONS_MS = [0, 5000, 10000, 30000, 60000] as const;
const APP_FILTER_ICON: Record<AppType, string> = {
  claude: "claude",
  codex: "openai",
  gemini: "gemini",
  opencode: "opencode",
};
const DYNAMIC_OPTION_PREFIX = "v:";
const encodeOptionValue = (name: string) => `${DYNAMIC_OPTION_PREFIX}${name}`;
const decodeOptionValue = (value: string) =>
  value === "all" ? undefined : value.slice(DYNAMIC_OPTION_PREFIX.length);

export function UsageDashboard() {
  const { t, i18n } = useTranslation();
  const queryClient = useQueryClient();
  const [range, setRange] = useState<UsageRangeSelection>({ preset: "today" });
  const [appType, setAppType] = useState<AppTypeFilter>("all");
  const [providerName, setProviderName] = useState<string | undefined>(
    undefined,
  );
  const [model, setModel] = useState<string | undefined>(undefined);
  const [refreshIntervalMs, setRefreshIntervalMs] = useState(
    DEFAULT_REFRESH_INTERVAL_MS,
  );

  const changeAppType = (next: AppTypeFilter) => {
    setAppType(next);
    if (next !== appType) {
      setProviderName(undefined);
      setModel(undefined);
    }
  };

  const changeProviderName = (next: string | undefined) => {
    setProviderName(next);
    if (next !== providerName) {
      setModel(undefined);
    }
  };

  const changeRefreshInterval = (next: number) => {
    setRefreshIntervalMs(next);
    queryClient.invalidateQueries({ queryKey: usageKeys.all });
  };

  const language = i18n.resolvedLanguage || i18n.language || "en";
  const locale = getLocaleFromLanguage(language);
  const resolvedRange = useMemo(() => resolveUsageRange(range), [range]);
  const rangeLabel = useMemo(() => {
    if (range.preset !== "custom") {
      return getUsageRangePresetLabel(range.preset, t);
    }

    return `${new Date(resolvedRange.startDate * 1000).toLocaleString(locale)} - ${new Date(
      resolvedRange.endDate * 1000,
    ).toLocaleString(locale)}`;
  }, [locale, range, resolvedRange.endDate, resolvedRange.startDate, t]);

  const optionsRefetch = {
    refetchInterval:
      refreshIntervalMs > 0 ? refreshIntervalMs : (false as const),
  };
  const { data: providerOptionsData } = useProviderStats(
    range,
    { appType },
    optionsRefetch,
  );
  const { data: modelOptionsData } = useModelStats(
    range,
    { appType, providerName },
    optionsRefetch,
  );

  const providerOptions = useMemo(() => {
    const names = new Set<string>();
    for (const stat of providerOptionsData ?? []) {
      names.add(stat.providerName);
    }
    if (providerName) names.add(providerName);
    return Array.from(names);
  }, [providerOptionsData, providerName]);

  const modelOptions = useMemo(() => {
    const names = new Set<string>();
    for (const stat of modelOptionsData ?? []) {
      names.add(stat.model);
    }
    if (model) names.add(model);
    return Array.from(names);
  }, [modelOptionsData, model]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="space-y-8 pb-8"
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex flex-col gap-1">
            <h2 className="text-2xl font-bold">{t("usage.title")}</h2>
            <p className="text-sm text-muted-foreground">
              {t("usage.subtitle")}
            </p>
          </div>
        </div>

        <div className="rounded-xl border border-border/50 bg-card/40 backdrop-blur-sm p-4">
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex items-center p-1 bg-muted/30 rounded-lg border border-border/50">
              {APP_FILTER_OPTIONS.map((type) => {
                const label = t(`usage.appFilter.${type}`);
                return (
                  <button
                    key={type}
                    type="button"
                    onClick={() => changeAppType(type)}
                    title={label}
                    aria-label={label}
                    className={cn(
                      "flex h-8 items-center justify-center px-2.5 rounded-md transition-all",
                      appType === type
                        ? "bg-background text-primary shadow-sm"
                        : "text-muted-foreground hover:text-foreground hover:bg-muted/50",
                    )}
                  >
                    {type === "all" ? (
                      <LayoutGrid className="h-4 w-4" />
                    ) : (
                      <ProviderIcon
                        icon={APP_FILTER_ICON[type]}
                        name={label}
                        size={16}
                      />
                    )}
                  </button>
                );
              })}
            </div>

            <Select
              value={
                providerName != null ? encodeOptionValue(providerName) : "all"
              }
              onValueChange={(v) => changeProviderName(decodeOptionValue(v))}
            >
              <SelectTrigger
                className="h-9 w-[120px] bg-background text-xs focus:border-border-default [&>span]:min-w-0 [&>span]:truncate"
                title={providerName ?? t("usage.filterBySource")}
              >
                <SelectValue placeholder={t("usage.filterBySource")} />
              </SelectTrigger>
              <SelectContent className="max-w-[280px]">
                <SelectItem value="all">{t("usage.allSources")}</SelectItem>
                {providerOptions.map((name) => (
                  <SelectItem
                    key={name}
                    value={encodeOptionValue(name)}
                    title={name}
                    className="[&>span]:min-w-0 [&>span]:truncate"
                  >
                    {name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <Select
              value={model != null ? encodeOptionValue(model) : "all"}
              onValueChange={(v) => setModel(decodeOptionValue(v))}
            >
              <SelectTrigger
                className="h-9 w-[120px] bg-background text-xs focus:border-border-default [&>span]:min-w-0 [&>span]:truncate"
                title={model ?? t("usage.filterByModel")}
              >
                <SelectValue placeholder={t("usage.filterByModel")} />
              </SelectTrigger>
              <SelectContent className="max-w-[280px]">
                <SelectItem value="all">{t("usage.allModels")}</SelectItem>
                {modelOptions.map((name) => (
                  <SelectItem
                    key={name}
                    value={encodeOptionValue(name)}
                    title={name}
                    className="[&>span]:min-w-0 [&>span]:truncate"
                  >
                    {name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>

            <div className="ml-auto flex items-center gap-2">
              <Select
                value={String(refreshIntervalMs)}
                onValueChange={(v) => changeRefreshInterval(Number(v))}
              >
                <SelectTrigger
                  className="h-9 w-[100px] bg-background text-xs focus:border-border-default"
                  title={t("usage.refreshInterval")}
                  aria-label={t("usage.refreshInterval")}
                >
                  <span className="flex items-center gap-2">
                    <RefreshCw className="h-3.5 w-3.5 shrink-0" />
                    <SelectValue />
                  </span>
                </SelectTrigger>
                <SelectContent>
                  {REFRESH_INTERVAL_OPTIONS_MS.map((ms) => (
                    <SelectItem key={ms} value={String(ms)}>
                      {ms > 0 ? `${ms / 1000}s` : t("usage.refreshOff")}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>

              <UsageDateRangePicker
                selection={range}
                triggerLabel={rangeLabel}
                onApply={(nextRange) => setRange(nextRange)}
              />
            </div>
          </div>
        </div>
      </div>

      <DataSourceBar refreshIntervalMs={refreshIntervalMs} />

      <UsageHero
        range={range}
        appType={appType === "all" ? undefined : appType}
        providerName={providerName}
        model={model}
        refreshIntervalMs={refreshIntervalMs}
      />

      <UsageSummaryCards
        range={range}
        appType={appType}
        providerName={providerName}
        model={model}
        refreshIntervalMs={refreshIntervalMs}
      />

      <UsageTrendChart
        range={range}
        rangeLabel={rangeLabel}
        appType={appType}
        providerName={providerName}
        model={model}
        refreshIntervalMs={refreshIntervalMs}
      />

      <div className="space-y-4">
        <Tabs defaultValue="logs" className="w-full">
          <div className="flex items-center justify-between mb-4">
            <TabsList className="bg-muted/50">
              <TabsTrigger value="logs" className="gap-2">
                <ListFilter className="h-4 w-4" />
                {t("usage.requestLogs")}
              </TabsTrigger>
              <TabsTrigger value="providers" className="gap-2">
                <Activity className="h-4 w-4" />
                {t("usage.providerStats")}
              </TabsTrigger>
              <TabsTrigger value="models" className="gap-2">
                <BarChart3 className="h-4 w-4" />
                {t("usage.modelStats")}
              </TabsTrigger>
            </TabsList>
          </div>

          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
          >
            <TabsContent value="logs" className="mt-0">
              <RequestLogTable
                range={range}
                rangeLabel={rangeLabel}
                appType={appType}
                providerName={providerName}
                model={model}
                refreshIntervalMs={refreshIntervalMs}
                onRangeChange={setRange}
              />
            </TabsContent>

            <TabsContent value="providers" className="mt-0">
              <ProviderStatsTable
                range={range}
                appType={appType}
                providerName={providerName}
                model={model}
                refreshIntervalMs={refreshIntervalMs}
              />
            </TabsContent>

            <TabsContent value="models" className="mt-0">
              <ModelStatsTable
                range={range}
                appType={appType}
                providerName={providerName}
                model={model}
                refreshIntervalMs={refreshIntervalMs}
              />
            </TabsContent>
          </motion.div>
        </Tabs>
      </div>

      <Accordion type="multiple" defaultValue={[]} className="w-full space-y-4">
        <AccordionItem
          value="pricing"
          className="rounded-xl glass-card overflow-hidden"
        >
          <AccordionTrigger className="px-6 py-4 hover:no-underline hover:bg-muted/50 data-[state=open]:bg-muted/50">
            <div className="flex items-center gap-3">
              <Coins className="h-5 w-5 text-yellow-500" />
              <div className="text-left">
                <h3 className="text-base font-semibold">
                  {t("settings.advanced.pricing.title")}
                </h3>
                <p className="text-sm text-muted-foreground font-normal">
                  {t("settings.advanced.pricing.description")}
                </p>
              </div>
            </div>
          </AccordionTrigger>
          <AccordionContent className="px-6 pb-6 pt-4 border-t border-border/50">
            <PricingConfigPanel />
          </AccordionContent>
        </AccordionItem>
      </Accordion>
    </motion.div>
  );
}
