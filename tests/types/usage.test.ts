import { describe, expect, it } from "vitest";
import { getFreshInputTokens } from "@/types/usage";

describe("usage token normalization", () => {
  it("subtracts cache reads only for cache-inclusive app types", () => {
    expect(
      getFreshInputTokens({
        appType: "codex",
        inputTokens: 100,
        cacheReadTokens: 25,
      }),
    ).toBe(75);

    expect(
      getFreshInputTokens({
        appType: "gemini",
        inputTokens: 100,
        cacheReadTokens: 25,
      }),
    ).toBe(75);
  });

  it("keeps OpenCode input tokens as fresh input", () => {
    expect(
      getFreshInputTokens({
        appType: "opencode",
        inputTokens: 100,
        cacheReadTokens: 25,
      }),
    ).toBe(100);
  });
});
