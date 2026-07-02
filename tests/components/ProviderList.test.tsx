import { render, screen, fireEvent } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ReactElement } from "react";
import type { Provider } from "@/types";
import { ProviderList } from "@/components/providers/ProviderList";

const useDragSortMock = vi.fn();
const useSortableMock = vi.fn();
const providerCardRenderSpy = vi.fn();
const useOpenClawLiveProviderIdsMock = vi.fn();
const useOpenClawDefaultModelMock = vi.fn();
const useHermesLiveProviderIdsMock = vi.fn();
const useHermesModelConfigMock = vi.fn();
const useCurrentOmoProviderIdMock = vi.fn();
const useCurrentOmoSlimProviderIdMock = vi.fn();
const useAutoFailoverEnabledMock = vi.fn();
const useFailoverQueueMock = vi.fn();

vi.mock("@/hooks/useDragSort", () => ({
  useDragSort: (...args: unknown[]) => useDragSortMock(...args),
}));

vi.mock("@/components/providers/ProviderCard", () => ({
  ProviderCard: (props: any) => {
    providerCardRenderSpy(props);
    const {
      provider,
      onSwitch,
      onEdit,
      onDelete,
      onDuplicate,
      onConfigureUsage,
    } = props;

    return (
      <div data-testid={`provider-card-${provider.id}`}>
        <button
          data-testid={`switch-${provider.id}`}
          onClick={() => onSwitch(provider)}
        >
          switch
        </button>
        <button
          data-testid={`edit-${provider.id}`}
          onClick={() => onEdit(provider)}
        >
          edit
        </button>
        <button
          data-testid={`duplicate-${provider.id}`}
          onClick={() => onDuplicate(provider)}
        >
          duplicate
        </button>
        <button
          data-testid={`usage-${provider.id}`}
          onClick={() => onConfigureUsage(provider)}
        >
          usage
        </button>
        <button
          data-testid={`delete-${provider.id}`}
          onClick={() => onDelete(provider)}
        >
          delete
        </button>
        <span data-testid={`is-current-${provider.id}`}>
          {props.isCurrent ? "current" : "inactive"}
        </span>
        <span data-testid={`drag-attr-${provider.id}`}>
          {props.dragHandleProps?.attributes?.["data-dnd-id"] ?? "none"}
        </span>
      </div>
    );
  },
}));

vi.mock("@/components/UsageFooter", () => ({
  default: () => <div data-testid="usage-footer" />,
}));

vi.mock("@/hooks/useOpenClaw", () => ({
  useOpenClawLiveProviderIds: (enabled: boolean) =>
    useOpenClawLiveProviderIdsMock(enabled),
  useOpenClawDefaultModel: (enabled: boolean) =>
    useOpenClawDefaultModelMock(enabled),
}));

vi.mock("@/hooks/useHermes", () => ({
  useHermesLiveProviderIds: (enabled: boolean) =>
    useHermesLiveProviderIdsMock(enabled),
  useHermesModelConfig: (enabled: boolean) => useHermesModelConfigMock(enabled),
}));

vi.mock("@/lib/query/omo", () => ({
  useCurrentOmoProviderId: (enabled: boolean) =>
    useCurrentOmoProviderIdMock(enabled),
  useCurrentOmoSlimProviderId: (enabled: boolean) =>
    useCurrentOmoSlimProviderIdMock(enabled),
}));


vi.mock("@dnd-kit/sortable", async () => {
  const actual = await vi.importActual<any>("@dnd-kit/sortable");

  return {
    ...actual,
    useSortable: (...args: unknown[]) => useSortableMock(...args),
  };
});

// Mock hooks that use QueryClient
vi.mock("@/hooks/useStreamCheck", () => ({
  useStreamCheck: () => ({
    checkProvider: vi.fn(),
    isChecking: () => false,
  }),
}));

