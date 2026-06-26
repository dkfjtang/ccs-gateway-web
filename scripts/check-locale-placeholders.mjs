import { readFile } from "node:fs/promises";
import { relative, resolve } from "node:path";

const localeFiles = [
  "src/i18n/locales/en.json",
  "src/i18n/locales/ja.json",
  "src/i18n/locales/zh-TW.json",
  "src/i18n/locales/zh.json",
];

const placeholderPattern = /\?{4,}/;

function collectPlaceholderStrings(value, path, findings) {
  if (typeof value === "string") {
    if (placeholderPattern.test(value)) {
      findings.push({ path, value });
    }
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      collectPlaceholderStrings(item, `${path}[${index}]`, findings),
    );
    return;
  }

  if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      collectPlaceholderStrings(item, path ? `${path}.${key}` : key, findings);
    }
  }
}

const repoRoot = process.cwd();
let hasFailures = false;

for (const file of localeFiles) {
  const fullPath = resolve(repoRoot, file);
  const source = await readFile(fullPath, "utf8");
  const parsed = JSON.parse(source);
  const findings = [];
  collectPlaceholderStrings(parsed, "", findings);

  if (findings.length > 0) {
    hasFailures = true;
    const displayPath = relative(repoRoot, fullPath);
    for (const finding of findings) {
      console.error(
        `${displayPath}: ${finding.path} contains suspicious placeholder text: ${JSON.stringify(
          finding.value,
        )}`,
      );
    }
  }
}

if (hasFailures) {
  process.exitCode = 1;
}
