import type { UsageProbe, UsageProbeType, UsageScript } from "@/types";

const USAGE_PROBE_TYPES = new Set<UsageProbeType>([
  "usage",
  "rate",
  "models",
  "account",
]);

type DraftObject = Record<string, unknown>;

const stripOuterParens = (value: string): string => {
  let text = value.trim();
  while (text.startsWith("(") && text.endsWith(")")) {
    const inner = text.slice(1, -1).trim();
    if (!inner) break;
    text = inner;
  }
  return text;
};

const isIdentChar = (value: string): boolean => /[A-Za-z0-9_$-]/.test(value);

const findMatching = (
  source: string,
  start: number,
  open: string,
  close: string,
): number => {
  let depth = 0;
  let quote: string | null = null;
  let escaped = false;

  for (let i = start; i < source.length; i++) {
    const char = source[i];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === quote) {
        quote = null;
      }
      continue;
    }

    if (char === '"' || char === "'" || char === "`") {
      quote = char;
      continue;
    }
    if (char === open) depth++;
    if (char === close) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
};

const findStringEnd = (source: string, start: number, quote: string): number => {
  let escaped = false;
  for (let i = start + 1; i < source.length; i++) {
    const char = source[i];
    if (escaped) {
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (char === quote) {
      return i;
    }
  }
  return -1;
};

const splitTopLevel = (source: string, separator = ","): string[] => {
  const parts: string[] = [];
  let start = 0;
  let round = 0;
  let square = 0;
  let curly = 0;
  let quote: string | null = null;
  let escaped = false;

  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) quote = null;
      continue;
    }

    if (char === '"' || char === "'" || char === "`") {
      quote = char;
      continue;
    }
    if (char === "(") round++;
    else if (char === ")") round--;
    else if (char === "[") square++;
    else if (char === "]") square--;
    else if (char === "{") curly++;
    else if (char === "}") curly--;
    else if (
      char === separator &&
      round === 0 &&
      square === 0 &&
      curly === 0
    ) {
      parts.push(source.slice(start, i).trim());
      start = i + 1;
    }
  }

  const tail = source.slice(start).trim();
  if (tail) parts.push(tail);
  return parts;
};

const readPropertyKey = (source: string, start: number): { key: string; end: number } | null => {
  let i = start;
  while (/\s/.test(source[i] ?? "")) i++;
  const quote = source[i];
  if (quote === '"' || quote === "'") {
    const end = findStringEnd(source, i, quote);
    if (end < 0) return null;
    return { key: source.slice(i + 1, end), end: end + 1 };
  }

  const keyStart = i;
  while (i < source.length && isIdentChar(source[i])) i++;
  if (i === keyStart) return null;
  return { key: source.slice(keyStart, i), end: i };
};

const parseObjectLiteral = (source: string): DraftObject | null => {
  const text = stripOuterParens(source);
  if (!text.startsWith("{") || !text.endsWith("}")) return null;
  const body = text.slice(1, -1);
  const result: DraftObject = {};

  for (const part of splitTopLevel(body)) {
    const keyInfo = readPropertyKey(part, 0);
    if (!keyInfo) continue;
    let i = keyInfo.end;
    while (/\s/.test(part[i] ?? "")) i++;
    if (part[i] !== ":") continue;
    result[keyInfo.key] = part.slice(i + 1).trim();
  }

  return result;
};

const parseArrayLiteral = (source: string): string[] | null => {
  const text = stripOuterParens(source);
  if (!text.startsWith("[") || !text.endsWith("]")) return null;
  return splitTopLevel(text.slice(1, -1)).filter(Boolean);
};

const unquote = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  if (!text) return undefined;
  const quote = text[0];
  if (
    (quote === '"' || quote === "'" || quote === "`") &&
    text.endsWith(quote)
  ) {
    return text.slice(1, -1);
  }
  return text;
};

const parseBoolean = (value: unknown): boolean | undefined => {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return undefined;
  if (value.trim() === "true") return true;
  if (value.trim() === "false") return false;
  return undefined;
};

const parseNumber = (value: unknown): number | undefined => {
  if (typeof value === "number") return value;
  if (typeof value !== "string") return undefined;
  const parsed = Number(value.trim());
  return Number.isFinite(parsed) ? parsed : undefined;
};

