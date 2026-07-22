#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const VALID_MODES = new Set(["quick", "standard", "release"]);
const RELEASE_SKIP_FLAGS = new Set(["-SkipDocker", "-SkipDesktopPreflight"]);

const ps = (...args) => [
  "powershell",
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  ...args,
];

const step = (name, command) => ({ name, command });

const BASE_STEPS = [
  step("git diff --check", ["git", "diff", "--check"]),
  step("secret preflight (changed)", [
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    [
      "$ErrorActionPreference = 'Stop'",
      "$distro = if ($env:CCS_WSL_DISTRO) { $env:CCS_WSL_DISTRO } else { 'Ubuntu' }",
      "function Convert-ToWslPath([string] $Path) { $normalized = ($Path -replace '/', '\\'); $full = [System.IO.Path]::GetFullPath($normalized); if ($full -notmatch '^([A-Za-z]):\\\\(.*)$') { throw \"Only drive-letter Windows paths are supported: $full\" }; return '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\\\', '/') }",
      "$root = (Resolve-Path -LiteralPath '.').Path",
      "$gitDir = (git rev-parse --git-dir).Trim()",
      "$gitCommonDir = (git rev-parse --git-common-dir).Trim()",
      "$wslRoot = Convert-ToWslPath $root",
      "$wslGitDir = Convert-ToWslPath $gitDir",
      "$wslGitCommonDir = Convert-ToWslPath $gitCommonDir",
      "wsl.exe -d $distro -- bash -lc \"cd '$wslRoot' && GIT_DIR='$wslGitDir' GIT_COMMON_DIR='$wslGitCommonDir' GIT_WORK_TREE='$wslRoot' CCS_PREFLIGHT_SCOPE=changed ./scripts/ccs-secret-preflight.sh\"",
      "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
    ].join("; "),
  ]),
];

const STANDARD_STEPS_BY_CATEGORY = {
  "token-saver": [
    step("token saver overlays", ps("-File", "scripts/verify-token-cost-savers.ps1")),
  ],
  "caveman": [
    step("caveman release gate", ps("-File", "scripts/verify-caveman-release-gate.ps1")),
  ],
  "overlay-governance": [
    step("official upstream alignment", ps("-File", "scripts/verify-official-upstream-alignment.ps1")),
    step("local overlay governance", ps("-File", "scripts/verify-local-overlays.ps1")),
  ],
  "core-backend": [
    step("official upstream alignment", ps("-File", "scripts/verify-official-upstream-alignment.ps1")),
    step("local overlay governance", ps("-File", "scripts/verify-local-overlays.ps1")),
    step("core backend checks", [
      "powershell",
      "-NoProfile",
      "-Command",
      [
        "cargo test --manifest-path src-tauri/Cargo.toml codex_chat --lib",
        "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
        "cargo test --manifest-path src-tauri/Cargo.toml s3 --lib",
        "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
        "cargo check --manifest-path src-tauri/Cargo.toml --no-default-features --features headless",
        "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
      ].join("; "),
    ]),
  ],
  "server-rpc": [
    step("server RPC checks", [
      "powershell",
      "-NoProfile",
      "-Command",
      [
        "cargo test --manifest-path crates/server/Cargo.toml",
        "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
        "cargo test --manifest-path crates/core/Cargo.toml",
        "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
      ].join("; "),
    ]),
  ],
  frontend: [
    step("frontend typecheck", ["powershell", "-NoProfile", "-Command", "& .\\node_modules\\.bin\\tsc.cmd --noEmit"]),
    step("frontend unit tests", [
      "powershell",
      "-NoProfile",
      "-Command",
      "& .\\node_modules\\.bin\\vitest.cmd run --testTimeout=15000",
    ]),
    step("frontend web build", ["powershell", "-NoProfile", "-Command", "& .\\node_modules\\.bin\\vite.cmd build --mode web"]),
  ],
  "docker-runtime": [
    step("docker runtime release required", [
      "node",
      "-e",
      "console.log('docker_runtime_release_required=true'); console.log('Run pnpm gate:release or scripts/publish-local-wsl-ccs-web.ps1 for Docker runtime smoke.');",
    ]),
  ],
};

