import {
  buildSyncRequest,
  formatSyncError,
  getRequiredSyncOrigins,
  isLoopbackServerUrl,
} from "./sync-policy.js";
import { defaultServerUrl, normalizeServerUrl } from "./url-policy.js";

const captureButton = document.getElementById("capture");
const copyButton = document.getElementById("copy");
const output = document.getElementById("output");
const meta = document.getElementById("meta");
const candidatesList = document.getElementById("candidates");
const serverInput = document.getElementById("server");

function setMeta(text, error = false) {
  meta.textContent = text;
  meta.classList.toggle("error", error);
}

function safeSerialize(value) {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return "{}";
  }
}

async function getServerUrl() {
  const serverUrl = normalizeServerUrl(serverInput.value);
  await chrome.storage.local.set({ serverUrl });
  serverInput.value = serverUrl;
  return serverUrl;
}

async function getCcsSessionHeader(serverUrl) {
  const sessionResponse = await chrome.runtime.sendMessage({
    type: "GET_CCS_SESSION",
    url: serverUrl,
  });
  if (!sessionResponse?.ok) {
    throw new Error(sessionResponse?.error || "读取 CCS 登录态失败。");
  }
  if (!sessionResponse.value) {
    throw new Error(
      "本地 CCS 未登录或登录态已过期，请先打开 CCS Web 并完成登录。",
    );
  }
  return sessionResponse.value;
}

function previewSecret(value) {
  const text = String(value ?? "");
  if (!text) {
    return "";
  }
  if (text.length <= 16) {
    return `${text.slice(0, 4)}...len=${text.length}`;
  }
  return `${text.slice(0, 10)}...${text.slice(-6)} len=${text.length}`;
}

function base64UrlDecode(value) {
  const normalized = String(value || "")
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return atob(padded);
}

function parseJwtPayload(value) {
  const text = String(value || "").replace(/^Bearer\s+/i, "");
  const parts = text.split(".");
  if (parts.length !== 3) {
    return null;
  }

  try {
    const decoded = base64UrlDecode(parts[1]);
    return JSON.parse(decoded);
  } catch {
    return null;
  }
}

function formatUnixSeconds(value) {
  if (!Number.isFinite(value)) {
    return null;
  }
  return new Date(value * 1000).toISOString();
}

function buildAuthTokenReview(candidate) {
  if (!candidate?.value) {
    return null;
  }

  const value = String(candidate.value);
  const payload = parseJwtPayload(value);
  const nowSeconds = Math.floor(Date.now() / 1000);
  const expiresInSeconds = Number.isFinite(payload?.exp)
    ? payload.exp - nowSeconds
    : null;

  return {
    source: `${candidate.source}.${candidate.key}`,
    preview: previewSecret(value),
    length: value.length,
    prefix16: value.slice(0, 16),
    suffix12: value.slice(-12),
    isJwt: Boolean(payload),
    jwt: payload
      ? {
          issuer: payload.iss || null,
          subject: payload.sub || null,
          audience: payload.aud || null,
          issuedAt: formatUnixSeconds(payload.iat),
          expiresAt: formatUnixSeconds(payload.exp),
          expiresInSeconds,
        }
      : null,
    reviewHint:
      "请用 Network 里真实 Authorization bearer 的长度、前 16 位、后 12 位和 JWT exp 对照；这里不会展示完整 token。",
  };
}

