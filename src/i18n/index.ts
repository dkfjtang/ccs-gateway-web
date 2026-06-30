import i18n from "i18next";
import { initReactI18next } from "react-i18next";

type Language = "zh" | "zh-TW" | "en" | "ja";
type LocaleModule = { default: Record<string, unknown> };
type ResourceMap = Partial<
  Record<Language, { translation: Record<string, unknown> }>
>;

const DEFAULT_LANGUAGE: Language = "zh";
const FALLBACK_LANGUAGE: Language = "en";
const loadedLanguages = new Set<Language>();
const lazyPatchSymbol = Symbol.for("cc-switch.i18n.lazy-change-language");
const originalChangeLanguageSymbol = Symbol.for(
  "cc-switch.i18n.original-change-language",
);
const resourceLoaderSymbol = Symbol.for("cc-switch.i18n.resource-loader");
type I18nWithLazyPatch = typeof i18n & Record<symbol, unknown>;

const localeLoaders: Record<Language, () => Promise<LocaleModule>> = {
  en: () => import("./locales/en.json"),
  ja: () => import("./locales/ja.json"),
  zh: () => import("./locales/zh.json"),
  "zh-TW": () => import("./locales/zh-TW.json"),
};

const normalizeLanguage = (value?: string | null): Language => {
  if (!value) {
    return DEFAULT_LANGUAGE;
  }

  const normalized = value.toLowerCase();
  if (normalized === "en" || normalized === "ja") {
    return normalized;
  }
  if (
    normalized === "zh-tw" ||
    normalized === "zh_tw" ||
    normalized === "zh-hant" ||
    normalized === "zh_hant" ||
    normalized === "zh-hk" ||
    normalized === "zh-mo"
  ) {
    return "zh-TW";
  }
  return DEFAULT_LANGUAGE;
};

const getInitialLanguage = (): Language => {
  if (typeof window !== "undefined") {
    try {
      const stored = window.localStorage.getItem("language");
      if (stored) {
        return normalizeLanguage(stored);
      }
    } catch (error) {
      console.warn("[i18n] Failed to read stored language preference", error);
    }
  }

  const navigatorLang =
    typeof navigator !== "undefined"
      ? (navigator.language?.toLowerCase() ??
        navigator.languages?.[0]?.toLowerCase())
      : undefined;

  if (
    navigatorLang === "zh-tw" ||
    navigatorLang === "zh-hk" ||
    navigatorLang === "zh-mo" ||
    navigatorLang?.startsWith("zh-hant")
  ) {
    return "zh-TW";
  }

  if (navigatorLang?.startsWith("zh")) {
    return "zh";
  }

  if (navigatorLang?.startsWith("ja")) {
    return "ja";
  }

  if (navigatorLang?.startsWith("en")) {
    return "en";
  }

  return DEFAULT_LANGUAGE;
};

export const ensureLanguageResource = async (
  language: string,
): Promise<Language> => {
  await i18nReady;
  const normalized = normalizeLanguage(language);
  if (
    loadedLanguages.has(normalized) &&
    i18n.hasResourceBundle(normalized, "translation")
  ) {
    return normalized;
  }

  const locale = await localeLoaders[normalized]();
  i18n.addResourceBundle(
    normalized,
    "translation",
    locale.default,
    true,
    true,
  );
  loadedLanguages.add(normalized);
  return normalized;
};

const loadLanguageResource = async (
  language: string,
): Promise<[Language, { translation: Record<string, unknown> }]> => {
  const normalized = normalizeLanguage(language);
  const locale = await localeLoaders[normalized]();
  return [normalized, { translation: locale.default }];
};

const loadInitialResources = async (languages: Language[]) => {
  const entries = await Promise.all(languages.map(loadLanguageResource));
  const resources: ResourceMap = {};
  for (const [language, resource] of entries) {
    resources[language] = resource;
  }
  return resources;
};

const installLazyChangeLanguagePatch = () => {
  const patchableI18n = i18n as I18nWithLazyPatch;
  patchableI18n[resourceLoaderSymbol] = ensureLanguageResource;
  if (patchableI18n[lazyPatchSymbol]) {
    return;
  }
  patchableI18n[originalChangeLanguageSymbol] = i18n.changeLanguage.bind(i18n);
  i18n.changeLanguage = (async (language?: string, callback?: unknown) => {
    const originalChangeLanguage = (patchableI18n[
      originalChangeLanguageSymbol
    ] ?? i18n.changeLanguage.bind(i18n)) as typeof i18n.changeLanguage;
    if (language) {
      const ensureResource = (patchableI18n[resourceLoaderSymbol] ??
        ensureLanguageResource) as typeof ensureLanguageResource;
      const normalized = await ensureResource(language);
      return originalChangeLanguage(normalized, callback as never);
    }
    return originalChangeLanguage(language, callback as never);
  }) as typeof i18n.changeLanguage;
  patchableI18n[lazyPatchSymbol] = true;
};

const initialLanguage = getInitialLanguage();
const initialResourceLanguages = Array.from(
  new Set<Language>([initialLanguage, FALLBACK_LANGUAGE]),
);

export const i18nReady = loadInitialResources(initialResourceLanguages)
  .then((resources) =>
    i18n.use(initReactI18next).init({
      resources,
      lng: initialLanguage, // 根据本地存储或系统语言选择默认语言
      fallbackLng: FALLBACK_LANGUAGE, // 如果缺少中文翻译则退回英文

      interpolation: {
        escapeValue: false, // React 已经默认转义
      },

      // 开发模式下显示调试信息
      debug: false,
    }),
  )
  .then((result) => {
    for (const language of initialResourceLanguages) {
      loadedLanguages.add(language);
    }
    installLazyChangeLanguagePatch();
    return result;
  });

export default i18n;
