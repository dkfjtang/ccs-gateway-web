import { describe, expect, it, vi } from "vitest";

describe("i18n bootstrap", () => {
  it("registers traditional chinese resources from persisted language", async () => {
    vi.resetModules();
    window.localStorage.setItem("language", "zh-TW");

    const { default: i18n, i18nReady } = await import("@/i18n");
    await i18nReady;

    expect(i18n.language).toBe("zh-TW");
    expect(i18n.hasResourceBundle("zh-TW", "translation")).toBe(true);
    expect(i18n.t("common.save")).not.toBe("common.save");
  });
});
