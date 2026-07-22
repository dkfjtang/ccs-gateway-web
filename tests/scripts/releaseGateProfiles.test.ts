import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = process.cwd();
const gateScriptFile = path.resolve(repoRoot, "scripts/release-gate-profiles.mjs");
const gateScriptUrl = pathToFileURL(gateScriptFile).href;

async function buildFixturePlan() {
  const snippet = [
    "const gate = await import(process.argv[1]);",
    "const changedPaths = [",
    "  'src-tauri/src/proxy/forwarder.rs',",
    "  'src-tauri/src/services/s3_sync.rs',",
    "  'crates/server/src/api/dispatch.rs',",
    "  'docker-compose.ccs-web.yml',",
    "];",
    "const plan = gate.buildGatePlan({ mode: 'standard', changedPaths });",
    "console.log(JSON.stringify({",
    "  classification: gate.classifyChangedPaths(changedPaths),",
    "  stepNames: plan.steps.map((step) => step.name),",
    "  lastCommand: plan.steps.at(-1).command,",
    "}));",
  ].join(" ");

  const result = await execFileAsync(process.execPath, [
    "--input-type=module",
    "--eval",
    snippet,
    gateScriptUrl,
  ]);

  return JSON.parse(result.stdout) as {
    classification: {
      groups: number[];
      categories: string[];
    };
    stepNames: string[];
    lastCommand: string[];
  };
}

async function runGateScript(args: string[] = []) {
  return execFileAsync(process.execPath, [gateScriptFile, ...args], {
    cwd: repoRoot,
  });
}

describe("release gate profiles", () => {
  it("keeps release as a thin wrapper around the full gate", async () => {
    const result = await runGateScript(["release", "--print"]);

    expect(result.stdout).toContain("release_gate_profile=release");
    expect(result.stdout).toContain("release_gate_evidence=true");
    expect(result.stdout).toContain("full release gate");
    expect(result.stdout).toContain("scripts/verify-ccs-3-16-2-release-gate.ps1");
    expect(result.stdout).not.toContain("-SkipDocker");
    expect(result.stdout).not.toContain("-SkipDesktopPreflight");
  });

  it("uses changed-scope secret preflight and diff check for quick feedback", async () => {
    const result = await runGateScript(["quick", "--print"]);

    expect(result.stdout).toContain("release_gate_scope=changed");
    expect(result.stdout).toContain("git diff --check");
    expect(result.stdout).toContain("secret preflight (changed)");
    expect(result.stdout).toContain("GIT_WORK_TREE=");
    expect(result.stdout).toContain("GIT_COMMON_DIR=");
  });

  it("expands standard validation based on changed group categories", async () => {
    const fixture = await buildFixturePlan();

    expect(fixture.classification).toEqual({
      groups: [2, 5, 6, 12],
      categories: [
        "token-saver",
        "core-backend",
        "server-rpc",
        "docker-runtime",
      ],
    });
    expect(fixture.stepNames).toEqual([
      "git diff --check",
      "secret preflight (changed)",
      "token saver overlays",
      "official upstream alignment",
      "local overlay governance",
      "core backend checks",
      "server RPC checks",
      "docker runtime release required",
    ]);
    expect(fixture.lastCommand).toEqual([
      "node",
      "-e",
      "console.log('docker_runtime_release_required=true'); console.log('Run pnpm gate:release or scripts/publish-local-wsl-ccs-web.ps1 for Docker runtime smoke.');",
    ]);

    const result = await runGateScript(["standard", "--print"]);

    expect(result.stdout).toContain("release_gate_profile=standard");
    expect(result.stdout).toContain("release_gate_evidence=false");
    expect(result.stdout).toContain("not_release_evidence=true");
  });

  it("rejects unknown modes", async () => {
    await expect(runGateScript(["banana"])).rejects.toMatchObject({
      stderr: expect.stringContaining("Unknown release gate mode"),
    });
  });

  it("exposes package scripts for each profile", async () => {
    const packageJson = JSON.parse(await readFile("package.json", "utf8"));

    expect(packageJson.scripts).toMatchObject({
      "gate:quick": "node scripts/release-gate-profiles.mjs quick",
      "gate:standard": "node scripts/release-gate-profiles.mjs standard",
      "gate:release": "node scripts/release-gate-profiles.mjs release",
    });
  });

  it("adds elapsed timing output to existing PowerShell gate wrappers", async () => {
    const scripts = [
      "scripts/verify-ccs-3-16-2-release-gate.ps1",
      "scripts/verify-local-overlays.ps1",
      "scripts/verify-token-cost-savers.ps1",
    ];

    for (const script of scripts) {
      const content = await readFile(script, "utf8");
      expect(content).toContain("[System.Diagnostics.Stopwatch]::StartNew()");
      expect(content).toContain("elapsedMs=");
    }
  });

  it("marks non-release profiles as not release evidence", async () => {
    const quick = await runGateScript(["quick", "--print"]);
    const standard = await runGateScript(["standard", "--print"]);
    const release = await runGateScript(["release", "--print"]);

    expect(quick.stdout).toContain("release_gate_evidence=false");
    expect(quick.stdout).toContain("not_release_evidence=true");
    expect(standard.stdout).toContain("release_gate_evidence=false");
    expect(standard.stdout).toContain("not_release_evidence=true");
    expect(release.stdout).toContain("release_gate_evidence=true");
    expect(release.stdout).not.toContain("not_release_evidence=true");
  });
});