function looksLikeAuthValue(source, key, value) {
  const keyText = String(key || "").toLowerCase();
  const valueText = String(value || "");
  if (!valueText || valueText.length < 20) {
    return false;
  }
  if (
    /(^|[_-])(auth|access|id|api)?[_-]?(token|jwt|bearer)([_-]|$)/i.test(
      keyText,
    )
  ) {
    return true;
  }
  if (
    source === "cookie" &&
    /(^|[_-])(session|sid|jwt|auth|token|access|bearer)([_-]|$)/i.test(keyText)
  ) {
    return true;
  }
  if (
    /^(eyJ[A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/.test(valueText)
  ) {
    return true;
  }
  if (/^Bearer\s+[A-Za-z0-9._~+/=-]{20,}$/i.test(valueText)) {
    return true;
  }
  return false;
}

function extractCookieMap(cookieText) {
  const cookies = {};
  for (const part of String(cookieText || "").split(";")) {
    const trimmed = part.trim();
    if (!trimmed) {
      continue;
    }
    const index = trimmed.indexOf("=");
    const key = index >= 0 ? trimmed.slice(0, index) : trimmed;
    const value = index >= 0 ? trimmed.slice(index + 1) : "";
    cookies[key] = value;
  }
  return cookies;
}

function hostKeyFromOrigin(origin) {
  return new URL(origin).hostname.toLowerCase();
}

function findAuthCandidates(capture) {
  const candidates = [];
  const addCandidate = (source, key, value) => {
    if (!looksLikeAuthValue(source, key, value)) {
      return;
    }
    candidates.push({
      source,
      key,
      preview: previewSecret(value),
      length: String(value ?? "").length,
      value,
    });
  };

  for (const [key, value] of Object.entries(capture?.localStorage || {})) {
    addCandidate("localStorage", key, value);
  }
  for (const [key, value] of Object.entries(capture?.sessionStorage || {})) {
    addCandidate("sessionStorage", key, value);
  }
  for (const [key, value] of Object.entries(
    extractCookieMap(capture?.cookie || ""),
  )) {
    addCandidate("cookie", key, value);
  }

  return candidates;
}

function pickAuthToken(candidates) {
  return (
    candidates.find(
      (candidate) =>
        candidate.source !== "cookie" && candidate.key === "auth_token",
    ) ||
    candidates.find(
      (candidate) =>
        candidate.source !== "cookie" && /token/i.test(candidate.key),
    ) ||
    candidates.find((candidate) => candidate.source !== "cookie") ||
    null
  );
}

function sanitizeCapture(capture) {
  const candidates = findAuthCandidates(capture);
  const authToken = pickAuthToken(candidates);
  return {
    capturedAt: capture?.capturedAt,
    title: capture?.title,
    url: capture?.url,
    origin: capture?.origin,
    cookieSource: capture?.cookieSource || null,
    cookieCount: Number.isFinite(capture?.cookieCount)
      ? capture.cookieCount
      : null,
    cookieError: capture?.cookieError || null,
    authCandidateCount: candidates.filter(
      (candidate) => candidate.source !== "cookie",
    ).length,
    tokenCandidateCount: candidates.length,
    selectedAuthToken: buildAuthTokenReview(authToken),
    authCandidates: candidates.map(({ value, ...candidate }) => candidate),
    tokenCandidates: candidates.map(({ value, ...candidate }) => candidate),
    storageKeys: {
      localStorage: Object.keys(capture?.localStorage || {}),
      sessionStorage: Object.keys(capture?.sessionStorage || {}),
      cookie: Object.keys(extractCookieMap(capture?.cookie || "")),
    },
  };
}

function toSiteEntry(capture) {
  const candidates = findAuthCandidates(capture);
  const authToken = pickAuthToken(candidates);
  const cookieHeader = String(capture?.cookie || "").trim();
  const cookieNames = Object.keys(extractCookieMap(cookieHeader));

  return {
    origin: capture.origin,
    host: hostKeyFromOrigin(capture.origin),
    url: capture.url,
    title: capture.title,
    capturedAt: capture.capturedAt,
    cookieSource: capture.cookieSource || null,
    cookieCount: Number.isFinite(capture.cookieCount)
      ? capture.cookieCount
      : null,
    authCandidateCount: candidates.filter(
      (candidate) => candidate.source !== "cookie",
    ).length,
    tokenCandidateCount: candidates.length,
    authToken: authToken?.value || null,
    authTokenSource: authToken ? `${authToken.source}.${authToken.key}` : null,
    authTokenPreview: authToken ? previewSecret(authToken.value) : null,
    cookieHeader: cookieHeader || null,
    cookieNames,
    cookieHeaderPreview: cookieHeader
      ? `${cookieNames.join("; ")} len=${cookieHeader.length}`
      : null,
    candidates: candidates.map(({ value, ...candidate }) => candidate),
  };
}

function buildFreshnessNote(previousSiteEntry, nextSiteEntry, summary) {
  if (!previousSiteEntry) {
    return null;
  }

  if (
    (summary.cookieCount || 0) === 0 &&
    (previousSiteEntry.authToken || previousSiteEntry.cookieHeader)
  ) {
    return "本次未取到 Cookie，但该站点已有历史认证记录，可能已过期、被轮换或被浏览器权限拦截。";
  }

  if (
    previousSiteEntry.authToken &&
    !nextSiteEntry.authToken &&
    (summary.authCandidateCount || 0) === 0
  ) {
    return "本次未识别到 token，但该站点已有历史 token，可能已过期、被轮换或字段名变化。";
  }

  return null;
}

function toVaultEntry(capture, candidate) {
  return {
    origin: capture.origin,
    url: capture.url,
    capturedAt: capture.capturedAt,
    tokenName: `${new URL(capture.origin).hostname.replace(/[^a-z0-9]+/gi, "_")}__${candidate.key}`,
    source: `${candidate.source}.${candidate.key}`,
    value: candidate.value,
    preview: previewSecret(candidate.value),
    length: String(candidate.value ?? "").length,
  };
}

function renderCandidates(candidates) {
  candidatesList.replaceChildren();
  if (!candidates.length) {
    const item = document.createElement("li");
    item.className = "candidate";
    item.textContent = "未发现疑似认证值。";
    candidatesList.appendChild(item);
    return;
  }
  for (const candidate of candidates) {
    const item = document.createElement("li");
    item.className = "candidate";

    const title = document.createElement("strong");
    title.textContent = `${candidate.source}.${candidate.key}`;

    const preview = document.createElement("code");
    preview.textContent = candidate.preview;

    item.append(title, preview);
    candidatesList.appendChild(item);
  }
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("未找到当前活动页面。");
  }
  return tab;
}

async function captureCurrentTab() {
  const tab = await getActiveTab();
  const [result] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => {
      const readStorage = (storage) => {
        const snapshot = {};
        for (let i = 0; i < storage.length; i += 1) {
          const key = storage.key(i);
          if (key) {
            snapshot[key] = storage.getItem(key);
          }
        }
        return snapshot;
      };

      return {
        capturedAt: new Date().toISOString(),
        title: document.title,
        url: location.href,
        origin: location.origin,
        localStorage: readStorage(window.localStorage),
        sessionStorage: readStorage(window.sessionStorage),
        cookie: document.cookie,
      };
    },
  });

  const capture = result?.result ?? {};
  try {
    const cookieOrigin = `${new URL(capture.url || tab.url).origin}/*`;
    if (chrome.permissions?.contains && chrome.permissions?.request) {
      const hasCookieOrigin = await chrome.permissions.contains({
        permissions: ["cookies"],
        origins: [cookieOrigin],
      });
      if (!hasCookieOrigin) {
        await chrome.permissions.request({
          permissions: ["cookies"],
          origins: [cookieOrigin],
        });
      }
    }
    const cookieResponse = await chrome.runtime.sendMessage({
      type: "GET_COOKIES",
      url: capture.url || tab.url,
    });
    if (!cookieResponse?.ok) {
      throw new Error(cookieResponse?.error || "后台 Cookie 读取失败。");
    }
    const cookies = cookieResponse.cookies || [];
    const cookieHeader = cookies
      .map((cookie) => `${cookie.name}=${cookie.value}`)
      .join("; ");
    capture.cookie = cookieHeader || capture.cookie || "";
    capture.cookieCount = cookies.length;
    capture.cookieSource = cookieHeader
      ? "background.cookies"
      : "background.cookies(empty)";
  } catch (error) {
    capture.cookieSource = "document.cookie";
    capture.cookieError =
      error instanceof Error ? error.message : String(error);
    capture.cookieCount = 0;
  }

  return capture;
}

