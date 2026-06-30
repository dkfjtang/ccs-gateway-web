import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { UpdateProvider } from "./contexts/UpdateContext";
import { AuthProvider } from "./contexts/AuthContext";
import "./index.css";
import { QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "@/components/theme-provider";
import { queryClient } from "@/lib/query";
import { Toaster } from "@/components/ui/sonner";
import { i18nReady } from "@/i18n";
import { listen, invoke } from "@/lib/transport";
import { verifyServerBuildProfile } from "@/lib/buildInfo";
import {
  handleFatalConfigLoadError,
  type ConfigLoadErrorPayload,
} from "@platform/bootstrap";

try {
  const ua = navigator.userAgent || "";
  const plat = (navigator.platform || "").toLowerCase();
  const isMac = /mac/i.test(ua) || plat.includes("mac");
  if (isMac) {
    document.body.classList.add("is-mac");
  }
} catch {
  // 忽略平台检测失败
}

async function bootstrap() {
  await i18nReady;

  try {
    await verifyServerBuildProfile();
  } catch (error) {
    renderProfileMismatchPage(error);
    return;
  }

  try {
    await listen<ConfigLoadErrorPayload | null>(
      "configLoadError",
      async (payload) => {
        await handleFatalConfigLoadError(payload);
      },
    );
  } catch (e) {
    console.error("订阅 configLoadError 事件失败", e);
  }

  try {
    const initError = (await invoke(
      "get_init_error",
    )) as ConfigLoadErrorPayload | null;
    if (initError && (initError.path || initError.error)) {
      await handleFatalConfigLoadError(initError);
      return;
    }
  } catch (e) {
    console.error("拉取初始化错误失败", e);
  }

  ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <QueryClientProvider client={queryClient}>
        <ThemeProvider defaultTheme="system" storageKey="cc-switch-theme">
          <AuthProvider>
            <UpdateProvider>
              <App />
              <Toaster />
            </UpdateProvider>
          </AuthProvider>
        </ThemeProvider>
      </QueryClientProvider>
    </React.StrictMode>,
  );
}

void bootstrap().catch((e) => {
  console.error("应用引导失败", e);
});

function renderProfileMismatchPage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  document.body.classList.add("min-h-screen", "bg-background", "text-foreground");
  document.getElementById("root")!.innerHTML = `
    <main class="flex min-h-screen items-center justify-center p-6">
      <section class="max-w-xl rounded-lg border border-destructive/40 bg-card p-6 shadow-sm">
        <h1 class="text-lg font-semibold text-destructive">ccs-web profile mismatch</h1>
        <p class="mt-3 text-sm text-muted-foreground">
          The frontend build profile does not match the backend runtime profile.
          Rebuild or restart the service with a consistent CCS_WEB_PROFILE / VITE_CCS_WEB_PROFILE.
        </p>
        <pre class="mt-4 overflow-auto rounded-md bg-muted p-3 text-xs">${escapeHtml(message)}</pre>
      </section>
    </main>
  `;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });
}
