import { detectTransport } from "@platform/transport-impl";
import type { ApiTransport, UnlistenFn } from "./types";

export type { ApiTransport, UnlistenFn, TransportMode } from "./types";

let cachedTransport: ApiTransport | null = null;

export function getTransport(): ApiTransport {
  if (!cachedTransport) {
    cachedTransport = detectTransport();
  }
  return cachedTransport;
}

export function invoke<T = unknown>(
  command: string,
  payload?: unknown,
): Promise<T> {
  return getTransport().invoke<T>(command, payload);
}

export function listen<T = unknown>(
  event: string,
  handler: (payload: T) => void,
): Promise<UnlistenFn> {
  return getTransport().listen<T>(event, handler);
}

export function supportsRealtimeEvents(): boolean {
  const transport = getTransport();
  return transport.mode === "ws" || transport.mode === "tauri";
}

export function getTransportMode() {
  return getTransport().mode;
}

export function __setTransportForTesting(t: ApiTransport | null) {
  cachedTransport = t;
}
