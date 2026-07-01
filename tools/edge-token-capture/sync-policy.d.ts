export declare const fixedVaultPath: string;

export declare function isLoopbackServerUrl(serverUrl: unknown): boolean;

export declare function getRequiredSyncOrigins(serverUrl: string): string[];

export declare function buildSyncRequest(args: {
  serverUrl: string;
  payload: unknown;
  ccsSession?: string | null;
}): {
  url: string;
  init: RequestInit;
};

export declare function formatSyncError(
  result: unknown,
  status: number,
): string;
