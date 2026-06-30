import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("i18n bootstrap", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    window.localStorage.clear();
    vi.resetModules();
  });

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
    const { default: i18n, ensureLanguageResource, i18nReady } = await import(
      "@/i18n"
    );
    await i18nReady;

    const keys = [
      "usage.currentRate",
      "usage.currentRateValue",
      "usage.usagePartialError",
      "usage.probePartialError",
    ];

    for (const locale of ["zh", "zh-TW", "en", "ja"]) {
      await ensureLanguageResource(locale);
      for (const key of keys) {
        const translated = i18n.getFixedT(locale)(key, { rate: 1.5 });
        expect(translated).not.toBe(key);
        if (locale !== "zh") {
          expect(translated).not.toMatch(/当前倍率|用量异常|探测异常/);
        }
      }
    }
  });

  it("provides usage dashboard toolbar labels for all bundled locales", async () => {
    vi.resetModules();
    const { default: i18n, ensureLanguageResource, i18nReady } = await import(
      "@/i18n"
    );
    await i18nReady;

    const keys = [
      "usage.filterBySource",
      "usage.filterByModel",
      "usage.allSources",
      "usage.allModels",
      "usage.refreshInterval",
      "usage.refreshOff",
    ];

    for (const locale of ["zh", "zh-TW", "en", "ja"]) {
      await ensureLanguageResource(locale);
      for (const key of keys) {
        const translated = i18n.getFixedT(locale)(key);
        expect(translated).not.toBe(key);
        expect(translated).not.toMatch(/^usage\./);
      }
    }
  });

  it("loads non-initial language resources before changing language", async () => {
    vi.resetModules();
    window.localStorage.setItem("language", "zh");

    const { default: i18n, i18nReady } = await import("@/i18n");
    await i18nReady;

    if (i18n.hasResourceBundle("ja", "translation")) {
      i18n.removeResourceBundle("ja", "translation");
    }
    expect(i18n.hasResourceBundle("ja", "translation")).toBe(false);

    await i18n.changeLanguage("ja");

    expect(i18n.language).toBe("ja");
    expect(i18n.hasResourceBundle("ja", "translation")).toBe(true);
    expect(i18n.t("settings.languageOptionJapanese")).not.toBe(
      "settings.languageOptionJapanese",
    );
  });

  it("does not add resource bundles before i18next init attaches the resource store", async () => {
    vi.resetModules();
    Object.defineProperty(window.navigator, "language", {
      configurable: true,
      value: "zh-CN",
    });
    Object.defineProperty(window.navigator, "languages", {
      configurable: true,
      value: ["zh-CN"],
    });
    const addResourceBundle = vi.fn();
    const hasResourceBundle = vi.fn(() => false);
    const changeLanguage = vi.fn(async (language: string) => {
      return language;
    });
    const i18nMock = {
      changeLanguage,
      init: undefined as unknown,
      use: undefined as unknown,
    } as {
      addResourceBundle?: typeof addResourceBundle;
      changeLanguage: typeof changeLanguage;
      hasResourceBundle?: typeof hasResourceBundle;
      init: (options: unknown) => Promise<unknown>;
      use: () => typeof i18nMock;
    };
    const use = vi.fn(() => {
      return i18nMock;
    });
    const init = vi.fn((options: unknown) => {
      Object.assign(i18nMock, {
        addResourceBundle,
        hasResourceBundle,
      });
      return Promise.resolve(options);
    });
    i18nMock.init = init;
    i18nMock.use = use;

    vi.doMock("i18next", () => ({
      default: i18nMock,
    }));
    vi.doMock("react-i18next", () => ({
      initReactI18next: { type: "3rdParty", init: vi.fn() },
    }));

    const { default: i18n, ensureLanguageResource, i18nReady } = await import(
      "@/i18n"
    );

    await expect(i18nReady).resolves.toBeDefined();
    expect(init).toHaveBeenCalledWith(
      expect.objectContaining({
        lng: "zh",
        fallbackLng: "en",
        resources: expect.objectContaining({
          zh: expect.any(Object),
          en: expect.any(Object),
        }),
      }),
    );
    expect(addResourceBundle).not.toHaveBeenCalled();

    await ensureLanguageResource("ja");

    expect(i18n.addResourceBundle).toBe(addResourceBundle);
    expect(addResourceBundle).toHaveBeenCalledWith(
      "ja",
      "translation",
      expect.any(Object),
      true,
      true,
    );
  });
});
