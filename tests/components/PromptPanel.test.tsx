import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import PromptPanel from "@/components/prompts/PromptPanel";
import { promptsApi, type Prompt } from "@/lib/api";

const reloadMock = vi.fn();
const savePromptMock = vi.fn();
const deletePromptMock = vi.fn();
const toggleEnabledMock = vi.fn();

let promptState: Record<string, Prompt> = {};

vi.mock("sonner", () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
  },
}));

vi.mock("@/hooks/usePromptActions", () => ({
  usePromptActions: () => ({
    prompts: promptState,
    loading: false,
    reload: reloadMock,
    savePrompt: savePromptMock,
    deletePrompt: deletePromptMock,
    toggleEnabled: toggleEnabledMock,
  }),
}));

vi.mock("@/lib/api", async () => {
  const actual = await vi.importActual<typeof import("@/lib/api")>("@/lib/api");
  return {
    ...actual,
    promptsApi: {
      ...actual.promptsApi,
      createCavemanStyleProfile: vi.fn(),
      enablePrompt: vi.fn(),
    },
  };
});

describe("PromptPanel Caveman profiles", () => {
  beforeEach(() => {
    promptState = {};
    reloadMock.mockReset();
    savePromptMock.mockReset();
    deletePromptMock.mockReset();
    toggleEnabledMock.mockReset();
    vi.mocked(promptsApi.createCavemanStyleProfile).mockReset();
    vi.mocked(promptsApi.enablePrompt).mockReset();
  });

  it("enables an existing inactive Caveman profile without recreating it", async () => {
    promptState = {
      "caveman-lite": {
        id: "caveman-lite",
        name: "Caveman Lite Style Profile",
        content: "Mode: lite",
        enabled: false,
      },
    };
    vi.mocked(promptsApi.createCavemanStyleProfile).mockResolvedValue(
      "caveman-full",
    );

    render(
      <PromptPanel open={true} onOpenChange={() => {}} appId="openclaw" />,
    );

    const liteButton = screen.getByRole("button", {
      name: "prompts.caveman.useExisting",
    });

    await userEvent.click(liteButton);

    expect(promptsApi.createCavemanStyleProfile).not.toHaveBeenCalled();
    expect(promptsApi.enablePrompt).toHaveBeenCalledWith(
      "openclaw",
      "caveman-lite",
    );

    await waitFor(() => {
      expect(reloadMock).toHaveBeenCalled();
    });
  });

  it("creates and enables the selected Caveman mode", async () => {
    vi.mocked(promptsApi.createCavemanStyleProfile).mockResolvedValue(
      "caveman-full",
    );
    vi.mocked(promptsApi.enablePrompt).mockResolvedValue();

    render(
      <PromptPanel open={true} onOpenChange={() => {}} appId="openclaw" />,
    );

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.createFull" }),
    );

    await waitFor(() => {
      expect(promptsApi.createCavemanStyleProfile).toHaveBeenCalledWith(
        "openclaw",
        "full",
      );
      expect(promptsApi.enablePrompt).toHaveBeenCalledWith(
        "openclaw",
        "caveman-full",
      );
    });
  });

  it("turns off the active Caveman mode without deleting the preset", async () => {
    promptState = {
      "caveman-ultra": {
        id: "caveman-ultra",
        name: "Caveman Ultra Style Profile",
        content: "Mode: ultra",
        enabled: true,
      },
    };
    toggleEnabledMock.mockResolvedValue(undefined);

    render(
      <PromptPanel open={true} onOpenChange={() => {}} appId="openclaw" />,
    );

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.turnOff" }),
    );

    expect(toggleEnabledMock).toHaveBeenCalledWith("caveman-ultra", false);
    expect(promptsApi.createCavemanStyleProfile).not.toHaveBeenCalled();
  });

  it("switches from one active Caveman mode to another existing mode", async () => {
    promptState = {
      "caveman-lite": {
        id: "caveman-lite",
        name: "Caveman Lite Style Profile",
        content: "Mode: lite",
        enabled: true,
      },
      "caveman-full": {
        id: "caveman-full",
        name: "Caveman Full Style Profile",
        content: "Mode: full",
        enabled: false,
      },
      "caveman-custom": {
        id: "caveman-custom",
        name: "User custom caveman prompt",
        content: "custom",
        enabled: true,
      },
    };
    vi.mocked(promptsApi.enablePrompt).mockResolvedValue();

    render(
      <PromptPanel open={true} onOpenChange={() => {}} appId="openclaw" />,
    );

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.useExisting" }),
    );

    expect(promptsApi.createCavemanStyleProfile).not.toHaveBeenCalled();
    expect(promptsApi.enablePrompt).toHaveBeenCalledWith(
      "openclaw",
      "caveman-full",
    );
    expect(
      screen.getByRole("button", { name: "prompts.caveman.turnOff" }),
    ).toBeEnabled();
  });
});
