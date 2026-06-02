import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import PromptPanel from "@/components/prompts/PromptPanel";
import type { Prompt } from "@/lib/api";
import { __setTransportForTesting } from "@/lib/transport";
import type { ApiTransport } from "@/lib/transport";

type InvokeCall = {
  command: string;
  payload?: unknown;
};

describe("PromptPanel Caveman runtime flow", () => {
  let prompts: Record<string, Prompt>;
  let livePromptFile: string | null;
  let calls: InvokeCall[];

  beforeEach(() => {
    prompts = {};
    livePromptFile = null;
    calls = [];

    const transport: ApiTransport = {
      mode: "tauri",
      async invoke<T>(command: string, payload?: unknown): Promise<T> {
        calls.push({ command, payload });

        switch (command) {
          case "get_prompts":
            return { ...prompts } as T;
          case "get_current_prompt_file_content":
            return livePromptFile as T;
          case "create_caveman_style_profile": {
            const { profile } = payload as { profile: "lite" | "full" | "ultra" };
            const id = `caveman-${profile}`;
            prompts[id] = {
              id,
              name: `Caveman ${profile} Style Profile`,
              content: `Mode: ${profile}`,
              enabled: false,
            };
            return id as T;
          }
          case "enable_prompt": {
            const { id } = payload as { id: string };
            prompts = Object.fromEntries(
              Object.entries(prompts).map(([promptId, prompt]) => [
                promptId,
                { ...prompt, enabled: promptId === id },
              ]),
            );
            livePromptFile = prompts[id]?.content ?? null;
            return undefined as T;
          }
          case "upsert_prompt": {
            const { id, prompt } = payload as { id: string; prompt: Prompt };
            prompts[id] = prompt;
            const enabledPrompt = Object.values(prompts).find((p) => p.enabled);
            livePromptFile = enabledPrompt?.content ?? null;
            return undefined as T;
          }
          default:
            throw new Error(`Unexpected command: ${command}`);
        }
      },
      async listen() {
        return () => {};
      },
    };

    __setTransportForTesting(transport);
  });

  afterEach(() => {
    __setTransportForTesting(null);
  });

  it("creates, enables, switches, and turns off Caveman through the real prompt hook", async () => {
    render(
      <PromptPanel open={true} onOpenChange={() => {}} appId="openclaw" />,
    );

    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: "prompts.caveman.createLite" }),
      ).toBeInTheDocument();
    });
    expect(
      screen.getByRole("button", { name: "prompts.caveman.createFull" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "prompts.caveman.createUltra" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "prompts.caveman.turnOff" }),
    ).toBeDisabled();

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.createFull" }),
    );

    await waitFor(() => {
      expect(prompts["caveman-full"].enabled).toBe(true);
      expect(livePromptFile).toBe("Mode: full");
      expect(
        screen.getByRole("button", { name: "prompts.caveman.enabled" }),
      ).toBeInTheDocument();
    });
    expect(prompts["caveman-full"]).toBeDefined();
    expect(
      calls.some(
        (call) =>
          call.command === "create_caveman_style_profile" &&
          (call.payload as { profile?: string }).profile === "full",
      ),
    ).toBe(true);

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.createLite" }),
    );

    await waitFor(() => {
      expect(prompts["caveman-lite"].enabled).toBe(true);
      expect(prompts["caveman-full"].enabled).toBe(false);
      expect(livePromptFile).toBe("Mode: lite");
      expect(
        screen.getByRole("button", { name: "prompts.caveman.enabled" }),
      ).toBeInTheDocument();
    });

    await userEvent.click(
      screen.getByRole("button", { name: "prompts.caveman.turnOff" }),
    );

    await waitFor(() => {
      expect(prompts["caveman-lite"]).toBeDefined();
      expect(prompts["caveman-lite"].enabled).toBe(false);
      expect(livePromptFile).toBeNull();
      expect(
        screen.getByRole("button", { name: "prompts.caveman.turnOff" }),
      ).toBeDisabled();
      expect(
        screen.getAllByRole("button", { name: "prompts.caveman.useExisting" }),
      ).toHaveLength(2);
    });
  });
});
