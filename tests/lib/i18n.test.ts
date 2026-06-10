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

  it("provides usage probe badge labels for all bundled locales", async () => {
    vi.resetModules();
    const { default: i18n, i18nReady } = await import("@/i18n");
    await i18nReady;

    const keys = [
      "usage.currentRate",
      "usage.currentRateValue",
      "usage.usagePartialError",
      "usage.probePartialError",
    ];

    for (const locale of ["zh", "zh-TW", "en", "ja"]) {
      for (const key of keys) {
        const translated = i18n.getFixedT(locale)(key, { rate: 1.5 });
        expect(translated).not.toBe(key);
        if (locale !== "zh") {
          expect(translated).not.toMatch(/当前倍率|用量异常|探测异常/);
        }
      }
    }
  });
});
