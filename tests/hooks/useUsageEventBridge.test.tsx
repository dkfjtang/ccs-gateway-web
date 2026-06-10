import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { PropsWithChildren } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useUsageEventBridge } from "@/hooks/useUsageEventBridge";
import { usageKeys } from "@/lib/query/usage";

const listenMock = vi.fn();

vi.mock("@tauri-apps/api/event", () => ({
  listen: (...args: unknown[]) => listenMock(...args),
}));

describe("useUsageEventBridge", () => {
  beforeEach(() => {
    listenMock.mockReset();
  });

  it("invalidates usage queries when backend records a usage log", async () => {
    let eventHandler: (() => void) | undefined;
    const unlisten = vi.fn();
    listenMock.mockImplementation(async (_eventName, handler) => {
      eventHandler = handler as () => void;
      return unlisten;
    });

    const queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false },
      },
    });
    const invalidateSpy = vi.spyOn(queryClient, "invalidateQueries");

    const wrapper = ({ children }: PropsWithChildren) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    );

    const { unmount } = renderHook(() => useUsageEventBridge(), { wrapper });

    await waitFor(() => {
      expect(listenMock).toHaveBeenCalledWith(
        "usage-log-recorded",
        expect.any(Function),
      );
    });

    eventHandler?.();

    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: usageKeys.all });

    unmount();
    expect(unlisten).toHaveBeenCalledTimes(1);
  });
});
