import { afterEach, describe, expect, it, vi } from "vitest";

import { HttpInvokeError, HttpTransport } from "@/lib/transport/httpTransport";

describe("HttpTransport", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("surfaces structured capability disabled errors from HTTP invoke", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        return new Response(
          JSON.stringify({
            error: {
              error: "capability_disabled",
              capability: "skills",
              command: "get_installed_skills",
              message:
                "This capability is disabled in the current ccs-web profile.",
            },
          }),
          {
            status: 403,
            headers: { "content-type": "application/json" },
          },
        );
      }),
    );

    await expect(
      HttpTransport.invoke("get_installed_skills"),
    ).rejects.toMatchObject({
      name: "HttpInvokeError",
      message: "capability_disabled",
      status: 403,
      data: {
        error: "capability_disabled",
        capability: "skills",
        command: "get_installed_skills",
      },
      command: "get_installed_skills",
    } satisfies Partial<HttpInvokeError>);
  });

  it("preserves legacy string errors from HTTP invoke", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        return new Response(
          JSON.stringify({
            error: "invalid request payload",
          }),
          {
            status: 400,
            headers: { "content-type": "application/json" },
          },
        );
      }),
    );

    await expect(HttpTransport.invoke("ping")).rejects.toMatchObject({
      name: "HttpInvokeError",
      message: "invalid request payload",
      status: 400,
      data: undefined,
      command: "ping",
    } satisfies Partial<HttpInvokeError>);
  });
});