async function saveCaptureToVault(capture, summary) {
  const siteEntry = toSiteEntry(capture);
  if (!siteEntry.authToken && !siteEntry.cookieHeader) {
    throw new Error("最近一次读取中没有发现可保存的认证值或 Cookie。");
  }

  const firstCandidate = findAuthCandidates(capture)[0];
  const entry = firstCandidate ? toVaultEntry(capture, firstCandidate) : null;
  const { siteVault = {}, tokenVault = {} } = await chrome.storage.local.get([
    "siteVault",
    "tokenVault",
  ]);
  const previousSiteEntry = siteVault[siteEntry.host] || null;
  const freshnessNote = buildFreshnessNote(
    previousSiteEntry,
    siteEntry,
    summary,
  );
  const nextSiteVault = {
    ...siteVault,
    [siteEntry.host]: siteEntry,
  };
  const nextVault = {
    ...tokenVault,
    ...(entry ? { [entry.tokenName]: entry } : {}),
  };
  await chrome.storage.local.set({
    siteVault: nextSiteVault,
    tokenVault: nextVault,
  });
  return { siteEntry, entry, freshnessNote, previousSiteEntry };
}

async function syncVaultToCcs() {
  const { siteVault = {}, tokenVault = {} } = await chrome.storage.local.get([
    "siteVault",
    "tokenVault",
  ]);
  if (!Object.keys(siteVault).length && !Object.keys(tokenVault).length) {
    throw new Error("扩展本地认证库为空。");
  }

  const serverUrl = await getServerUrl();
  const requiredSyncOrigins = getRequiredSyncOrigins(serverUrl);
  if (
    requiredSyncOrigins.length &&
    chrome.permissions?.contains &&
    chrome.permissions?.request
  ) {
    const hasSyncOrigin = await chrome.permissions.contains({
      origins: requiredSyncOrigins,
    });
    if (!hasSyncOrigin) {
      const granted = await chrome.permissions.request({
        origins: requiredSyncOrigins,
      });
      if (!granted) {
        throw new Error("未授予扩展访问远程 CCS 服务地址的权限。");
      }
    }
  }
  let ccsSession = null;
  if (isLoopbackServerUrl(serverUrl)) {
    ccsSession = await getCcsSessionHeader(serverUrl);
  } else {
    try {
      ccsSession = await getCcsSessionHeader(serverUrl);
    } catch {
      ccsSession = null;
    }
  }
  const request = buildSyncRequest({
    serverUrl,
    payload: { sites: siteVault, tokenVault },
    ccsSession,
  });
  const response = await fetch(request.url, request.init);
  const result = await response.json();
  if (!response.ok || !result.ok) {
    throw new Error(formatSyncError(result, response.status));
  }

  return result;
}

