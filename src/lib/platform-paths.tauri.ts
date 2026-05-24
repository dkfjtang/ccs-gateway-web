import { homeDir, join } from "@tauri-apps/api/path";
import type { AppId } from "@/lib/api";

export async function computeDefaultAppConfigDir(): Promise<
  string | undefined
> {
  try {
    const home = await homeDir();
    return await join(home, ".cc-switch");
  } catch (error) {
    console.error(
      "[platform-paths] Failed to resolve default app config dir",
      error,
    );
    return undefined;
  }
}

export async function computeDefaultConfigDir(
  app: AppId,
): Promise<string | undefined> {
  try {
    const home = await homeDir();
    const folder =
      app === "claude"
        ? ".claude"
        : app === "codex"
          ? ".codex"
          : app === "gemini"
            ? ".gemini"
            : app === "opencode"
              ? ".config/opencode"
              : app === "openclaw"
                ? ".openclaw"
                : ".hermes";
    return await join(home, folder);
  } catch (error) {
    console.error(
      "[platform-paths] Failed to resolve default config dir",
      error,
    );
    return undefined;
  }
}