vi.mock("@/lib/query/failover", () => ({
  useAutoFailoverEnabled: (...args: unknown[]) =>
    useAutoFailoverEnabledMock(...args),
  useFailoverQueue: (...args: unknown[]) => useFailoverQueueMock(...args),
  useAddToFailoverQueue: () => ({ mutate: vi.fn() }),
  useRemoveFromFailoverQueue: () => ({ mutate: vi.fn() }),
  useReorderFailoverQueue: () => ({ mutate: vi.fn() }),
}));

function createProvider(overrides: Partial<Provider> = {}): Provider {
  return {
    id: overrides.id ?? "provider-1",
    name: overrides.name ?? "Test Provider",
    settingsConfig: overrides.settingsConfig ?? {},
    category: overrides.category,
    createdAt: overrides.createdAt,
    sortIndex: overrides.sortIndex,
    meta: overrides.meta,
    websiteUrl: overrides.websiteUrl,
  };
}

function renderWithQueryClient(ui: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>,
  );
}

beforeEach(() => {
  useDragSortMock.mockReset();
  useSortableMock.mockReset();
  providerCardRenderSpy.mockClear();
  vi.clearAllMocks();

  useSortableMock.mockImplementation(({ id }: { id: string }) => ({
    setNodeRef: vi.fn(),
    attributes: { "data-dnd-id": id },
    listeners: { onPointerDown: vi.fn() },
    transform: null,
    transition: null,
    isDragging: false,
  }));

  useDragSortMock.mockReturnValue({
    sortedProviders: [],
    sensors: [],
    handleDragEnd: vi.fn(),
  });
  useOpenClawLiveProviderIdsMock.mockReturnValue({ data: [] });
  useOpenClawDefaultModelMock.mockReturnValue({ data: null });
  useHermesLiveProviderIdsMock.mockReturnValue({ data: [] });
  useHermesModelConfigMock.mockReturnValue({ data: null });
  useCurrentOmoProviderIdMock.mockReturnValue({ data: null });
  useCurrentOmoSlimProviderIdMock.mockReturnValue({ data: null });
  useAutoFailoverEnabledMock.mockReturnValue({ data: false });
  useFailoverQueueMock.mockReturnValue({ data: [] });
});

