export interface BuildInfo {
  build_id?: string;
  buildId?: string;
  assets?: string[];
}

export interface BuildUpdateDecision {
  clientBuildId: string;
  serverBuildId: string;
  alreadyNotified: boolean;
  notify: () => void;
}

export function getCurrentDocumentBuildId(doc: Document = document): string {
  const assets = new Set<string>();
  doc
    .querySelectorAll<HTMLScriptElement | HTMLLinkElement>(
      'script[src*="assets/index-"],link[href*="assets/index-"]',
    )
    .forEach((element) => {
      const raw =
        element instanceof HTMLScriptElement
          ? element.getAttribute("src")
          : element.getAttribute("href");
      const normalized = normalizeAssetPath(raw);
      if (normalized) {
        assets.add(normalized);
      }
    });

  return Array.from(assets).sort().join(",");
}

export function shouldNotifyBuildUpdate({
  clientBuildId,
  serverBuildId,
  alreadyNotified,
  notify,
}: BuildUpdateDecision): boolean {
  if (!clientBuildId || !serverBuildId || clientBuildId === serverBuildId) {
    return false;
  }
  if (alreadyNotified) {
    return false;
  }
  notify();
  return true;
}

export async function fetchServerBuildId(
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const response = await fetchImpl("/build-info.json", {
    cache: "no-store",
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    return "";
  }
  const info = (await response.json()) as BuildInfo;
  return info.build_id || info.buildId || "";
}

export function startBuildUpdateMonitor(options: {
  onUpdateAvailable: () => void;
  intervalMs?: number;
}): () => void {
  if (typeof window === "undefined" || typeof document === "undefined") {
    return () => {};
  }
  if (!/^https?:$/.test(window.location.protocol)) {
    return () => {};
  }

  const clientBuildId = getCurrentDocumentBuildId();
  if (!clientBuildId) {
    return () => {};
  }

  let stopped = false;
  let alreadyNotified = false;

  const check = async () => {
    if (stopped) return;
    try {
      const serverBuildId = await fetchServerBuildId();
      const notified = shouldNotifyBuildUpdate({
        clientBuildId,
        serverBuildId,
        alreadyNotified,
        notify: options.onUpdateAvailable,
      });
      alreadyNotified = alreadyNotified || notified;
    } catch {
      // Build refresh checks must not interrupt normal app usage.
    }
  };

  const onFocus = () => {
    void check();
  };
  const onVisibilityChange = () => {
    if (document.visibilityState === "visible") {
      void check();
    }
  };

  const interval = window.setInterval(check, options.intervalMs ?? 300_000);
  window.addEventListener("focus", onFocus);
  document.addEventListener("visibilitychange", onVisibilityChange);
  void check();

  return () => {
    stopped = true;
    window.clearInterval(interval);
    window.removeEventListener("focus", onFocus);
    document.removeEventListener("visibilitychange", onVisibilityChange);
  };
}

function normalizeAssetPath(value: string | null): string {
  if (!value) return "";
  const match = value.match(/assets\/index-[^?#"']+\.(?:js|css)/);
  return match?.[0] ?? "";
}
