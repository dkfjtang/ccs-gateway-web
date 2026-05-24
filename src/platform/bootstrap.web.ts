export interface ConfigLoadErrorPayload {
  path?: string;
  error?: string;
}

export async function handleFatalConfigLoadError(
  payload: ConfigLoadErrorPayload | null,
): Promise<void> {
  const path = payload?.path ?? "~/.cc-switch/config.json";
  const detail = payload?.error ?? "Unknown error";
  const message = [
    "无法读取配置文件：",
    path,
    "",
    "错误详情：",
    detail,
    "",
    "请手动检查 JSON 是否有效，或从同目录的备份文件（如 config.json.bak）恢复。",
    "",
    "应用将退出以便您进行修复。",
  ].join("\n");

  if (typeof window !== "undefined" && typeof window.alert === "function") {
    window.alert(message);
  }

  throw new Error(`Config load failed: ${detail}`);
}
