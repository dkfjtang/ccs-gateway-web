import type { CheckOptions } from "./updater";

export async function getCurrentVersion(): Promise<string> {
  return __APP_VERSION__;
}

export async function checkForUpdate(
  _opts: CheckOptions = {},
): Promise<{ status: "up-to-date" }> {
  return { status: "up-to-date" };
}

export async function relaunchApp(): Promise<void> {
  return Promise.resolve();
}
