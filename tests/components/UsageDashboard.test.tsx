import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";
import { describe, expect, it, vi } from "vitest";
import { UsageDashboard } from "@/components/usage/UsageDashboard";

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
    vi.clearAllMocks();
  });

  it("defaults to a 5s refresh interval", () => {
    renderDashboard();

    expect(screen.getByRole("button", { name: /5s/ })).toBeInTheDocument();
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
