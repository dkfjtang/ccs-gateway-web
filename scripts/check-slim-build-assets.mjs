import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { gzipSync } from "node:zlib";

const repoRoot = process.cwd();
const distDir = path.join(repoRoot, "dist");
const assetsDir = path.join(distDir, "assets");
const maxInitialGzipKbRaw = process.env.SLIM_MAX_INITIAL_GRAPH_GZIP_KB ?? "390";
const maxInitialGzipKb = Number(maxInitialGzipKbRaw);
const maxInitialAssetCountRaw =
  process.env.SLIM_MAX_INITIAL_GRAPH_ASSETS ?? "20";
const maxInitialAssetCount = Number(maxInitialAssetCountRaw);

const indexHtml = await readFile(path.join(distDir, "index.html"), "utf8");

const initialBlocklist = [
  "AgentsDefaultsPanel",
  "EnvPanel",
  "HermesMemoryPanel",
  "OpenClawHealthBanner",
  "SkillsPage",
  "ToolsPanel",
  "UnifiedMcpPanel",
  "UnifiedSkillsPanel",
  "WorkspaceFilesPanel",
];

const directAssetBlocklist = ["dds-", "shengsuanyun-"];
const initialAssetPrefixBlocklist = [
  "app-forms-",
  "app-dnd-",
  "app-sessions-",
  "vendor-flexsearch-",
  "vendor-dnd-",
  "vendor-forms-",
  "vendor-motion-",
];
const initialAssetPattern =
  /<(?:script|link)\b[^>]+(?:src|href)=["']\.\/assets\/([^"']+)["'][^>]*>/g;
