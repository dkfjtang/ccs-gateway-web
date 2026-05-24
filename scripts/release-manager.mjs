#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const projectRoot = path.resolve(scriptDir, "..");

const versionFiles = [
  "package.json",
  "src-tauri/Cargo.toml",
  "src-tauri/tauri.conf.json",
];

const semverPattern =
  /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

function usage() {
  console.log(`Usage:
  node scripts/release-manager.mjs sync <version>
  node scripts/release-manager.mjs release <version> [--message <msg>] [--tag <tag>] [--remote <remote>] [--push]

Commands:
  sync     Update all managed version files only.
  release  Update versions, stage managed files, commit staged changes, create an annotated tag, and optionally push.

Notes:
  - release requires a clean working tree except for already staged changes.
  - release commits the current index after staging managed version files.
  - managed version files:
      package.json
      src-tauri/Cargo.toml
      src-tauri/tauri.conf.json`);
}

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function runGit(args, options = {}) {
  const result = execFileSync("git", args, {
    cwd: projectRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });
  return typeof result === "string" ? result.trim() : "";
}

function ensureGitRepo() {
  const root = runGit(["rev-parse", "--show-toplevel"]);
  if (path.resolve(root) !== projectRoot) {
    fail(`script must run from repository root: ${projectRoot}`);
  }
}

function parseArgs(argv) {
  const [command, version, ...rest] = argv;
  if (!command || command === "--help" || command === "-h") {
    usage();
    process.exit(0);
  }

  const options = {
    message: "",
    push: false,
    remote: "origin",
    tag: "",
  };

  for (let index = 0; index < rest.length; index += 1) {
    const current = rest[index];
    switch (current) {
      case "--message":
        index += 1;
        options.message = rest[index] ?? "";
        if (!options.message) {
          fail("--message requires a value");
        }
        break;
      case "--remote":
        index += 1;
        options.remote = rest[index] ?? "";
        if (!options.remote) {
          fail("--remote requires a value");
        }
        break;
      case "--tag":
        index += 1;
        options.tag = rest[index] ?? "";
        if (!options.tag) {
          fail("--tag requires a value");
        }
        break;
      case "--push":
        options.push = true;
        break;
      default:
        fail(`unknown argument: ${current}`);
    }
  }

  if (!version) {
    fail("missing version argument");
  }

  if (!semverPattern.test(version)) {
    fail(`invalid version: ${version}`);
  }

  return { command, options, version };
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function replaceFirstMatch(content, pattern, replacement, file) {
  if (!pattern.test(content)) {
    fail(`could not find version field in ${file}`);
  }
  return content.replace(pattern, replacement);
}

function updateVersions(version) {
  const packageJsonPath = path.join(projectRoot, "package.json");
  const tauriConfigPath = path.join(projectRoot, "src-tauri/tauri.conf.json");
  const cargoTomlPath = path.join(projectRoot, "src-tauri/Cargo.toml");

  const packageJson = readJson(packageJsonPath);
  packageJson.version = version;
  writeJson(packageJsonPath, packageJson);

  const tauriConfig = readJson(tauriConfigPath);
  tauriConfig.version = version;
  writeJson(tauriConfigPath, tauriConfig);

  const cargoToml = fs.readFileSync(cargoTomlPath, "utf8");
  const updatedCargoToml = replaceFirstMatch(
    cargoToml,
    /^version = ".*"$/m,
    `version = "${version}"`,
    "src-tauri/Cargo.toml",
  );
  fs.writeFileSync(cargoTomlPath, updatedCargoToml);
}

function ensureCleanWorktree() {
  const unstaged = runGit(["diff", "--name-only"]);
  const untracked = runGit(["ls-files", "--others", "--exclude-standard"]);
  if (unstaged) {
    fail(
      `unstaged changes detected:\n${unstaged}\nStage or discard them before running release`,
    );
  }
  if (untracked) {
    fail(
      `untracked files detected:\n${untracked}\nStage or remove them before running release`,
    );
  }
}

function ensureStagedChangesExist() {
  const staged = runGit(["diff", "--cached", "--name-only"]);
  if (!staged) {
    fail("nothing staged for commit");
  }
}

function ensureOnBranch() {
  const branch = runGit(["branch", "--show-current"]);
  if (!branch) {
    fail("detached HEAD is not supported");
  }
  return branch;
}

function ensureTagAvailable(tag, remote) {
  const localTag = runGit(["tag", "--list", tag]);
  if (localTag === tag) {
    fail(`local tag already exists: ${tag}`);
  }

  const remoteTag = runGit(["ls-remote", "--tags", remote, `refs/tags/${tag}`]);
  if (remoteTag) {
    fail(`remote tag already exists on ${remote}: ${tag}`);
  }
}

function stageManagedFiles() {
  runGit(["add", ...versionFiles]);
}

function commit(message) {
  runGit(["commit", "-m", message], { stdio: "inherit" });
}

function createAnnotatedTag(tag) {
  runGit(["tag", "-a", tag, "-m", `Release ${tag}`], { stdio: "inherit" });
}

function push(remote, branch, tag) {
  runGit(["push", remote, branch], { stdio: "inherit" });
  runGit(["push", remote, tag], { stdio: "inherit" });
}

function main() {
  ensureGitRepo();

  const { command, options, version } = parseArgs(process.argv.slice(2));
  const tag = options.tag || `v${version}`;

  if (command === "sync") {
    updateVersions(version);
    console.log(`Updated versions to ${version}`);
    return;
  }

  if (command !== "release") {
    fail(`unknown command: ${command}`);
  }

  const branch = ensureOnBranch();
  ensureCleanWorktree();
  ensureTagAvailable(tag, options.remote);
  updateVersions(version);
  stageManagedFiles();
  ensureStagedChangesExist();

  const message = options.message || `release: ${tag}`;
  commit(message);
  createAnnotatedTag(tag);

  if (options.push) {
    push(options.remote, branch, tag);
  }

  console.log(`Release commit created for ${tag}`);
  if (!options.push) {
    console.log(`Push manually when ready: git push ${options.remote} ${branch} && git push ${options.remote} ${tag}`);
  }
}

main();
