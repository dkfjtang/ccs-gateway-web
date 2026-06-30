import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ProviderIcon } from "@/components/ProviderIcon";
import { loadIconUrl } from "@/icons/extracted";

vi.mock("@/icons/extracted", () => ({
  getIcon: (name: string) =>
    name === "claude" ? "<svg data-testid='inline-icon'></svg>" : "",
  hasIcon: (name: string) => ["claude", "dds"].includes(name),
  getIconMetadata: () => undefined,
  isUrlIcon: (name: string) => name === "dds",
  loadIconUrl: vi.fn(async (name: string) =>
    name === "dds" ? "/assets/dds.svg" : "",
  ),
}));

describe("ProviderIcon", () => {
  const loadIconUrlMock = vi.mocked(loadIconUrl);

  it("loads URL icons on demand instead of needing a static URL registry", async () => {
    render(<ProviderIcon icon="dds" name="DDS" size={24} />);

    expect(screen.getByText("D")).toBeInTheDocument();

    const image = await screen.findByRole("img", { name: "DDS" });
    expect(image).toHaveAttribute("src", "/assets/dds.svg");
  });

  it("renders inline SVG icons without async URL loading", async () => {
    render(<ProviderIcon icon="claude" name="Claude" size={24} />);

    await waitFor(() =>
      expect(screen.getByTitle("Claude").innerHTML).toContain(
        "data-testid=\"inline-icon\"",
      ),
    );
  });

  it("keeps the fallback when a URL icon fails to load", async () => {
    loadIconUrlMock.mockRejectedValueOnce(new Error("missing icon asset"));

    render(<ProviderIcon icon="dds" name="DDS" size={24} />);

    expect(screen.getByText("D")).toBeInTheDocument();
    await waitFor(() => expect(loadIconUrlMock).toHaveBeenCalledWith("dds"));
    expect(screen.queryByRole("img", { name: "DDS" })).not.toBeInTheDocument();
    expect(screen.getByText("D")).toBeInTheDocument();
  });
});
