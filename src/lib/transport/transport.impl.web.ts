import { HttpTransport } from "./httpTransport";
import { WebSocketTransport } from "./wsTransport";
import type { ApiTransport } from "./types";

export function detectTransport(): ApiTransport {
  const mode = import.meta.env.VITE_CC_SWITCH_MODE;

  if (mode === "ws" || mode === "websocket") {
    console.log("[Transport] Using WebSocket transport (build-time)");
    return WebSocketTransport;
  }

  if (mode === "http" || mode === "web") {
    console.log("[Transport] Using HTTP transport (build-time)");
    return HttpTransport;
  }

  if (typeof WebSocket === "undefined") {
    console.warn("[Transport] WebSocket not supported, falling back to HTTP");
    return HttpTransport;
  }

  console.log("[Transport] Using WebSocket transport (runtime detection)");
  return WebSocketTransport;
}