const staticImportPattern =
  /\bimport(?:\s*["']\.\/([^"']+)["']|[^;"'()]*?\bfrom\s*["']\.\/([^"']+)["'])/g;
const staticExportPattern =
  /\bexport\s+(?:[^;"'()]*?\bfrom\s*)["']\.\/([^"']+)["']/g;
const dynamicImportPattern = /\bimport\(\s*["']\.\/([^"']+)["']\s*\)/g;
const cssUrlPattern = /url\(["']?\.\/([^"')]+)["']?\)/g;
const recoverableRouteAssetPrefixes = ["SettingsPage-"];

const failures = [];
const initialAssets = [];
const eagerAssets = new Set();
const scannedAssets = new Set();
const assetSizes = new Map();
const initialDynamicAssets = new Set();
const recoverableRouteGraphs = new Map();

if (!Number.isFinite(maxInitialGzipKb) || maxInitialGzipKb <= 0) {
  failures.push(
    `SLIM_MAX_INITIAL_GRAPH_GZIP_KB must be a positive number, got ${JSON.stringify(
      process.env.SLIM_MAX_INITIAL_GRAPH_GZIP_KB,
    )}`,
  );
}

if (!Number.isInteger(maxInitialAssetCount) || maxInitialAssetCount <= 0) {
  failures.push(
    `SLIM_MAX_INITIAL_GRAPH_ASSETS must be a positive integer, got ${JSON.stringify(
      process.env.SLIM_MAX_INITIAL_GRAPH_ASSETS,
    )}`,
  );
}

// Lazy chunks may still be emitted into dist. The slim gate only rejects assets
// reachable from index.html through static JS imports or CSS url() references.
for (const marker of initialBlocklist) {
  if (indexHtml.includes(marker)) {
    failures.push(`index.html directly references disabled chunk ${marker}`);
  }
}

for (const match of indexHtml.matchAll(initialAssetPattern)) {
  initialAssets.push(match[1]);
}

if (initialAssets.length === 0) {
  failures.push("index.html does not reference any initial build assets");
}

async function scanStaticAssetGraph(
  asset,
  graphAssets,
  {
    dynamicAssets = null,
    scannedGraphAssets = new Set(),
    missingAssetSource = "index.html",
  } = {},
) {
  if (scannedGraphAssets.has(asset)) {
    return;
  }
  scannedGraphAssets.add(asset);
  graphAssets.add(asset);

  if (scannedAssets.has(asset)) {
    return;
  }
  scannedAssets.add(asset);

  const assetPath = path.join(assetsDir, asset);
  const assetStat = await stat(assetPath).catch(() => null);
  if (assetStat == null) {
    failures.push(`${missingAssetSource} references missing asset ${asset}`);
    return;
  }
  assetSizes.set(asset, {
    bytes: assetStat.size,
    gzipBytes: null,
  });

  if (!asset.endsWith(".js") && !asset.endsWith(".css")) {
    return;
  }

  const assetBuffer = await readFile(assetPath).catch(() => null);
  const assetText = assetBuffer?.toString("utf8") ?? null;
  if (assetText == null) {
    failures.push(`${missingAssetSource} references missing asset ${asset}`);
    return;
  }
  assetSizes.set(asset, {
    bytes: assetStat.size,
    gzipBytes: gzipSync(assetBuffer).length,
  });

  if (asset.endsWith(".js")) {
    for (const match of assetText.matchAll(staticImportPattern)) {
      await scanStaticAssetGraph(match[1] ?? match[2], graphAssets, {
        dynamicAssets,
        scannedGraphAssets,
        missingAssetSource,
      });
    }
    for (const match of assetText.matchAll(staticExportPattern)) {
      await scanStaticAssetGraph(match[1], graphAssets, {
        dynamicAssets,
        scannedGraphAssets,
        missingAssetSource,
      });
    }
    if (dynamicAssets) {
      for (const match of assetText.matchAll(dynamicImportPattern)) {
        dynamicAssets.add(match[1]);
      }
    }
  }

  if (asset.endsWith(".css")) {
    for (const match of assetText.matchAll(cssUrlPattern)) {
      await scanStaticAssetGraph(match[1], graphAssets, {
        dynamicAssets,
        scannedGraphAssets,
        missingAssetSource,
      });
    }
  }
}

for (const asset of initialAssets) {
  await scanStaticAssetGraph(asset, eagerAssets, {
    dynamicAssets: initialDynamicAssets,
  });
}

for (const routeAsset of initialDynamicAssets) {
  if (
    !recoverableRouteAssetPrefixes.some((prefix) =>
      routeAsset.startsWith(prefix),
    )
  ) {
    continue;
  }

  const routeAssets = new Set();
  await scanStaticAssetGraph(routeAsset, routeAssets, {
    scannedGraphAssets: new Set(),
    missingAssetSource: `recoverable route asset ${routeAsset}`,
  });
  recoverableRouteGraphs.set(routeAsset, routeAssets);
}

for (const marker of [...initialBlocklist, ...directAssetBlocklist]) {
  const matches = [...eagerAssets].filter((name) => name.startsWith(marker));
  if (matches.length > 0) {
    failures.push(`initial import graph references ${matches.join(", ")}`);
  }
}

for (const marker of initialAssetPrefixBlocklist) {
  const matches = [...eagerAssets].filter((name) => name.startsWith(marker));
  if (matches.length > 0) {
    failures.push(
      `initial import graph eagerly includes slim-lazy asset ${matches.join(
        ", ",
      )}`,
    );
  }
}

for (const [routeAsset, routeAssets] of recoverableRouteGraphs) {
  for (const marker of initialAssetPrefixBlocklist) {
    const matches = [...routeAssets].filter((name) => name.startsWith(marker));
    if (matches.length > 0) {
      failures.push(
        `recoverable route asset ${routeAsset} eagerly includes slim-lazy asset ${matches.join(
          ", ",
        )}`,
      );
    }
  }
}

const eagerSizeTotals = [...eagerAssets].reduce(
  (totals, asset) => {
    const size = assetSizes.get(asset);
    if (size == null) {
      return totals;
    }
    return {
      bytes: totals.bytes + size.bytes,
      gzipBytes: totals.gzipBytes + (size.gzipBytes ?? size.bytes),
    };
  },
  { bytes: 0, gzipBytes: 0 },
);
const eagerRawKb = eagerSizeTotals.bytes / 1024;
const eagerGzipKb = eagerSizeTotals.gzipBytes / 1024;

console.log(
  [
    `slim initial graph assets=${eagerAssets.size}`,
    `raw=${eagerRawKb.toFixed(2)}KB`,
    `gzip=${eagerGzipKb.toFixed(2)}KB`,
    Number.isInteger(maxInitialAssetCount) && maxInitialAssetCount > 0
      ? `assetBudget=${maxInitialAssetCount}`
      : `assetBudget=invalid(${JSON.stringify(maxInitialAssetCountRaw)})`,
    Number.isFinite(maxInitialGzipKb) && maxInitialGzipKb > 0
      ? `budget=${maxInitialGzipKb.toFixed(2)}KB`
      : `budget=invalid(${JSON.stringify(maxInitialGzipKbRaw)})`,
  ].join(" "),
);

if (Number.isFinite(maxInitialGzipKb) && eagerGzipKb > maxInitialGzipKb) {
  failures.push(
    `slim initial import graph gzip ${eagerGzipKb.toFixed(
      2,
    )}KB exceeds budget ${maxInitialGzipKb.toFixed(2)}KB`,
  );
}

if (
  Number.isInteger(maxInitialAssetCount) &&
  eagerAssets.size > maxInitialAssetCount
) {
  failures.push(
    `slim initial import graph asset count ${eagerAssets.size} exceeds budget ${maxInitialAssetCount}`,
  );
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("slim build asset checks passed");
