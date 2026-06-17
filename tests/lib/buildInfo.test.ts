import { describe, expect, it, vi } from "vitest";
import {
  getCurrentDocumentBuildId,
  shouldNotifyBuildUpdate,
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
});
