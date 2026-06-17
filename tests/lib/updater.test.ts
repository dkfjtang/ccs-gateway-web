import { describe, expect, it, vi } from "vitest";

const downloadAndInstall = vi.fn();

vi.mock("@platform/updater-impl", () => ({
  getCurrentVersion: vi.fn(async () => "3.16.3-ccs-gateway.1"),
  relaunchApp: vi.fn(async () => undefined),
  checkForUpdate: vi.fn(async () => ({
    status: "available",
    info: {
      currentVersion: "3.16.3-ccs-gateway.1",
      availableVersion: "3.16.4-ccs-gateway.1",
    },
    update: {
      version: "3.16.4-ccs-gateway.1",
      downloadAndInstall,
    },
  })),
}));

describe("updater contract", () => {
  it("preserves the install handle required by UpdateContext", async () => {
    const { checkForUpdate } = await import("@/lib/updater");

    const result = await checkForUpdate({ timeout: 1234 });

    expect(result.status).toBe("available");
    if (result.status === "available") {
      expect(result.info.availableVersion).toBe("3.16.4-ccs-gateway.1");
      expect(result.update.version).toBe("3.16.4-ccs-gateway.1");
      await result.update.downloadAndInstall();
      expect(downloadAndInstall).toHaveBeenCalledTimes(1);
    }
  });
});
