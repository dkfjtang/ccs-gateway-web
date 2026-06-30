import { Suspense, type ComponentType } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AuthProvider } from "@/contexts/AuthContext";
import { server } from "../msw/server";
import { resetProviderState } from "../msw/state";

const buildInfoMock = vi.hoisted(() => ({
  startBuildUpdateMonitor: vi.fn<
    (options: {
      onUpdateAvailable: () => void;
      onProfileMismatch?: (message: string) => void;
      intervalMs?: number;
    }) => () => void
  >(() => () => {}),
}));
const appSwitcherPropsMock = vi.fn();
const providerListPropsMock = vi.fn();
const openclawScanHealthMock = vi.fn();
const hermesOpenWebUIMock = vi.fn();
const hermesLaunchDashboardMock = vi.fn();

vi.mock("@/lib/buildInfo", () => ({
  startBuildUpdateMonitor: buildInfoMock.startBuildUpdateMonitor,
}));

vi.mock("@/lib/api/auth", () => ({
  authApi: {
    checkStatus: () => Promise.resolve({ enabled: false }),
    checkSession: () => Promise.resolve({ valid: true }),
    login: () => Promise.resolve({ success: false, error: "mock" }),
  },
}));

vi.mock("@/components/providers/ProviderList", () => ({
  ProviderList: (props: any) => {
    providerListPropsMock(props);
    return (
      <div data-testid="provider-list">{JSON.stringify(props.providers)}</div>
    );
  },
}));

vi.mock("@/components/AppSwitcher", () => ({
  AppSwitcher: (props: any) => {
    appSwitcherPropsMock(props);
    return (
      <div data-testid="app-switcher">
        {JSON.stringify(props.visibleApps)}
      </div>
    );
  },
}));

vi.mock("@/components/UpdateBadge", () => ({
  UpdateBadge: () => <button>update-badge</button>,
}));

vi.mock("@/lib/api/openclaw", () => {
  return {
    openclawApi: {
      scanHealth: openclawScanHealthMock,
    },
  };
});

vi.mock("@/lib/api/hermes", () => {
  return {
    hermesApi: {
      openWebUI: hermesOpenWebUIMock,
      launchDashboard: hermesLaunchDashboardMock,
    },
  };
});

vi.mock("sonner", () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
    warning: vi.fn(),
  },
}));

const renderApp = (AppComponent: ComponentType) => {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <AuthProvider>
        <Suspense fallback={<div data-testid="loading">loading</div>}>
          <AppComponent />
        </Suspense>
      </AuthProvider>
    </QueryClientProvider>,
  );
};

describe("App slim startup effects", () => {
  beforeEach(() => {
    vi.stubEnv("VITE_CCS_WEB_PROFILE", "slim");
    resetProviderState();
    appSwitcherPropsMock.mockClear();
    providerListPropsMock.mockClear();
    openclawScanHealthMock.mockClear();
    hermesOpenWebUIMock.mockClear();
    hermesLaunchDashboardMock.mockClear();
    buildInfoMock.startBuildUpdateMonitor.mockReset();
    buildInfoMock.startBuildUpdateMonitor.mockReturnValue(() => {});
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("does not run local env or skills startup effects in slim profile", async () => {
    const rpcCommands: string[] = [];
    const onRequestStart = ({ request }: { request: Request }) => {
      const url = new URL(request.url);
      if (url.origin === "http://tauri.local") {
        rpcCommands.push(url.pathname.slice(1));
      }
    };
    server.events.on("request:start", onRequestStart);

    try {
      const { default: App } = await import("@/App");
      renderApp(App);

      await waitFor(() =>
        expect(screen.getByTestId("provider-list")).toBeInTheDocument(),
      );
      await waitFor(() => {
        expect(rpcCommands).toContain("get_migration_result");
      });

      expect(rpcCommands).not.toContain("check_env_conflicts");
      expect(rpcCommands).not.toContain("get_skills_migration_result");
      expect(appSwitcherPropsMock).toHaveBeenCalled();
      expect(appSwitcherPropsMock.mock.calls.at(-1)?.[0].visibleApps).toEqual({
        claude: true,
        "claude-desktop": false,
        codex: true,
        gemini: true,
        opencode: false,
        openclaw: false,
        hermes: false,
      });
      expect(providerListPropsMock).toHaveBeenCalledWith(
        expect.objectContaining({
          desktopHelpersEnabled: false,
          thirdPartyLocalToolsEnabled: false,
          usageCapabilitiesEnabled: true,
        }),
      );
      expect(openclawScanHealthMock).not.toHaveBeenCalled();
      expect(hermesOpenWebUIMock).not.toHaveBeenCalled();
      expect(hermesLaunchDashboardMock).not.toHaveBeenCalled();
    } finally {
      server.events.removeListener("request:start", onRequestStart);
    }
  });

  it("blocks runtime usage when the backend profile differs from the baked slim profile", async () => {
    buildInfoMock.startBuildUpdateMonitor.mockImplementation(
      ({ onProfileMismatch }) => {
        onProfileMismatch?.(
          "ccs-web profile mismatch: frontend=slim, backend=full",
        );
        return () => {};
      },
    );

    const { default: App } = await import("@/App");
    renderApp(App);

    expect(
      await screen.findByRole("heading", { name: "ccs-web profile mismatch" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/frontend=slim, backend=full/),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("provider-list")).not.toBeInTheDocument();
  });
});
