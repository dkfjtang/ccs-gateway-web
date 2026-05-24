declare module "@platform/updater-impl" {
  import type { CheckOptions, UpdateHandle, UpdateInfo } from "@/lib/updater";

  export function getCurrentVersion(): Promise<string>;
  export function checkForUpdate(
    opts?: CheckOptions,
  ): Promise<
    | { status: "up-to-date" }
    | { status: "available"; info: UpdateInfo; update: UpdateHandle }
  >;
  export function relaunchApp(): Promise<void>;
}
