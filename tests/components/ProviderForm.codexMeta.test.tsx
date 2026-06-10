import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import { ProviderForm } from "@/components/providers/forms/ProviderForm";
import { settingsApi } from "@/lib/api";

let settingsQueryData: unknown = { commonConfigConfirmed: true };

vi.mock("sonner", () => ({
  toast: {
    error: vi.fn(),
    success: vi.fn(),
  },
}));

vi.mock("@tanstack/react-query", async () => {
  const actual = await vi.importActual<typeof import("@tanstack/react-query")>(
    "@tanstack/react-query",
  );
  return {
    ...actual,
    useQuery: () => ({ data: [], isLoading: false }),
    useQueryClient: () => ({ invalidateQueries: vi.fn() }),
  };
});

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock("@/lib/api", () => ({
  providersApi: {
    getProviders: vi.fn().mockResolvedValue([]),
  },
  configApi: {
    getCommonConfigSnippet: vi.fn().mockResolvedValue(""),
  },
  settingsApi: {
    save: vi.fn().mockResolvedValue(undefined),
  },
}));

vi.mock("@/lib/query", () => ({
  useSettingsQuery: () => ({
    data: settingsQueryData,
  }),
}));

vi.mock("@/components/providers/forms/ProviderPresetSelector", () => ({
  ProviderPresetSelector: () => null,
}));

vi.mock("@/components/providers/forms/CodexConfigEditor", () => ({
  default: () => null,
}));

describe("ProviderForm Codex metadata", () => {
  it("preserves Codex chat preset metadata when submitting", async () => {
    const handleSubmit = vi.fn().mockResolvedValue(undefined);

    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });

    render(
      <QueryClientProvider client={queryClient}>
        <ProviderForm
          appId="codex"
          submitLabel="providerForm.saveProvider"
          onCancel={vi.fn()}
          onSubmit={handleSubmit}
          initialData={{
            name: "Volcengine Agentplan",
            websiteUrl: "https://ark.cn-beijing.volces.com",
            settingsConfig: {
              auth: {},
              config:
                'model_provider = "volcengine-agentplan"\nwire_api = "responses"\n',
              modelCatalog: [
                {
                  model: "deepseek-v3-1-terminus",
                  name: "DeepSeek V3.1 Terminus",
                },
              ],
            },
            meta: {
              apiFormat: "openai_chat",
              codexChatReasoning: {
                supportsThinking: true,
                supportsEffort: true,
                effortParam: "reasoning_effort",
                effortValueMode: "passthrough",
              },
            },
          }}
        />
      </QueryClientProvider>,
    );

    fireEvent.click(
      screen.getByRole("button", {
        name: "providerForm.saveProvider",
      }),
    );
    fireEvent.click(
      await screen.findByRole("button", {
        name: "providerForm.softValidation.saveAnyway",
      }),
    );

    await waitFor(() => expect(handleSubmit).toHaveBeenCalledTimes(1));
    const submitted = handleSubmit.mock.calls[0][0];
    expect(submitted.meta?.apiFormat).toBe("openai_chat");
    expect(submitted.meta?.codexChatReasoning).toEqual({
      supportsThinking: true,
      supportsEffort: true,
      effortParam: "reasoning_effort",
      effortValueMode: "passthrough",
    });
    expect(JSON.parse(submitted.settingsConfig).modelCatalog).toEqual([
      {
        model: "deepseek-v3-1-terminus",
        name: "DeepSeek V3.1 Terminus",
      },
    ]);
  });

  it("does not submit cloud sync settings when confirming common config", async () => {
    vi.mocked(settingsApi.save).mockClear();
    settingsQueryData = {
      commonConfigConfirmed: false,
      webdavSync: {
        enabled: true,
        password: "",
      },
      s3Sync: {
        enabled: true,
        secretAccessKey: "",
      },
    };

    try {
      const queryClient = new QueryClient({
        defaultOptions: {
          queries: { retry: false },
          mutations: { retry: false },
        },
      });

      render(
        <QueryClientProvider client={queryClient}>
          <ProviderForm
            appId="codex"
            submitLabel="providerForm.saveProvider"
            onCancel={vi.fn()}
            onSubmit={vi.fn()}
          />
        </QueryClientProvider>,
      );

      fireEvent.click(
        screen.getByRole("button", {
          name: "confirm.commonConfig.confirm",
        }),
      );

      await waitFor(() => expect(settingsApi.save).toHaveBeenCalledTimes(1));
      const payload = vi.mocked(settingsApi.save).mock.calls[0][0];
      expect(payload.commonConfigConfirmed).toBe(true);
      expect(payload).not.toHaveProperty("webdavSync");
      expect(payload).not.toHaveProperty("s3Sync");
    } finally {
      settingsQueryData = { commonConfigConfirmed: true };
    }
  });
});
