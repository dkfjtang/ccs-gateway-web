import { describe, expect, it, vi } from "vitest";
import {
  assertProfileMatchesBuildInfo,
  fetchServerBuildInfo,
  getCurrentDocumentBuildId,
  shouldNotifyBuildUpdate,
  startBuildUpdateMonitor,
  verifyServerBuildProfile,
} from "@/lib/buildInfo";

describe("buildInfo", () => {
  it("uses current document main assets as the client build id", () => {
    document.head.innerHTML = `
      <script type="module" src="./assets/index-BTaiIF1Z.js"></script>
      <link rel="stylesheet" href="./assets/index-CY8IdWrI.css">
      <script type="module" src="./assets/vendor-react.js"></script>
    `;

    expect(getCurrentDocumentBuildId()).toBe(
      "assets/index-BTaiIF1Z.js,assets/index-CY8IdWrI.css",
    );
  });

  it("notifies only once when the server build differs from the client build", () => {
    const notify = vi.fn();

    expect(
      shouldNotifyBuildUpdate({
        clientBuildId: "assets/index-old.js",
        serverBuildId: "assets/index-new.js",
        alreadyNotified: false,
        notify,
      }),
    ).toBe(true);
    expect(
      shouldNotifyBuildUpdate({
        clientBuildId: "assets/index-old.js",
        serverBuildId: "assets/index-new.js",
        alreadyNotified: true,
        notify,
      }),
    ).toBe(false);
    expect(notify).toHaveBeenCalledTimes(1);
  });

  it("reads build info profile and capabilities", async () => {
    const fetchImpl = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          build_id: "assets/index-new.js",
          profile: "slim",
          capabilities: {
            profile: "slim",
            enabled_groups: ["providers"],
            disabled_groups: ["skills"],
          },
        }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;

    const info = await fetchServerBuildInfo(fetchImpl);

    expect(info?.profile).toBe("slim");
    expect(info?.capabilities?.disabled_groups).toContain("skills");
  });

  it("deduplicates concurrent build info fetches", async () => {
    let resolveResponse: ((response: Response) => void) | undefined;
    const fetchImpl = vi.fn(
      () =>
        new Promise<Response>((resolve) => {
          resolveResponse = resolve;
        }),
    ) as unknown as typeof fetch;

    const first = fetchServerBuildInfo(fetchImpl);
    const second = fetchServerBuildInfo(fetchImpl);

    expect(fetchImpl).toHaveBeenCalledTimes(1);

    resolveResponse?.(
      new Response(
        JSON.stringify({
          build_id: "assets/index-new.js",
          profile: "slim",
        }),
        { status: 200 },
      ),
    );

    await expect(first).resolves.toMatchObject({
      build_id: "assets/index-new.js",
    });
    await expect(second).resolves.toMatchObject({
      build_id: "assets/index-new.js",
    });
  });

  it("throws on frontend backend profile mismatch", () => {
    expect(() => assertProfileMatchesBuildInfo({ profile: "slim" }, "full")).toThrow(
      /profile mismatch/,
    );
    expect(() => assertProfileMatchesBuildInfo({ profile: "slim" }, "slim")).not.toThrow();
  });

  it("rejects startup profile mismatch before rendering", async () => {
    const fetchImpl = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          build_id: "assets/index-server.js",
          profile: "slim",
        }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;

    await expect(verifyServerBuildProfile(fetchImpl)).rejects.toThrow(
      /profile mismatch/,
    );
  });

  it("allows legacy build info that does not expose a profile", async () => {
    const fetchImpl = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          build_id: "assets/index-server.js",
        }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;

    await expect(verifyServerBuildProfile(fetchImpl)).resolves.toBeUndefined();
  });

  it("allows missing build info so legacy or file-based contexts can start", async () => {
    const fetchImpl = vi.fn(async () => {
      return new Response("", { status: 404 });
    }) as unknown as typeof fetch;

    await expect(verifyServerBuildProfile(fetchImpl)).resolves.toBeUndefined();
  });

  it("does not block startup when build info is temporarily unavailable", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("network offline");
    }) as unknown as typeof fetch;

    await expect(verifyServerBuildProfile(fetchImpl)).resolves.toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      "[build-info] Failed to verify server build profile",
      expect.any(TypeError),
    );

    errorSpy.mockRestore();
  });

  it("gates runtime usage on profile mismatch during build monitoring", async () => {
    vi.useFakeTimers();
    document.head.innerHTML = `
      <script type="module" src="./assets/index-client.js"></script>
    `;
    expect(window.location.protocol).toMatch(/^https?:$/);
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(
      async () =>
        new Response(
          JSON.stringify({
            build_id: "assets/index-server.js",
            profile: "slim",
          }),
          { status: 200 },
        ),
    );
    const notify = vi.fn();
    const onProfileMismatch = vi.fn();

    const stop = startBuildUpdateMonitor({
      onUpdateAvailable: notify,
      onProfileMismatch,
      intervalMs: 1000,
    });
    await vi.runOnlyPendingTimersAsync();

    expect(notify).not.toHaveBeenCalled();
    expect(onProfileMismatch).toHaveBeenCalledWith(
      expect.stringContaining("profile mismatch"),
    );

    stop();
    fetchSpy.mockRestore();
    vi.useRealTimers();
  });
});