const normalizeExtractor = (value: unknown): string => {
  const text = unquote(value);
  if (!text) return "return response";
  const trimmed = text.trim();
  if (!trimmed.startsWith("function")) return trimmed;
  const start = trimmed.indexOf("{");
  if (start < 0) return "return response";
  const end = findMatching(trimmed, start, "{", "}");
  if (end < 0) return "return response";
  return trimmed.slice(start + 1, end).trim();
};

const normalizeHeaders = (value: unknown): Record<string, string> => {
  if (!value) return {};
  if (typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, String(item)]),
    );
  }
  if (typeof value !== "string") return {};
  const parsed = parseObjectLiteral(value);
  if (!parsed) return {};
  return Object.fromEntries(
    Object.entries(parsed).map(([key, item]) => [key, unquote(item) ?? ""]),
  );
};

const normalizeBody = (value: unknown): string | undefined => {
  if (value === undefined) return undefined;
  if (typeof value === "string") {
    const parsedObject = parseObjectLiteral(value);
    if (parsedObject) {
      return JSON.stringify(
        Object.fromEntries(
          Object.entries(parsedObject).map(([key, item]) => [
            key,
            unquote(item) ?? "",
          ]),
        ),
      );
    }
    return unquote(value) ?? value;
  }
  return JSON.stringify(value);
};

export const normalizeProbeDraft = (
  value: unknown,
  index: number,
): UsageProbe | null => {
  const parsed =
    typeof value === "string" ? parseObjectLiteral(value) : (value as DraftObject);
  if (!parsed || typeof parsed !== "object" || !parsed.request) {
    return null;
  }

  const request =
    typeof parsed.request === "string"
      ? parseObjectLiteral(parsed.request)
      : (parsed.request as DraftObject);
  if (!request) return null;

  const rawType = unquote(parsed.type) as UsageProbeType | undefined;
  const type = rawType && USAGE_PROBE_TYPES.has(rawType)
    ? rawType
    : index === 0
      ? "usage"
      : "rate";

  return {
    id: unquote(parsed.id) || `${type}-${index + 1}`,
    type,
    enabled: parseBoolean(parsed.enabled) !== false,
    timeout: parseNumber(parsed.timeout),
    request: {
      url: unquote(request.url) || "",
      method: unquote(request.method) || "GET",
      headers: normalizeHeaders(request.headers),
      body: normalizeBody(request.body),
    },
    extractor: normalizeExtractor(parsed.extractor),
  };
};

const normalizeProbeList = (items: unknown[]): UsageProbe[] =>
  items
    .map((probe, index) => normalizeProbeDraft(probe, index))
    .filter(Boolean) as UsageProbe[];

export const parseUsageScriptDraft = (
  value: string,
): Partial<UsageScript> | null => {
  const trimmed = value.trim();
  if (!trimmed) return null;

  try {
    const parsed = JSON.parse(trimmed);
    const rawProbes = Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed?.probes)
        ? parsed.probes
        : parsed?.request
          ? [parsed]
          : null;
    if (!rawProbes) return null;
    const probes = normalizeProbeList(rawProbes);
    if (probes.length === 0) return null;
    return {
      ...(!Array.isArray(parsed) && !parsed.request ? parsed : {}),
      enabled: parsed?.enabled !== false,
      language: "javascript",
      code: trimmed,
      probes,
    };
  } catch {
    // Fall through to JavaScript object/list source parsing without evaluating it.
  }

  const list = parseArrayLiteral(trimmed);
  const rawProbes = list ?? (parseObjectLiteral(trimmed) ? [trimmed] : null);
  if (!rawProbes) return null;
  const probes = normalizeProbeList(rawProbes);
  if (probes.length === 0) return null;

  return {
    enabled: true,
    language: "javascript",
    code: trimmed,
    probes,
  };
};

export const mergeUsageScriptDraft = (
  current: UsageScript,
  draft: Partial<UsageScript>,
): UsageScript => ({
  ...current,
  ...draft,
  apiKey: draft.apiKey ?? current.apiKey,
  baseUrl: draft.baseUrl ?? current.baseUrl,
  accessToken: draft.accessToken ?? current.accessToken,
  userId: draft.userId ?? current.userId,
  language: "javascript",
  code: draft.code ?? current.code,
});
