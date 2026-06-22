import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import i18n from "i18next";
import type { PropsWithChildren } from "react";
import { describe, expect, it, vi } from "vitest";
import { UsageDashboard } from "@/components/usage/UsageDashboard";
import zh from "@/i18n/locales/zh.json";

vi.mock("@/lib/api/usage", () => ({
  usageApi: {
    getUsageSummary: vi.fn().mockResolvedValue({
      totalRequests: 0,
      totalCost: 0,
      totalInputTokens: 0,
      totalOutputTokens: 0,
      totalCacheCreationTokens: 0,
      totalCacheReadTokens: 0,
      successRate: 0,
      cacheHitRate: 0,
    }),
    getUsageSummaryByApp: vi.fn().mockResolvedValue([]),
    getUsageTrends: vi.fn().mockResolvedValue([]),
    getProviderStats: vi.fn().mockResolvedValue([]),
    getModelStats: vi.fn().mockResolvedValue([]),
    getRequestLogs: vi.fn().mockResolvedValue({ data: [], total: 0 }),
    getDataSourceBreakdown: vi.fn().mockResolvedValue([]),
  },
}));

const dataSourceBarProps = vi.fn();
const usageHeroProps = vi.fn();
const usageSummaryCardsProps = vi.fn();
const usageTrendChartProps = vi.fn();
const requestLogTableProps = vi.fn();
const providerStatsTableProps = vi.fn();
const modelStatsTableProps = vi.fn();

vi.mock("@/components/usage/UsageHero", () => ({
  UsageHero: (props: unknown) => {
    usageHeroProps(props);
    return <div data-testid="usage-hero" />;
  },
}));

vi.mock("@/components/usage/UsageSummaryCards", () => ({
  UsageSummaryCards: (props: unknown) => {
    usageSummaryCardsProps(props);
    return <div data-testid="usage-summary-cards" />;
  },
}));

vi.mock("@/components/usage/UsageTrendChart", () => ({
  UsageTrendChart: (props: unknown) => {
    usageTrendChartProps(props);
    return <div data-testid="usage-trend-chart" />;
  },
}));

vi.mock("@/components/usage/RequestLogTable", () => ({
  RequestLogTable: (props: unknown) => {
    requestLogTableProps(props);
    return <div data-testid="request-log-table" />;
  },
}));

vi.mock("@/components/usage/ProviderStatsTable", () => ({
  ProviderStatsTable: (props: unknown) => {
    providerStatsTableProps(props);
    return <div data-testid="provider-stats-table" />;
  },
}));

vi.mock("@/components/usage/ModelStatsTable", () => ({
  ModelStatsTable: (props: unknown) => {
    modelStatsTableProps(props);
    return <div data-testid="model-stats-table" />;
  },
}));

vi.mock("@/components/usage/DataSourceBar", () => ({
  DataSourceBar: (props: unknown) => {
    dataSourceBarProps(props);
    return <div data-testid="data-source-bar" />;
  },
}));

vi.mock("@/components/usage/PricingConfigPanel", () => ({
  PricingConfigPanel: () => <div data-testid="pricing-config-panel" />,
}));

vi.mock("@/components/ui/tabs", () => ({
  Tabs: ({ children }: PropsWithChildren) => <div>{children}</div>,
  TabsList: ({ children }: PropsWithChildren) => <div>{children}</div>,
  TabsTrigger: ({ children }: PropsWithChildren) => <button>{children}</button>,
  TabsContent: ({ children }: PropsWithChildren) => <div>{children}</div>,
}));

function renderDashboard() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <UsageDashboard />
    </QueryClientProvider>,
  );
}

describe("UsageDashboard", () => {
  beforeEach(() => {
    i18n.addResourceBundle("zh", "translation", zh, true, true);
    void i18n.changeLanguage("zh");
    vi.clearAllMocks();
  });

  it("renders localized toolbar labels and defaults to a 5s refresh interval", () => {
    renderDashboard();

    expect(
      screen.getByRole("combobox", { name: "筛选来源" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("combobox", { name: "筛选模型" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("combobox", { name: "刷新间隔" }),
    ).toBeInTheDocument();
    expect(screen.queryByText(/usage\./)).not.toBeInTheDocument();
    expect(dataSourceBarProps).toHaveBeenCalledWith(
      expect.objectContaining({ refreshIntervalMs: 5000 }),
    );
  });

  it("offers Off and 5s options in the refresh interval menu", async () => {
    const user = userEvent.setup();
    renderDashboard();

    await user.click(screen.getByRole("combobox", { name: "刷新间隔" }));

    expect(await screen.findByRole("option", { name: "关闭" })).toBeVisible();
    expect(screen.getByRole("option", { name: "5s" })).toBeVisible();
  });

  it("passes the default 5s refresh interval to all usage panels", () => {
    renderDashboard();

    for (const spy of [
      dataSourceBarProps,
      usageHeroProps,
      usageSummaryCardsProps,
      usageTrendChartProps,
      requestLogTableProps,
      providerStatsTableProps,
      modelStatsTableProps,
    ]) {
      expect(spy).toHaveBeenCalledWith(
        expect.objectContaining({ refreshIntervalMs: 5000 }),
      );
    }
  });
});
