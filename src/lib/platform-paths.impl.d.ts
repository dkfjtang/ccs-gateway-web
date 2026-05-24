declare module "@platform/platform-paths-impl" {
  import type { AppId } from "@/lib/api";

  export function computeDefaultAppConfigDir(): Promise<string | undefined>;
  export function computeDefaultConfigDir(
    app: AppId,
  ): Promise<string | undefined>;
}
