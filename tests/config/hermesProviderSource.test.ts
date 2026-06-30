import { describe, expect, it } from "vitest";
import {
  HERMES_PROVIDER_SOURCE_DICT,
  HERMES_PROVIDER_SOURCE_FIELD,
  isHermesReadOnlyProvider,
} from "@/config/hermesProviderSource";

describe("hermesProviderSource", () => {
  it("marks Hermes providers from the providers dict as read-only", () => {
    expect(
      isHermesReadOnlyProvider({
        [HERMES_PROVIDER_SOURCE_FIELD]: HERMES_PROVIDER_SOURCE_DICT,
      }),
    ).toBe(true);
  });

  it("does not mark custom-list or malformed providers as read-only", () => {
    expect(
      isHermesReadOnlyProvider({
        [HERMES_PROVIDER_SOURCE_FIELD]: "custom_providers",
      }),
    ).toBe(false);
    expect(isHermesReadOnlyProvider(null)).toBe(false);
    expect(isHermesReadOnlyProvider("providers_dict")).toBe(false);
  });
});
