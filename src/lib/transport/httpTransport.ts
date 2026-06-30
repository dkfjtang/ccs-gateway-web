import type { ApiTransport, UnlistenFn } from "./types";

const API_BASE = import.meta.env.VITE_CC_SWITCH_API_BASE || "/api";
const USAGE_INVOKE_TIMEOUT_MS = 30000;

const USAGE_COMMANDS = new Set([
  "get_usage_summary",
  "get_usage_summary_by_app",
  "get_usage_trends",
  "get_provider_stats",
  "get_model_stats",
  "get_request_logs",
  "get_usage_data_sources",
  "sync_session_usage",
]);

export class HttpInvokeError extends Error {
  readonly status: number;
  readonly command: string;
  readonly code?: number;
  readonly data?: unknown;

  constructor(input: {
    status: number;
    command: string;
    message: string;
    code?: number;
    data?: unknown;
  }) {
    super(input.message);
    this.name = "HttpInvokeError";
    this.status = input.status;
    this.command = input.command;
    this.code = input.code;
    this.data = input.data;
  }
}

function parseJson(text: string): unknown {
  if (!text) return undefined;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function extractEnvelopeError(
  json: unknown,
): { message?: string; code?: number; data?: unknown } | undefined {
  if (!json || typeof json !== "object") return undefined;
  const error = (json as { error?: unknown }).error;
  if (!error) return undefined;

  if (typeof error === "string") {
    return { message: error };
  }

  if (typeof error === "object") {
    const shaped = error as { message?: unknown; code?: unknown; data?: unknown };
    const data = shaped.data;
    const directError =
      typeof (error as { error?: unknown }).error === "string"
        ? (error as { error: string }).error
        : undefined;
    const directCapability =
      typeof (error as { capability?: unknown }).capability === "string"
        ? (error as { capability: string }).capability
        : undefined;
    const directCommand =
      typeof (error as { command?: unknown }).command === "string"
        ? (error as { command: string }).command
        : undefined;
    const directMessage =
      typeof (error as { message?: unknown }).message === "string"
        ? (error as { message: string }).message
        : undefined;
    const dataMessage =
      data && typeof data === "object"
        ? (data as { message?: unknown; error?: unknown }).message ||
          (data as { message?: unknown; error?: unknown }).error
        : undefined;
    const normalizedData =
      data !== undefined
        ? data
        : directError || directCapability || directCommand || directMessage
          ? error
          : undefined;
    const message =
      typeof directError === "string"
        ? directError
        : typeof shaped.message === "string"
          ? shaped.message
          : typeof dataMessage === "string"
            ? dataMessage
            : undefined;
    return {
      message,
      code: typeof shaped.code === "number" ? shaped.code : undefined,
      data: normalizedData,
    };
  }

  return undefined;
}

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
  const parsed = parseJson(text);
  if (!res.ok) {
    const envelopeError = extractEnvelopeError(parsed);
    throw new HttpInvokeError({
      status: res.status,
      command,
      message: envelopeError?.message || text || `Invoke failed for ${command}`,
      code: envelopeError?.code,
      data: envelopeError?.data,
    });
  }

  if (!text) return undefined as T;
  try {
    const json = parsed ?? JSON.parse(text);
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
