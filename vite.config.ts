import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { codeInspectorPlugin } from "code-inspector-plugin";
import pkg from "./package.json" with { type: "json" };

const backendPort = Number(process.env.CC_SWITCH_PORT || 17666);
const VENDOR_CHUNK_GROUPS = {
  react: ["react", "react-dom", "scheduler"],
  query: ["@tanstack/react-query"],
  charts: ["recharts", "d3"],
  motion: ["framer-motion"],
  ui: ["@radix-ui", "lucide-react", "sonner", "cmdk", "@dnd-kit"],
  forms: ["react-hook-form", "@hookform/resolvers", "zod"],
  i18n: ["i18next", "react-i18next"],
} as const;
const SKIP_MANUAL_CHUNK_PACKAGES = new Set([
  "detect-node-es",
  "html-parse-stringify",
  "tiny-invariant",
  "void-elements",
]);

function getNodeModulePackageName(id: string): string | null {
  const nodeModulesMarker = "/node_modules/";
  const markerIndex = id.lastIndexOf(nodeModulesMarker);
  if (markerIndex === -1) {
    return null;
  }

  const modulePath = id.slice(markerIndex + nodeModulesMarker.length);
  const segments = modulePath.split("/");
  if (segments.length === 0 || !segments[0]) {
    return null;
  }

  if (segments[0].startsWith("@") && segments[1]) {
    return `${segments[0]}/${segments[1]}`;
  }

  return segments[0];
}

function getVendorChunkName(id: string): string | undefined {
  const packageName = getNodeModulePackageName(id);
  if (!packageName) {
    return undefined;
  }

  if (SKIP_MANUAL_CHUNK_PACKAGES.has(packageName)) {
    return undefined;
  }

  if (packageName === "prettier") {
    if (id.includes("parser-babel")) {
      return "vendor-prettier-parser-babel";
    }
    if (id.includes("plugins/estree")) {
      return "vendor-prettier-plugin-estree";
    }
    if (id.includes("standalone")) {
      return "vendor-prettier-standalone";
    }
  }

  for (const [chunkName, packages] of Object.entries(VENDOR_CHUNK_GROUPS)) {
    if (packages.some((pkgPrefix) => packageName === pkgPrefix || packageName.startsWith(`${pkgPrefix}/`))) {
      return `vendor-${chunkName}`;
    }
  }

  if (packageName.startsWith("@tauri-apps/")) {
    return "vendor-platform";
  }

  return `vendor-${packageName.replace(/[\/@]/g, "-")}`;
}

function getAppChunkName(id: string): string | undefined {
  if (!id.includes("/src/")) {
    return undefined;
  }

  if (id.includes("/src/lib/api/") || id.includes("/src/lib/query/")) {
    return "app-data";
  }

  if (id.includes("/src/hooks/")) {
    return "app-hooks";
  }

  if (id.includes("/src/components/ui/")) {
    return "app-ui";
  }

  if (id.includes("/src/lib/transport/") || id.includes("/src/platform/")) {
    return "app-platform";
  }

  if (id.includes("/src/i18n/")) {
    return "app-i18n";
  }

  return undefined;
}

export default defineConfig(({ command, mode }) => {
  const isWebMode = mode === "web";
  const platformSuffix = isWebMode ? "web" : "tauri";

  return {
    root: "src",
    plugins: [
      command === "serve" &&
        codeInspectorPlugin({
          bundler: "vite",
        }),
      react(),
    ].filter(Boolean),
    base: "./",
    build: {
      outDir: "../dist",
      emptyOutDir: true,
      rollupOptions: {
        output: {
          manualChunks(id) {
            return getAppChunkName(id) ?? getVendorChunkName(id);
          },
        },
      },
    },
    server: {
      port: 3000,
      strictPort: true,
      proxy: {
        "/api": {
          target: `http://127.0.0.1:${backendPort}`,
          changeOrigin: true,
          ws: true,
        },
      },
    },
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
        "@platform/bootstrap": path.resolve(
          __dirname,
          `./src/platform/bootstrap.${platformSuffix}.ts`,
        ),
        "@platform/transport-impl": path.resolve(
          __dirname,
          `./src/lib/transport/transport.impl.${platformSuffix}.ts`,
        ),
        "@platform/updater-impl": path.resolve(
          __dirname,
          `./src/lib/updater.${platformSuffix}.ts`,
        ),
        "@platform/platform-paths-impl": path.resolve(
          __dirname,
          `./src/lib/platform-paths.${platformSuffix}.ts`,
        ),
      },
    },
    define: {
      __APP_VERSION__: JSON.stringify(pkg.version),
    },
    clearScreen: false,
    envPrefix: ["VITE_", "TAURI_"],
  };
});
