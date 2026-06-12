import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Provider } from "@/types";
import { ProviderCard } from "@/components/providers/ProviderCard";

type ProviderCardTestProps = Partial<
  React.ComponentProps<typeof ProviderCard>
>;

const useUsageQueryMock = vi.fn();

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, options?: { defaultValue?: string }) =>
      options?.defaultValue ?? key,
  }),
}));

vi.mock("@/lib/query/failover", () => ({
  useProviderHealth: () => ({ data: null }),
}));

vi.mock("@/lib/query/queries", () => ({
  useUsageQuery: (...args: unknown[]) => useUsageQueryMock(...args),
}));

vi.mock("@/components/ProviderIcon", () => ({
  ProviderIcon: () => <div data-testid="provider-icon" />,
}));

vi.mock("@/components/UsageFooter", () => ({
  default: () => <div data-testid="usage-footer" />,
}));

vi.mock("@/components/SubscriptionQuotaFooter", () => ({
  default: () => <div data-testid="subscription-quota-footer" />,
}));

vi.mock("@/components/CopilotQuotaFooter", () => ({
  default: () => <div data-testid="copilot-quota-footer" />,
}));

vi.mock("@/components/CodexOauthQuotaFooter", () => ({
  default: () => <div data-testid="codex-oauth-quota-footer" />,
}));

const provider: Provider = {
  id: "provider-1",
  name: "Test Provider",
  settingsConfig: {
    env: {
      ANTHROPIC_BASE_URL: "https://example.invalid",
    },
  },
};

function renderProviderCard(overrides: ProviderCardTestProps = {}) {
  return render(
    <ProviderCard
      provider={provider}
      isCurrent={false}
      appId="claude"
      onSwitch={vi.fn()}
      onEdit={vi.fn()}
      onDelete={vi.fn()}
      onConfigureUsage={vi.fn()}
      onOpenWebsite={vi.fn()}
      onDuplicate={vi.fn()}
      onTest={vi.fn()}
      isProxyRunning={false}
      {...overrides}
    />,
  );
}

function getActionGroup() {
  const editButton = screen.getByTitle("common.edit");
  return editButton.closest("div")?.parentElement?.parentElement;
}

describe("ProviderCard", () => {
  beforeEach(() => {
    useUsageQueryMock.mockReset();
    useUsageQueryMock.mockReturnValue({ data: null });
  });

  it("keeps provider action buttons in the row and reveals them on hover or focus", () => {
    const { container } = renderProviderCard();

    const actionGroup = getActionGroup();

    expect(screen.getByTitle("provider.duplicate")).toBeInTheDocument();
    expect(screen.getByTitle("modelTest.testProvider")).toBeInTheDocument();
    expect(screen.getByTitle("provider.configureUsage")).toBeInTheDocument();
    expect(screen.getByTitle("common.delete")).toBeInTheDocument();
    expect(actionGroup).toHaveClass("opacity-0");
    expect(actionGroup).toHaveClass("pointer-events-none");

    const card = container.querySelector(".group");
    expect(card).not.toBeNull();

    fireEvent.mouseEnter(card!);
    expect(actionGroup).toHaveClass("opacity-100");
    expect(actionGroup).toHaveClass("pointer-events-auto");

    fireEvent.mouseLeave(card!);
    expect(actionGroup).toHaveClass("opacity-0");
    expect(actionGroup).toHaveClass("pointer-events-none");
  });

  it("keeps provider actions visible for the active provider row", () => {
    renderProviderCard({ isCurrent: true });

    const actionGroup = getActionGroup();

    expect(actionGroup).toHaveClass("opacity-100");
    expect(actionGroup).toHaveClass("pointer-events-auto");
  });

  it("keeps provider actions visible for additive-mode configured rows", () => {
    renderProviderCard({ appId: "opencode", isInConfig: true });

    const actionGroup = getActionGroup();

    expect(actionGroup).toHaveClass("opacity-100");
    expect(actionGroup).toHaveClass("pointer-events-auto");
  });

  it("reads usage cache without starting its own auto-refresh interval", () => {
    renderProviderCard({
      isCurrent: true,
      provider: {
        ...provider,
        meta: {
          usage_script: {
            enabled: true,
            language: "javascript",
            code: "",
            autoQueryInterval: 1,
          },
        },
      },
    });

    expect(useUsageQueryMock).toHaveBeenCalledWith("provider-1", "claude", {
      enabled: true,
      fetchOnMount: false,
    });
  });
});