describe("ProviderList Component", () => {
  it("should render skeleton placeholders when loading", () => {
    const { container } = renderWithQueryClient(
      <ProviderList
        providers={{}}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        isLoading
      />,
    );

    const placeholders = container.querySelectorAll(
      ".border-dashed.border-muted-foreground\\/40",
    );
    expect(placeholders).toHaveLength(3);
  });

  it("keeps hook order stable when switching from loading to loaded providers", async () => {
    const provider = createProvider({ id: "provider-a", name: "Provider A" });

    const { rerender } = renderWithQueryClient(
      <ProviderList
        providers={{}}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        isLoading
        desktopHelpersEnabled={false}
      />,
    );

    rerender(
      <QueryClientProvider
        client={
          new QueryClient({
            defaultOptions: { queries: { retry: false } },
          })
        }
      >
        <ProviderList
          providers={{ "provider-a": provider }}
          currentProviderId=""
          appId="claude"
          onSwitch={vi.fn()}
          onEdit={vi.fn()}
          onDelete={vi.fn()}
          onDuplicate={vi.fn()}
          onOpenWebsite={vi.fn()}
          desktopHelpersEnabled={false}
        />
      </QueryClientProvider>,
    );

    expect(
      await screen.findByTestId("provider-card-provider-a"),
    ).toBeInTheDocument();
  });

  it("should show empty state and trigger create callback when no providers exist", () => {
    const handleCreate = vi.fn();
    useDragSortMock.mockReturnValueOnce({
      sortedProviders: [],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{}}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        onCreate={handleCreate}
      />,
    );

    const addButton = screen.getByRole("button", {
      name: "provider.addProvider",
    });
    fireEvent.click(addButton);

    expect(handleCreate).toHaveBeenCalledTimes(1);
  });

  it("should render in sorted order and pass through action callbacks with dnd wiring", async () => {
    const providerA = createProvider({ id: "a", name: "A", sortIndex: 1 });
    const providerB = createProvider({ id: "b", name: "B", sortIndex: 0 });

    const handleSwitch = vi.fn();
    const handleEdit = vi.fn();
    const handleDelete = vi.fn();
    const handleDuplicate = vi.fn();
    const handleUsage = vi.fn();
    const handleOpenWebsite = vi.fn();

    useDragSortMock.mockReturnValue({
      sortedProviders: [providerB, providerA],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ a: providerA, b: providerB }}
        currentProviderId="b"
        appId="claude"
        onSwitch={handleSwitch}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onDuplicate={handleDuplicate}
        onConfigureUsage={handleUsage}
        onOpenWebsite={handleOpenWebsite}
        desktopHelpersEnabled={false}
      />,
    );

    // Verify sort order
    expect(await screen.findByTestId("provider-card-b")).toBeInTheDocument();
    expect(providerCardRenderSpy).toHaveBeenCalledTimes(2);
    expect(providerCardRenderSpy.mock.calls[0][0].provider.id).toBe("b");
    expect(providerCardRenderSpy.mock.calls[1][0].provider.id).toBe("a");

    // Verify current provider marker
    expect(providerCardRenderSpy.mock.calls[0][0].isCurrent).toBe(true);

    expect(await screen.findByText("b")).toBeInTheDocument();
    expect(useDragSortMock).toHaveBeenLastCalledWith(
      { a: providerA, b: providerB },
      "claude",
      { desktopHelpersEnabled: false },
    );
    expect(useSortableMock).toHaveBeenCalled();

    // Trigger action buttons
    fireEvent.click(screen.getByTestId("switch-b"));
    fireEvent.click(screen.getByTestId("edit-b"));
    fireEvent.click(screen.getByTestId("duplicate-b"));
    fireEvent.click(screen.getByTestId("usage-b"));
    fireEvent.click(screen.getByTestId("delete-a"));

    expect(handleSwitch).toHaveBeenCalledWith(providerB);
    expect(handleEdit).toHaveBeenCalledWith(providerB);
    expect(handleDuplicate).toHaveBeenCalledWith(providerB);
    expect(handleUsage).toHaveBeenCalledWith(providerB);
    expect(handleDelete).toHaveBeenCalledWith(providerA);

  });

  it("keeps provider drag sorting available when desktop helpers are disabled", async () => {
    const providerA = createProvider({ id: "a", name: "A", sortIndex: 1 });
    const providerB = createProvider({ id: "b", name: "B", sortIndex: 0 });

    renderWithQueryClient(
      <ProviderList
        providers={{ a: providerA, b: providerB }}
        currentProviderId="b"
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-b")).toBeInTheDocument();
    expect(useDragSortMock).toHaveBeenLastCalledWith(
      { a: providerA, b: providerB },
      "claude",
      { desktopHelpersEnabled: false },
    );
    expect(useSortableMock).toHaveBeenCalled();
    expect(providerCardRenderSpy).toHaveBeenCalledTimes(2);
    expect(providerCardRenderSpy.mock.calls[0][0].provider.id).toBe("b");
    expect(providerCardRenderSpy.mock.calls[1][0].provider.id).toBe("a");
    expect(providerCardRenderSpy.mock.calls[0][0].dragHandleProps).toBeDefined();
    expect(screen.getByTestId("drag-attr-b")).toHaveTextContent("b");
  });

  it("does not enable local tool live-config hooks when local tools are disabled", async () => {
    const provider = createProvider({ id: "openclaw-provider" });

    useDragSortMock.mockReturnValue({
      sortedProviders: [provider],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ "openclaw-provider": provider }}
        currentProviderId=""
        appId="openclaw"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        thirdPartyLocalToolsEnabled={false}
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-openclaw-provider")).toBeInTheDocument();
    expect(useOpenClawLiveProviderIdsMock).toHaveBeenCalledWith(false);
    expect(useOpenClawDefaultModelMock).toHaveBeenCalledWith(false);
    expect(providerCardRenderSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        usageCapabilitiesEnabled: true,
      }),
    );
  });

  it("passes usage capability gating independently from local tool gating", async () => {
    const provider = createProvider({ id: "provider-a" });

    useDragSortMock.mockReturnValue({
      sortedProviders: [provider],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ "provider-a": provider }}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        thirdPartyLocalToolsEnabled={false}
        usageCapabilitiesEnabled={false}
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-provider-a")).toBeInTheDocument();
    expect(
      providerCardRenderSpy.mock.calls.some(
        ([props]) => props.usageCapabilitiesEnabled === false,
      ),
    ).toBe(true);
  });

  it("does not fetch the failover queue until proxy failover mode can display it", async () => {
    const provider = createProvider({ id: "provider-a" });

    useDragSortMock.mockReturnValue({
      sortedProviders: [provider],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ "provider-a": provider }}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        isProxyTakeover={false}
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-provider-a")).toBeInTheDocument();
    expect(useAutoFailoverEnabledMock).toHaveBeenCalledWith("claude");
    expect(useFailoverQueueMock).toHaveBeenCalledWith("claude", {
      enabled: false,
    });
  });

  it("fetches the failover queue when proxy takeover and auto failover are active", async () => {
    const provider = createProvider({ id: "provider-a" });

    useAutoFailoverEnabledMock.mockReturnValue({ data: true });
    useDragSortMock.mockReturnValue({
      sortedProviders: [provider],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ "provider-a": provider }}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        isProxyTakeover
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-provider-a")).toBeInTheDocument();
    expect(useFailoverQueueMock).toHaveBeenCalledWith("claude", {
      enabled: true,
    });
  });

  it("filters providers with the search input", async () => {
    const providerAlpha = createProvider({ id: "alpha", name: "Alpha Labs" });
    const providerBeta = createProvider({ id: "beta", name: "Beta Works" });

    useDragSortMock.mockReturnValue({
      sortedProviders: [providerAlpha, providerBeta],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ alpha: providerAlpha, beta: providerBeta }}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
        desktopHelpersEnabled={false}
      />,
    );

    expect(await screen.findByTestId("provider-card-alpha")).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "f", metaKey: true });
    const searchInput = screen.getByPlaceholderText(
      "Search name, notes, or URL...",
    );
    // Initially both providers are rendered
    expect(screen.getByTestId("provider-card-alpha")).toBeInTheDocument();
    expect(screen.getByTestId("provider-card-beta")).toBeInTheDocument();

    fireEvent.change(searchInput, { target: { value: "beta" } });
    expect(screen.queryByTestId("provider-card-alpha")).not.toBeInTheDocument();
    expect(screen.getByTestId("provider-card-beta")).toBeInTheDocument();

    fireEvent.change(searchInput, { target: { value: "gamma" } });
    expect(screen.queryByTestId("provider-card-alpha")).not.toBeInTheDocument();
    expect(screen.queryByTestId("provider-card-beta")).not.toBeInTheDocument();
    expect(
      screen.getByText("No providers match your search."),
    ).toBeInTheDocument();
  });

  it("disables dnd while providers are filtered to avoid reordering hidden rows", async () => {
    const providerAlpha = createProvider({ id: "alpha", name: "Alpha Labs" });
    const providerBeta = createProvider({ id: "beta", name: "Beta Works" });

    useDragSortMock.mockReturnValue({
      sortedProviders: [providerAlpha, providerBeta],
      sensors: [],
      handleDragEnd: vi.fn(),
    });

    renderWithQueryClient(
      <ProviderList
        providers={{ alpha: providerAlpha, beta: providerBeta }}
        currentProviderId=""
        appId="claude"
        onSwitch={vi.fn()}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onDuplicate={vi.fn()}
        onOpenWebsite={vi.fn()}
      />,
    );

    expect(await screen.findByTestId("provider-card-alpha")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "f", metaKey: true });
    fireEvent.change(screen.getByPlaceholderText("Search name, notes, or URL..."), {
      target: { value: "beta" },
    });

    expect(screen.queryByTestId("provider-card-alpha")).not.toBeInTheDocument();
    expect(screen.getByTestId("provider-card-beta")).toBeInTheDocument();
    expect(
      providerCardRenderSpy.mock.calls.at(-1)?.[0].dragHandleProps,
    ).toBeUndefined();
  });

});
