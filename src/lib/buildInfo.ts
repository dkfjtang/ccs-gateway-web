import {
  getBakedProfile,
  profileMatchesBuildInfo,
  type CapabilityManifest,
  type CcsWebProfile,
} from "@/lib/capabilities";

export interface BuildInfo {
  build_id?: string;
  buildId?: string;
  assets?: string[];
  profile?: CcsWebProfile;
  capabilities?: CapabilityManifest;
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
  const info = await fetchServerBuildInfo(fetchImpl);
  return info?.build_id || info?.buildId || "";
}

export async function fetchServerBuildInfo(
  fetchImpl: typeof fetch = fetch,
): Promise<BuildInfo | null> {
  const existingRequest = serverBuildInfoRequests.get(fetchImpl);
  if (existingRequest) {
    return existingRequest;
  }
  const request = fetchServerBuildInfoUncached(fetchImpl);
  const trackedRequest = request.finally(() => {
    if (serverBuildInfoRequests.get(fetchImpl) === trackedRequest) {
      serverBuildInfoRequests.delete(fetchImpl);
    }
  });
  serverBuildInfoRequests.set(fetchImpl, trackedRequest);
  return trackedRequest;
}

const serverBuildInfoRequests = new WeakMap<
  typeof fetch,
  Promise<BuildInfo | null>
>();

async function fetchServerBuildInfoUncached(
  fetchImpl: typeof fetch,
): Promise<BuildInfo | null> {
  const response = await fetchImpl("/build-info.json", {
    cache: "no-store",
    headers: {
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    return null;
  }
  return (await response.json()) as BuildInfo;
}

export function assertProfileMatchesBuildInfo(
  info: BuildInfo | null,
  bakedProfile: CcsWebProfile = getBakedProfile(),
): void {
  if (!profileMatchesBuildInfo(bakedProfile, info?.profile)) {
    throw new Error(
      `ccs-web profile mismatch: frontend=${bakedProfile}, backend=${info?.profile}`,
    );
  }
}

export function getProfileMismatchMessage(
  info: BuildInfo | null,
  bakedProfile: CcsWebProfile = getBakedProfile(),
): string | null {
  try {
    assertProfileMatchesBuildInfo(info, bakedProfile);
    return null;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

export async function verifyServerBuildProfile(
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const info = await fetchServerBuildInfo(fetchImpl).catch((error) => {
    console.error("[build-info] Failed to verify server build profile", error);
    return null;
  });
  assertProfileMatchesBuildInfo(info);
}

export function startBuildUpdateMonitor(options: {
  onUpdateAvailable: () => void;
  onProfileMismatch?: (message: string) => void;
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
      const info = await fetchServerBuildInfo();
      const profileMismatch = getProfileMismatchMessage(info);
      if (profileMismatch) {
        options.onProfileMismatch?.(profileMismatch);
        return;
      }
      const serverBuildId = info?.build_id || info?.buildId || "";
      const notified = shouldNotifyBuildUpdate({
        clientBuildId,
        serverBuildId,
        alreadyNotified,
        notify: options.onUpdateAvailable,
      });
      alreadyNotified = alreadyNotified || notified;
    } catch (error) {
      console.error("[build-info] Failed to verify server build info", error);
      // Network/build refresh errors must not interrupt normal app usage.
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
