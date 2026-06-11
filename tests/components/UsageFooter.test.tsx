import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";
import UsageFooter from "@/components/UsageFooter";
import { usageApi } from "@/lib/api/usage";
import type { Provider, UsageResult } from "@/types";

vi.mock("@/lib/api/usage", () => ({
  usageApi: {
    query: vi.fn(),
  },
}));

function renderUsageFooter(
  usage: UsageResult,
  inline = true,
  onParentClick = vi.fn(),
) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  queryClient.setQueryData(["usage", "provider-1", "claude"], usage);

  const provider: Provider = {
    id: "provider-1",
    name: "Provider",
    settingsConfig: {},
    meta: {
      usage_script: {
        enabled: true,
        language: "javascript",
        code: "",
      },
    },
  };

  return render(
    <QueryClientProvider client={queryClient}>
      <div onClick={onParentClick}>
        <UsageFooter
          provider={provider}
          providerId="provider-1"
          appId="claude"
          usageEnabled
          isCurrent
          inline={inline}
        />
      </div>
    </QueryClientProvider>,
  );
}

describe("UsageFooter", () => {
  beforeEach(() => {
    vi.mocked(usageApi.query).mockResolvedValue({
      success: false,
      error: "refresh failed",
      rate: 1,
    });
  });

  it("shows current rate when usage failed but rate probe succeeded", () => {
    renderUsageFooter({
      success: false,
      error: "usage probe failed",
      rate: 1.5,
      rateLabel: "1.5x",
      probeErrors: {
        usage: "usage probe failed",
      },
    });

    expect(screen.getByText("当前倍率 1.5x")).toBeInTheDocument();
    expect(screen.getByText("用量异常")).toBeInTheDocument();
  });

  it("keeps long rate labels constrained while exposing the full title", () => {
    const longRateLabel =
      "current-rate-from-provider-is-very-long-and-should-not-expand-layout";
    renderUsageFooter({
      success: false,
      error: "usage probe failed",
      rateLabel: longRateLabel,
    });

    const badge = screen.getByText(`当前倍率 ${longRateLabel}`);
    expect(badge).toHaveClass("inline-block");
    expect(badge).toHaveClass("truncate");
    expect(badge).toHaveClass("max-w-[140px]");
    expect(badge).toHaveAttribute("title", `当前倍率 ${longRateLabel}`);
  });

  it("stops propagation when refreshing an inline failed usage result", () => {
    const onParentClick = vi.fn();
    renderUsageFooter(
      {
        success: false,
        error: "usage probe failed",
        rate: 1,
      },
      true,
      onParentClick,
    );

    fireEvent.click(screen.getByTitle("usage.refreshUsage"));

    expect(onParentClick).not.toHaveBeenCalled();
    expect(usageApi.query).toHaveBeenCalledWith("provider-1", "claude");
  });

  it("handles rate zero, label-only rate, and missing rate", () => {
    const { rerender } = renderUsageFooter({
      success: false,
      error: "usage probe failed",
      rate: 0,
    });
    expect(screen.getByText("当前倍率 0x")).toBeInTheDocument();

    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    queryClient.setQueryData(["usage", "provider-1", "claude"], {
      success: false,
      error: "usage probe failed",
      rateLabel: "provider label",
    } satisfies UsageResult);
    const provider: Provider = {
      id: "provider-1",
      name: "Provider",
      settingsConfig: {},
    };
    rerender(
      <QueryClientProvider client={queryClient}>
        <UsageFooter
          provider={provider}
          providerId="provider-1"
          appId="claude"
          usageEnabled
          isCurrent
          inline
        />
      </QueryClientProvider>,
    );
    expect(screen.getByText("当前倍率 provider label")).toBeInTheDocument();

    queryClient.setQueryData(["usage", "provider-1", "claude"], {
      success: false,
      error: "usage probe failed",
    } satisfies UsageResult);
    rerender(
      <QueryClientProvider client={queryClient}>
        <UsageFooter
          provider={provider}
          providerId="provider-1"
          appId="claude"
          usageEnabled
          isCurrent
          inline
        />
      </QueryClientProvider>,
    );
    expect(screen.queryByText(/当前倍率/)).not.toBeInTheDocument();
  });

  it("shows partial probe marker with successful usage data", () => {
    renderUsageFooter({
      success: true,
      data: [
        {
          planName: "Balance",
          used: 4,
          remaining: 6,
          unit: "USD",
          extra: "今日: $22.7450 / 2679 req, 总请求: 9999",
        },
      ],
      rate: 2,
      probeErrors: {
        models: "models probe failed",
      },
    });

    const badge = screen.getByText("2x");
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveAttribute("title", "当前倍率 2x");
    expect(screen.getByText("探测异常")).toBeInTheDocument();
    expect(screen.getByText("用")).toBeInTheDocument();
    expect(screen.getByText("4.00")).toBeInTheDocument();
    expect(screen.getByText(/总请求/)).toBeInTheDocument();
  });

  it("truncates long probe error titles", () => {
    const longError = `probe failed ${"x".repeat(120)}`;
    renderUsageFooter({
      success: true,
      data: [{ used: 1 }],
      probeErrors: {
        models: longError,
      },
    });

    const badge = screen.getByText("探测异常");
    expect(badge.getAttribute("title")).toHaveLength(83);
    expect(badge.getAttribute("title")).toMatch(/\.\.\.$/);
  });
});