async function loadLastCapture() {
  const {
    lastCaptureSummary = null,
    serverUrl = defaultServerUrl,
    siteVault = {},
  } = await chrome.storage.local.get([
    "lastCaptureSummary",
    "serverUrl",
    "siteVault",
  ]);
  serverInput.value = serverUrl;
  if (lastCaptureSummary) {
    output.textContent = safeSerialize(lastCaptureSummary);
    renderCandidates(
      lastCaptureSummary.authCandidates ||
        lastCaptureSummary.tokenCandidates ||
        [],
    );
    setMeta(
      `上次读取：${lastCaptureSummary.origin || "未知站点"}；已保存站点 ${Object.keys(siteVault).length} 个`,
    );
  }
}

captureButton.addEventListener("click", async () => {
  captureButton.disabled = true;
  setMeta("正在读取、保存并同步...");
  try {
    const capture = await captureCurrentTab();
    const summary = sanitizeCapture(capture);
    await chrome.storage.local.set({
      lastCaptureRaw: capture,
      lastCaptureSummary: summary,
    });
    const { siteEntry, freshnessNote, previousSiteEntry } =
      await saveCaptureToVault(capture, summary);
    const syncResult = await syncVaultToCcs();
    output.textContent = safeSerialize({
      capture: summary,
      savedSite: {
        host: siteEntry.host,
        origin: siteEntry.origin,
        title: siteEntry.title,
        authTokenSource: siteEntry.authTokenSource,
        authTokenPreview: siteEntry.authTokenPreview,
        selectedAuthToken: summary.selectedAuthToken,
        cookieNames: siteEntry.cookieNames,
        cookieHeaderPreview: siteEntry.cookieHeaderPreview,
        capturedAt: siteEntry.capturedAt,
        cookieSource: siteEntry.cookieSource,
        cookieCount: siteEntry.cookieCount,
        authCandidateCount: siteEntry.authCandidateCount,
        tokenCandidateCount: siteEntry.tokenCandidateCount,
      },
      synced: {
        count: syncResult.count,
        siteCount: syncResult.siteCount,
        sites: syncResult.sites,
        tokens: syncResult.tokens,
      },
      freshness: {
        previousSaved: Boolean(previousSiteEntry),
        note: freshnessNote,
      },
    });
    renderCandidates(summary.authCandidates || []);
    if (freshnessNote) {
      setMeta(`已读取、保存并同步 ${siteEntry.host}；${freshnessNote}`, true);
    } else if ((summary.cookieCount || 0) === 0) {
      setMeta(
        `已读取、保存并同步 ${siteEntry.host}，但未拿到 Cookie。请确认扩展已重新加载并授予 cookies 权限。`,
        true,
      );
    } else {
      setMeta(
        `已读取、保存并同步 ${siteEntry.host}；CCS 当前 ${syncResult.siteCount ?? 0} 个站点。`,
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setMeta(message, true);
  } finally {
    captureButton.disabled = false;
  }
});

copyButton.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(output.textContent || "{}");
    setMeta("结果已复制到剪贴板。");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setMeta(message, true);
  }
});

loadLastCapture().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  setMeta(message, true);
});
