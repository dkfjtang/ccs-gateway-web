import { execFile } from "node:child_process";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const checkerPath = path.join(repoRoot, "scripts/check-slim-build-assets.mjs");

async function createFixture(files: Record<string, string>) {
  const fixtureRoot = await mkdtemp(
    path.join(tmpdir(), "ccs-slim-assets-test-"),
  );

  for (const [relativePath, content] of Object.entries(files)) {
    const fullPath = path.join(fixtureRoot, relativePath);
    await mkdir(path.dirname(fullPath), { recursive: true });
    await writeFile(fullPath, content, "utf8");
  }

  return fixtureRoot;
}

async function runChecker(cwd: string) {
  return execFileAsync(process.execPath, [checkerPath], {
    cwd,
    env: {
      ...process.env,
      SLIM_MAX_INITIAL_GRAPH_ASSETS: "10",
      SLIM_MAX_INITIAL_GRAPH_GZIP_KB: "1000",
    },
  });
}

describe("check-slim-build-assets", () => {
  it("passes when slim-lazy chunks are only present outside the initial graph", async () => {
    const cwd = await createFixture({
      "dist/index.html": [
        '<script type="module" src="./assets/index-ok.js"></script>',
        '<link rel="stylesheet" href="./assets/index-ok.css">',
      ].join("\n"),
      "dist/assets/index-ok.js": [
        'import "./app-ui-ok.js";',
        'const lazy = () => import("./app-forms-lazy.js");',
        "void lazy;",
      ].join("\n"),
      "dist/assets/index-ok.css": ".root{color:currentColor}",
      "dist/assets/app-ui-ok.js": "export const ok = true;",
      "dist/assets/app-forms-lazy.js":
        'import "./vendor-forms-lazy.js"; export const lazy = true;',
      "dist/assets/vendor-forms-lazy.js": "export const forms = true;",
    });

    await expect(runChecker(cwd)).resolves.toMatchObject({
      stdout: expect.stringContaining("slim build asset checks passed"),
    });
  });

  it("rejects slim-lazy chunks referenced by index.html modulepreload", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<link rel="modulepreload" href="./assets/app-forms-eager.js">',
      "dist/assets/app-forms-eager.js": "export const eager = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset app-forms-eager.js",
      ),
    });
  });

  it("rejects slim-lazy chunks reached through static JS imports", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<script type="module" src="./assets/index-eager.js"></script>',
      "dist/assets/index-eager.js":
        'import "./vendor-forms-eager.js"; export const eager = true;',
      "dist/assets/vendor-forms-eager.js": "export const forms = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset vendor-forms-eager.js",
      ),
    });
  });

  it("rejects motion chunks reached through static JS imports", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<script type="module" src="./assets/index-eager.js"></script>',
      "dist/assets/index-eager.js":
        'import "./vendor-motion-eager.js"; export const eager = true;',
      "dist/assets/vendor-motion-eager.js": "export const motion = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset vendor-motion-eager.js",
      ),
    });
  });

  it("rejects slim-lazy chunks reached through CSS urls", async () => {
    const cwd = await createFixture({
      "dist/index.html": '<link rel="stylesheet" href="./assets/index.css">',
      "dist/assets/index.css":
        '.root{background-image:url("./app-sessions-eager.js")}',
      "dist/assets/app-sessions-eager.js": "export const eager = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset app-sessions-eager.js",
      ),
    });
  });

  it("rejects motion chunks referenced by index.html modulepreload", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<link rel="modulepreload" href="./assets/vendor-motion-eager.js">',
      "dist/assets/vendor-motion-eager.js": "export const eager = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset vendor-motion-eager.js",
      ),
    });
  });

  it("rejects dnd chunks referenced by index.html modulepreload", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<link rel="modulepreload" href="./assets/vendor-dnd-eager.js">',
      "dist/assets/vendor-dnd-eager.js": "export const eager = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset vendor-dnd-eager.js",
      ),
    });
  });

  it("rejects app dnd chunks referenced by index.html modulepreload", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<link rel="modulepreload" href="./assets/app-dnd-eager.js">',
      "dist/assets/app-dnd-eager.js": "export const eager = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "initial import graph eagerly includes slim-lazy asset app-dnd-eager.js",
      ),
    });
  });

  it("rejects motion chunks reached from recoverable settings route chunks", async () => {
    const cwd = await createFixture({
      "dist/index.html":
        '<script type="module" src="./assets/index-route.js"></script>',
      "dist/assets/index-route.js": [
        'const openSettings = () => import("./SettingsPage-route.js");',
        "void openSettings;",
      ].join("\n"),
      "dist/assets/SettingsPage-route.js":
        'import "./vendor-motion-route.js"; export const SettingsPage = true;',
      "dist/assets/vendor-motion-route.js": "export const motion = true;",
    });

    await expect(runChecker(cwd)).rejects.toMatchObject({
      stderr: expect.stringContaining(
        "recoverable route asset SettingsPage-route.js eagerly includes slim-lazy asset vendor-motion-route.js",
      ),
    });
  });
});
