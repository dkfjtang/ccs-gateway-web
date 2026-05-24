declare module "@platform/transport-impl" {
  import type { ApiTransport } from "@/lib/transport/types";

  export function detectTransport(): ApiTransport;
}
