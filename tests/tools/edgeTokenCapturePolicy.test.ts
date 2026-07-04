import { describe, expect, it } from "vitest";

import {
  buildSyncRequest,
  formatSyncError,
  getRequiredSyncOrigins,
  isLoopbackServerUrl,
} from "../../tools/edge-token-capture/sync-policy.js";
import {
  isAllowedCcsUrl,
  normalizeServerUrl,
} from "../../tools/edge-token-capture/url-policy.js";

describe("edge token capture CCS URL policy", () => {
  it("allows remote HTTPS CCS origins", () => {
    expect(normalizeServerUrl("https://ccs.example.com/")).toBe(
      "https://ccs.example.com",
    );
    expect(isAllowedCcsUrl("https://ccs.example.com/")).toBe(true);
  });

  it("keeps loopback defaults supported", () => {
    expect(normalizeServerUrl("")).toBe("http://127.0.0.1:17666");
    expect(normalizeServerUrl("http://localhost:17666/")).toBe(
      "http://localhost:17666",
    );
    expect(normalizeServerUrl("http://[::1]:17666/path")).toBe(
      "http://[::1]:17666",
    );
    expect(isAllowedCcsUrl("http://127.0.0.1:17666")).toBe(true);
  });

  it("rejects unsupported protocols", () => {
    expect(() => normalizeServerUrl("file:///tmp/ccs")).toThrow(
      "服务地址必须以 http:// 或 https:// 开头。",
    );
    expect(isAllowedCcsUrl("file:///tmp/ccs")).toBe(false);
  });

  it("rejects remote HTTP origins", () => {
    expect(() => normalizeServerUrl("http://ccs.example.com")).toThrow(
      "非本地 CCS 服务地址必须使用 https://。",
    );
    expect(isAllowedCcsUrl("http://ccs.example.com")).toBe(false);
  });

  it("rejects credentials in remote HTTPS origins", () => {
    expect(() =>
      normalizeServerUrl("https://user:pass@ccs.example.com"),
    ).toThrow("服务地址不能包含用户名或密码。");
    expect(isAllowedCcsUrl("https://user:pass@ccs.example.com")).toBe(false);
  });

  it("normalizes to the origin and ignores custom paths", () => {
    expect(
      normalizeServerUrl("https://ccs.example.com/custom/path?x=1#hash"),
    ).toBe("https://ccs.example.com");
  });
});

describe("edge token capture CCS sync policy", () => {
  const vaultPayload = {
    sites: { "example.com": { host: "example.com" } },
    tokenVault: {},
  };

  it("uses extension session header only for loopback CCS servers", () => {
    expect(isLoopbackServerUrl("http://127.0.0.1:17666")).toBe(true);
    expect(isLoopbackServerUrl("http://localhost:17666")).toBe(true);
    expect(isLoopbackServerUrl("http://[::1]:17666")).toBe(true);
    expect(isLoopbackServerUrl("https://ccs.example.com")).toBe(false);

    const request = buildSyncRequest({
      serverUrl: "http://127.0.0.1:17666",
      payload: vaultPayload,
      ccsSession: "session-token",
    });

    expect(request.url).toBe("http://127.0.0.1:17666/api/auth-vault/tokens");
    expect(request.init.credentials).toBe("same-origin");
    expect(request.init.headers).toEqual({
      "Content-Type": "application/json",
      "X-CCS-Auth-Vault-Sync": "browser-extension",
      "X-CCS-Session": "session-token",
    });
  });

  it("uses browser cookies for remote HTTPS CCS servers", () => {
    const request = buildSyncRequest({
      serverUrl: "https://ccs.example.com",
      payload: vaultPayload,
      ccsSession: null,
    });

    expect(request.url).toBe("https://ccs.example.com/api/auth-vault/tokens");
    expect(request.init.credentials).toBe("include");
    expect(request.init.headers).toEqual({
      "Content-Type": "application/json",
      "X-CCS-Auth-Vault-Sync": "browser-extension",
    });
  });

  it("keeps the dedicated receive session header available for remote HTTPS CCS servers", () => {
    const request = buildSyncRequest({
      serverUrl: "https://ccs.example.com",
      payload: vaultPayload,
      ccsSession: "session-token",
    });

    expect(request.url).toBe("https://ccs.example.com/api/auth-vault/tokens");
    expect(request.init.credentials).toBe("omit");
    expect(request.init.headers).toEqual({
      "Content-Type": "application/json",
      "X-CCS-Auth-Vault-Sync": "browser-extension",
      "X-CCS-Auth-Vault-Session": "session-token",
    });
    expect(request.init.headers).not.toHaveProperty("X-CCS-Session");
  });

  it("requires host access for remote HTTPS CCS sync origins", () => {
    expect(getRequiredSyncOrigins("http://127.0.0.1:17666")).toEqual([]);
    expect(getRequiredSyncOrigins("https://ccs.example.com")).toEqual([
      "https://ccs.example.com/*",
    ]);
  });

  it("formats disabled auth vault responses with an actionable diagnostic", () => {
    expect(
      formatSyncError(
        {
          error: "capability_disabled",
          capability: "auth-vault",
          message:
            "This capability is disabled in the current ccs-web profile.",
        },
        403,
      ),
    ).toBe(
      "远端 CCS 当前未开启 Auth Vault 接收能力，请先在远端 CCS 设置中打开临时接收开关后再同步。",
    );
  });

  it("formats closed receive window responses with an actionable diagnostic", () => {
    expect(
      formatSyncError(
        {
          ok: false,
          error: "auth_vault_receive_window_closed",
        },
        403,
      ),
    ).toBe(
      "远端 CCS 未打开 Auth Vault 临时接收窗口，请先在远端 CCS 设置中打开接收开关后再同步。",
    );
  });

  it("formats busy receive window responses with a retry diagnostic", () => {
    expect(
      formatSyncError(
        {
          ok: false,
          error: "auth_vault_receive_window_busy",
        },
        409,
      ),
    ).toBe(
      "远端 CCS Auth Vault 临时接收窗口正在处理另一条同步，请稍后重试；窗口不会因此关闭。",
    );
  });
});
