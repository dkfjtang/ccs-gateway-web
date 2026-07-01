export const defaultServerUrl = "http://127.0.0.1:17666";

export function isLoopbackHostname(hostname) {
  const normalized = String(hostname || "").toLowerCase();
  return (
    normalized === "localhost" ||
    normalized === "127.0.0.1" ||
    normalized === "::1" ||
    normalized === "[::1]"
  );
}

function parseHttpUrl(value) {
  const url = new URL(String(value || ""));
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("服务地址必须以 http:// 或 https:// 开头。");
  }
  if (url.username || url.password) {
    throw new Error("服务地址不能包含用户名或密码。");
  }
  if (url.protocol === "http:" && !isLoopbackHostname(url.hostname)) {
    throw new Error("非本地 CCS 服务地址必须使用 https://。");
  }
  return url;
}

export function normalizeServerUrl(value) {
  const text = String(value || "")
    .trim()
    .replace(/\/+$/, "");
  if (!text) {
    return defaultServerUrl;
  }
  return parseHttpUrl(text).origin;
}

export function isAllowedCcsUrl(value) {
  try {
    parseHttpUrl(value);
    return true;
  } catch {
    return false;
  }
}
