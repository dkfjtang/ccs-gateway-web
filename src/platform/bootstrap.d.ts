declare module "@platform/bootstrap" {
  export interface ConfigLoadErrorPayload {
    path?: string;
    error?: string;
  }

  export function handleFatalConfigLoadError(
    payload: ConfigLoadErrorPayload | null,
  ): Promise<void>;
}
