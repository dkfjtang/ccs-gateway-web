import { describe, expect, it } from "vitest";
import { settingsSchema } from "@/lib/schemas/settings";

const baseSettings = {
  showInTray: true,
  minimizeToTrayOnClose: false,
};

describe("settingsSchema", () => {
  it("accepts traditional chinese language preference", () => {
    const parsed = settingsSchema.parse({
      ...baseSettings,
      language: "zh-TW",
    });

    expect(parsed.language).toBe("zh-TW");
  });

  it("preserves s3 sync settings when parsing settings", () => {
    const parsed = settingsSchema.parse({
      ...baseSettings,
      s3Sync: {
        enabled: true,
        autoSync: true,
        region: "auto",
        bucket: "ccs-sync",
        accessKeyId: "access-key",
        secretAccessKey: "secret-key",
        endpoint: "https://example.r2.cloudflarestorage.com",
        remoteRoot: "cc-switch-sync",
        profile: "default",
        status: {
          lastError: "timeout",
          lastErrorSource: "auto",
        },
      },
    });

    expect(parsed.s3Sync).toMatchObject({
      enabled: true,
      autoSync: true,
      bucket: "ccs-sync",
      secretAccessKey: "secret-key",
      status: {
        lastError: "timeout",
        lastErrorSource: "auto",
      },
    });
  });
});