const MATCHERS = [
  {
    group: 1,
    category: "overlay-governance",
    patterns: [/^docs\/ccs-(fork-overlay-ledger|local-change-groups|official-upstream-migration|specified-change-ledger)\.md$/, /^scripts\/verify-(official-upstream-alignment|local-overlays)\.ps1$/],
  },
  {
    group: 2,
    category: "token-saver",
    patterns: [/^src-tauri\/src\/proxy\/(forwarder|token_saver|token_filter_engine|body_filter|types)\.rs$/, /^src-tauri\/fixtures\/token-cost-savers\//, /^scripts\/verify-token-cost-savers\.ps1$/],
  },
  {
    group: 3,
    category: "caveman",
    patterns: [/^src-tauri\/src\/(commands\/prompt|prompt|services\/prompt)\.rs$/, /^src\/components\/prompts\/PromptPanel\.tsx$/, /^tests\/components\/PromptPanel\./, /^scripts\/(verify|new)-caveman-/],
  },
  {
    group: 5,
    category: "core-backend",
    patterns: [/^src-tauri\/src\//, /^vitest\.config\.ts$/],
  },
  {
    group: 6,
    category: "server-rpc",
    patterns: [/^crates\/(server|core)\//, /^src\/lib\/transport\/wsTransport\.ts$/],
  },
  {
    group: 7,
    category: "frontend",
    patterns: [/^src\/(App|components|hooks|lib|types|utils)\//, /^tests\/(components|hooks|lib|utils)\//],
  },
  {
    group: 8,
    category: "frontend",
    patterns: [/^src\/config\//, /^tests\/config\//, /^src-tauri\/src\/resources\//],
  },
  {
    group: 9,
    category: "frontend",
    patterns: [/^src\/i18n\//, /^src\/components\/settings\/LanguageSettings\.tsx$/, /^tests\/lib\/(i18n|settingsSchema)\.test\.ts$/],
  },
  {
    group: 10,
    category: "frontend",
    patterns: [/usage/i],
  },
  {
    group: 11,
    category: "overlay-governance",
    patterns: [/^(README|CONTRIBUTING|SECURITY|SUPPORT)\.md$/, /^docs\/user-manual\//, /^flatpak\//, /^skills\/cc-switch-release\//],
  },
  {
    group: 12,
    category: "docker-runtime",
    patterns: [/^Dockerfile\.web$/, /^\.dockerignore$/, /^docker-compose\.ccs-web\.yml$/, /^scripts\/(ccs-prod-probe|ccs-secret-preflight|publish-local-wsl-ccs-web|verify-ccs-3-16-2-release-gate)\./, /^docs\/ccs-(production-runbook|release-observability-plan)\.md$/],
  },
];

function normalizePath(path) {
  return String(path).replace(/\\/g, "/").replace(/^\.\//, "");
}

function uniqueSortedNumbers(values) {
  return [...new Set(values)].sort((a, b) => a - b);
}

function uniqueInOrder(values) {
  return values.filter((value, index) => values.indexOf(value) === index);
}

export function classifyChangedPaths(changedPaths) {
  const groups = [];
  const categories = [];

  for (const rawPath of changedPaths) {
    const path = normalizePath(rawPath);
    for (const matcher of MATCHERS) {
      if (matcher.patterns.some((pattern) => pattern.test(path))) {
        groups.push(matcher.group);
        categories.push(matcher.category);
      }
    }
  }

  return {
    groups: uniqueSortedNumbers(groups),
    categories: uniqueInOrder(categories),
  };
}

function dedupeSteps(steps) {
  const seen = new Set();
  return steps.filter((candidate) => {
    const key = `${candidate.name}\0${candidate.command.join("\0")}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

export function buildGatePlan({ mode, changedPaths = [] }) {
  if (!VALID_MODES.has(mode)) {
    throw new Error(`Unknown release gate mode: ${mode}`);
  }

  if (mode === "release") {
    return {
      mode,
      scope: "all",
      categories: ["release"],
      releaseEvidence: true,
      steps: [
        step("full release gate", ps("-File", "scripts/verify-ccs-3-16-2-release-gate.ps1")),
      ],
    };
  }

  const classification = classifyChangedPaths(changedPaths);
  if (mode === "quick") {
    return {
      mode,
      scope: "changed",
      categories: classification.categories,
      releaseEvidence: false,
      steps: [...BASE_STEPS],
    };
  }

  const standardSteps = [...BASE_STEPS];
  for (const category of classification.categories) {
    standardSteps.push(...(STANDARD_STEPS_BY_CATEGORY[category] ?? []));
  }

  return {
    mode,
    scope: "changed",
    categories: classification.categories,
    releaseEvidence: false,
    steps: dedupeSteps(standardSteps),
  };
}

function getChangedPaths() {
  const commands = [
    ["git", ["diff", "--name-only", "--diff-filter=ACMR"]],
    ["git", ["diff", "--cached", "--name-only", "--diff-filter=ACMR"]],
    ["git", ["ls-files", "--others", "--exclude-standard"]],
  ];
  const paths = [];

  for (const [command, args] of commands) {
    const result = spawnSync(command, args, { encoding: "utf8" });
    if (result.status !== 0) {
      continue;
    }
    paths.push(
      ...result.stdout
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean),
    );
  }

  return uniqueInOrder(paths.map(normalizePath));
}

function printPlan(plan) {
  console.log(`release_gate_profile=${plan.mode}`);
  console.log(`release_gate_scope=${plan.scope}`);
  console.log(`release_gate_categories=${plan.categories.join(",") || "none"}`);
  console.log(`release_gate_evidence=${plan.releaseEvidence}`);
  if (!plan.releaseEvidence) {
    console.log("not_release_evidence=true");
  }
  for (const [index, step] of plan.steps.entries()) {
    console.log(`${index + 1}. ${step.name}`);
    console.log(`   ${step.command.join(" ")}`);
  }
}

function runStep(step) {
  const [command, ...args] = step.command;
  console.log(`==> ${step.name}`);
  const startedAt = process.hrtime.bigint();
  const result = spawnSync(command, args, { stdio: "inherit", shell: false });
  const elapsedSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
  console.log(`<== ${step.name} elapsed=${elapsedSeconds.toFixed(2)}s`);
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function main() {
  const [mode = "quick", ...args] = process.argv.slice(2);
  const printOnly = args.includes("--print");

  for (const arg of args) {
    if (RELEASE_SKIP_FLAGS.has(arg)) {
      throw new Error(`Release gate profiles do not accept skip flag: ${arg}`);
    }
  }

  const changedPaths = getChangedPaths();
  const plan = buildGatePlan({ mode, changedPaths });
  printPlan(plan);

  if (!printOnly) {
    for (const plannedStep of plan.steps) {
      runStep(plannedStep);
    }
  }
}

if (fileURLToPath(import.meta.url) === path.resolve(process.argv[1] ?? "")) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
