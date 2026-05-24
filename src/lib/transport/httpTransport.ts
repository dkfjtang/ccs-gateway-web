import type { ApiTransport, UnlistenFn } from "./types";

const API_BASE = import.meta.env.VITE_CC_SWITCH_API_BASE || "/api";
const USAGE_INVOKE_TIMEOUT_MS = 30000;

const USAGE_COMMANDS = new Set([
  "get_usage_summary",
  "get_usage_trends",
  "get_provider_stats",
  "get_model_stats",
  "get_request_logs",
  "get_usage_data_sources",
  "sync_session_usage",
]);

async function httpInvoke<T>(command: string, payload?: unknown): Promise<T> {
  const controller = USAGE_COMMANDS.has(command)
    ? new AbortController()
    : undefined;
  const timeoutId = controller
    ? window.setTimeout(() => controller.abort(), USAGE_INVOKE_TIMEOUT_MS)
    : undefined;

  let res: Response;
  try {
    res = await fetch(`${API_BASE}/invoke`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include", // Include cookies for auth
      body: JSON.stringify({ command, payload: payload ?? {} }),
      signal: controller?.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`Invoke timed out for ${command}`);
    }
    throw error;
  } finally {
    if (timeoutId != null) {
      window.clearTimeout(timeoutId);
    }
  }

  const text = await res.text();
  if (!res.ok) {
    throw new Error(text || `Invoke failed for ${command}`);
  }

  if (!text) return undefined as T;
  try {
    const json = JSON.parse(text);
    // Unwrap result/error envelope from server response
    if (json.error) {
      throw new Error(json.error);
    }
    return (json.result ?? json) as T;
  } catch (e) {
    if (e instanceof SyntaxError) {
      return text as T;
    }
    throw e;
  }
}

export const HttpTransport: ApiTransport = {
  mode: "http",

  invoke: httpInvoke,

  async listen<T = unknown>(
    _event: string,
    _handler: (payload: T) => void,
  ): Promise<UnlistenFn> {
    console.warn("[HttpTransport] listen() not supported, returning no-op");
    return () => {};
  },

  debug(msg: string, data?: unknown) {
    if (import.meta.env.DEV) {
      console.debug(`[HttpTransport] ${msg}`, data ?? "");
    }
  },
};
