import { isLoopbackHostname } from "./url-policy.js";

export const fixedVaultPath = "/api/auth-vault/tokens";

export function isLoopbackServerUrl(serverUrl) {
  try {
    return isLoopbackHostname(new URL(String(serverUrl || "")).hostname);
  } catch {
    return false;
  }
}

export function getRequiredSyncOrigins(serverUrl) {
  if (isLoopbackServerUrl(serverUrl)) {
    return [];
  }
  return [`${new URL(serverUrl).origin}/*`];
}

export function buildSyncRequest({ serverUrl, payload, ccsSession }) {
  const headers = {
    "Content-Type": "application/json",
    "X-CCS-Auth-Vault-Sync": "browser-extension",
  };
  const usesLoopbackBridge = isLoopbackServerUrl(serverUrl);

  if (usesLoopbackBridge) {
    if (!ccsSession) {
      throw new Error(
        "本地 CCS 未登录或登录态已过期，请先打开 CCS Web 并完成登录。",
      );
    }
    headers["X-CCS-Session"] = ccsSession;
  } else if (ccsSession) {
    headers["X-CCS-Auth-Vault-Session"] = ccsSession;
  }

  return {
    url: `${serverUrl}${fixedVaultPath}`,
    init: {
      method: "POST",
      credentials: usesLoopbackBridge
        ? "same-origin"
        : ccsSession
          ? "omit"
          : "include",
      headers,
      body: JSON.stringify(payload),
    },
  };
}

export function formatSyncError(result, status) {
  if (result?.error === "auth_vault_receive_window_closed") {
    return "远端 CCS 未打开 Auth Vault 临时接收窗口，请先在远端 CCS 设置中打开接收开关后再同步。";
  }
  if (result?.error === "auth_vault_receive_window_busy") {
    return "远端 CCS Auth Vault 临时接收窗口正在处理另一条同步，请稍后重试；窗口不会因此关闭。";
  }
  if (
    result?.error === "capability_disabled" &&
    result?.capability === "auth-vault"
  ) {
    return "远端 CCS 当前未开启 Auth Vault 接收能力，请先在远端 CCS 设置中打开临时接收开关后再同步。";
  }
  return result?.error || `CCS 返回 HTTP ${status}`;
}
