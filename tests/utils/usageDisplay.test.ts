import { describe, expect, it } from "vitest";
import { formatUsageDataSummary } from "@/utils/usageDisplay";

const labels = {
  invalid: "Invalid",
  remaining: "Remaining:",
  used: "Used:",
};

describe("formatUsageDataSummary", () => {
  it("formats used percentage when remaining is omitted", () => {
    expect(
      formatUsageDataSummary(
        {
          planName: "Coco OpenRouter",
          used: 55,
          total: 100,
          unit: "%",
        },
        labels,
      ),
    ).toBe("[Coco OpenRouter] Used: 55%");
  });

  it("formats remaining when present", () => {
    expect(
      formatUsageDataSummary(
        {
          planName: "Balance",
          remaining: 12.5,
          unit: "USD",
        },
        labels,
      ),
    ).toBe("[Balance] Remaining: 12.50 USD");
  });

  it("formats invalid results without requiring quota fields", () => {
    expect(
      formatUsageDataSummary(
        {
          isValid: false,
          invalidMessage: "Unauthorized",
        },
        labels,
      ),
    ).toBe("Unauthorized");
  });

  it("ignores probe-only fields in the compact data summary", () => {
    expect(
      formatUsageDataSummary(
        {
          planName: "Balance",
          used: 4,
          remaining: 6,
          total: 10,
          unit: "USD",
          resetsAt: "2026-07-01T00:00:00Z",
        },
        labels,
      ),
    ).toBe("[Balance] Used: 40% / Remaining: 6 USD");
  });
});
