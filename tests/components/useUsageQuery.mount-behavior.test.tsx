import { act, render } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import UsageFooter from "@/components/UsageFooter";
import { usageApi } from "@/lib/api/usage";
import type { Provider } from "@/types";

vi.mock("@/lib/api/usage", () => ({
  usageApi: {
    query: vi.fn(),
  },
}));

function createProvider(autoQueryInterval = 0): Provider {
  return {
    id: "provider-1",
    name: "Provider",
    settingsConfig: {},
    meta: {
      usage_script: {
        enabled: true,
        language: "javascript",
        code: "",
        autoQueryInterval,
      },
    },
  };
}

function renderFooter(props: {
  isCurrent: boolean;
  autoQueryInterval: number;
  isInConfig?: boolean;
  appId?: "claude" | "opencode";
}) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <UsageFooter
        provider={createProvider(props.autoQueryInterval)}
        providerId="provider-1"
        appId={props.appId ?? "claude"}
        usageEnabled
        isCurrent={props.isCurrent}
        isInConfig={props.isInConfig}
        inline
      />
    </QueryClientProvider>,
  );
}

describe("useUsageQuery mount behavior", () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it("does not fetch on mount when auto interval is configured", async () => {
    vi.useFakeTimers();
    vi.mocked(usageApi.query).mockResolvedValue({
      success: true,
      data: [{ used: 1 }],
    });

    renderFooter({
      isCurrent: true,
      autoQueryInterval: 5,
    });

    await vi.advanceTimersByTimeAsync(0);
    expect(usageApi.query).not.toHaveBeenCalled();
  });

  it("still fetches on interval for the current provider only", async () => {
    vi.useFakeTimers();
    vi.mocked(usageApi.query).mockResolvedValue({
      success: true,
      data: [{ used: 1 }],
    });

    renderFooter({
      isCurrent: true,
      autoQueryInterval: 1,
    });

    await act(async () => {
      await vi.advanceTimersByTimeAsync(60_000);
    });

    expect(usageApi.query).toHaveBeenCalledWith("provider-1", "claude");
  });

  it("does not auto-refresh inactive providers even when an interval is configured", async () => {
    vi.useFakeTimers();
    vi.mocked(usageApi.query).mockResolvedValue({
      success: true,
      data: [{ used: 1 }],
    });

    renderFooter({
      isCurrent: false,
      autoQueryInterval: 1,
    });

    await act(async () => {
      await vi.advanceTimersByTimeAsync(60_000);
    });

    expect(usageApi.query).not.toHaveBeenCalled();
  });

  it("does not auto-refresh opencode providers that are only in config but not current", async () => {
    vi.useFakeTimers();
    vi.mocked(usageApi.query).mockResolvedValue({
      success: true,
      data: [{ used: 1 }],
    });

    renderFooter({
      appId: "opencode",
      isCurrent: false,
      isInConfig: true,
      autoQueryInterval: 1,
    });

    await act(async () => {
      await vi.advanceTimersByTimeAsync(60_000);
    });

    expect(usageApi.query).not.toHaveBeenCalled();
  });
});
