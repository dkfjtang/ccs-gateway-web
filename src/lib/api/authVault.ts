const API_BASE = import.meta.env.VITE_CC_SWITCH_API_BASE || "/api";

export type AuthVaultReceiveClosedReason =
  | "manual"
  | "expired"
  | "success"
  | "failure_limit";

export interface AuthVaultReceiveWindowStatus {
  ok: boolean;
  status: "open" | "closed";
  enabled: boolean;
  expiresAt: string | null;
  remainingSeconds: number | null;
  failureCount: number;
  closedReason: AuthVaultReceiveClosedReason | null;
}

async function postReceiveWindow(path: string) {
  const response = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    credentials: "include",
  });
  const result = (await response.json().catch(() => null)) as
    | AuthVaultReceiveWindowStatus
    | { error?: string; message?: string }
    | null;

  if (!response.ok) {
    const error =
      result && typeof result === "object"
        ? (result as { error?: string; message?: string })
        : null;
    throw new Error(
      error?.message ||
        error?.error ||
        `Auth Vault request failed with status ${response.status}`,
    );
  }

  return result as AuthVaultReceiveWindowStatus;
}

export const authVaultApi = {
  openReceiveWindow(): Promise<AuthVaultReceiveWindowStatus> {
    return postReceiveWindow("/auth-vault/receive-window");
  },

  closeReceiveWindow(): Promise<AuthVaultReceiveWindowStatus> {
    return postReceiveWindow("/auth-vault/receive-window/close");
  },
};
