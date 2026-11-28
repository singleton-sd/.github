/**
 * Apply `az appconfig kv list` JSON from stdin.
 *
 * Unlabeled values are written first, then items whose label matches
 * APP_CONFIG_LABEL (the label wins). Selected keys go to GITHUB_ENV.
 * Every selected read is logged to the job summary and stdout (allowed
 * because these are non-secret public prefixes).
 *
 * Fails if any selected item is a Key Vault reference, does not start
 * with an allowed prefix, or is not a valid environment variable name.
 */
import { randomBytes } from "node:crypto";
import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const KEY_VAULT_CONTENT_TYPE =
  "application/vnd.microsoft.appconfig.keyvaultref+json";
const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
const GITHUB_ENV_DELIMITER_ATTEMPTS = 8;
const DEFAULT_PREFIXES = "PUBLIC_,NEXT_PUBLIC_";

export function parsePrefixes(raw) {
  const source = raw == null || String(raw).trim() === ""
    ? DEFAULT_PREFIXES
    : String(raw);
  const prefixes = [];
  for (const part of source.split(",")) {
    const prefix = part.trim();
    if (prefix === "") {
      continue;
    }
    if (!ENV_NAME.test(prefix)) {
      throw new Error(
        `Invalid App Configuration key prefix ${JSON.stringify(prefix)}.`,
      );
    }
    prefixes.push(prefix);
  }
  if (prefixes.length === 0) {
    throw new Error("APP_CONFIG_KEY_PREFIXES is empty.");
  }
  return prefixes;
}

export function keyStartsWithAllowedPrefix(key, prefixes) {
  return prefixes.some((prefix) => key.startsWith(prefix));
}

export function assertAllowedEnvKey(key, prefixes) {
  if (!ENV_NAME.test(key) || !keyStartsWithAllowedPrefix(key, prefixes)) {
    throw new Error(
      `Refusing App Configuration key ${JSON.stringify(key)} because it is not a valid environment variable name with an allowed prefix.`,
    );
  }
}

export function createGithubEnvDelimiter() {
  return `APPCONFIG_${randomBytes(16).toString("hex")}`;
}

export function contentTypeOf(item) {
  return String(item?.contentType ?? item?.content_type ?? "");
}

export function isKeyVaultReference(item) {
  return contentTypeOf(item).includes("vnd.microsoft.appconfig.keyvaultref");
}

export function itemKey(item) {
  return String(item?.key ?? "");
}

export function itemLabel(item) {
  const raw = item?.label;
  if (raw === null || raw === undefined || raw === "") {
    return "";
  }
  return String(raw);
}

export function itemValue(item) {
  return item?.value == null ? "" : String(item.value);
}

export function isSelectedLabel(label, repoLabel) {
  return label === "" || label === repoLabel;
}

export function applyAppConfigKv(items, options = {}) {
  const prefixes = parsePrefixes(options.prefixes);
  const repoLabel = String(options.label ?? "");
  const applied = [];
  const audit = [];

  if (!Array.isArray(items)) {
    throw new Error("App Configuration list must be a JSON array.");
  }

  const selected = [];
  for (const item of items) {
    const key = itemKey(item);
    const label = itemLabel(item);
    if (!isSelectedLabel(label, repoLabel)) {
      continue;
    }
    if (isKeyVaultReference(item)) {
      throw new Error(
        `Refusing Key Vault reference for ${key || "(missing key)"} (content type ${KEY_VAULT_CONTENT_TYPE}).`,
      );
    }
    assertAllowedEnvKey(key, prefixes);
    selected.push(item);
    audit.push({
      key,
      label: label || "(none)",
      value: itemValue(item),
      etag: String(item?.etag ?? item?.eTag ?? ""),
      lastModified: String(item?.lastModified ?? item?.last_modified ?? ""),
    });
  }

  const unlabeled = selected.filter((item) => itemLabel(item) === "");
  const labeled = selected.filter((item) => itemLabel(item) !== "");
  const byKey = new Map();
  for (const item of [...unlabeled, ...labeled]) {
    byKey.set(itemKey(item), itemValue(item));
  }
  for (const [key, value] of byKey) {
    applied.push({ key, value });
  }

  return { applied, audit };
}

export function githubEnvBlock(
  key,
  value,
  prefixes,
  createDelimiter = createGithubEnvDelimiter,
) {
  assertAllowedEnvKey(key, prefixes);
  const text = String(value);
  for (let attempt = 0; attempt < GITHUB_ENV_DELIMITER_ATTEMPTS; attempt += 1) {
    const delimiter = createDelimiter();
    if (!text.includes(delimiter)) {
      return `${key}<<${delimiter}\n${text}\n${delimiter}\n`;
    }
  }
  throw new Error(
    `Unable to choose a GITHUB_ENV delimiter that is absent from ${key}.`,
  );
}

function displayTableValue(value) {
  return String(value)
    .replaceAll("\r\n", "\n")
    .replaceAll("\n", "\\n")
    .replaceAll("|", "\\|")
    .replaceAll("`", "\\`");
}

export function auditSummaryMarkdown(audit, options = {}) {
  const store = options.store || "ssd-global-appcs-build-prod-ae";
  const label = options.label || "(repo)";
  const rows = audit
    .map(
      (row) =>
        `| \`${row.key}\` | \`${row.label}\` | \`${displayTableValue(row.value)}\` | \`${row.etag}\` | \`${row.lastModified}\` |`,
    )
    .join("\n");
  return [
    "## Azure App Configuration audit",
    "",
    `Store: \`${store}\`. Unlabeled values apply first; the \`${label}\` label wins.`,
    "",
    "| Key | Label | Value | ETag | Last modified |",
    "| --- | --- | --- | --- | --- |",
    rows || "| — | — | — | — | — |",
    "",
  ].join("\n");
}

function githubOutputBlock(name, value, createDelimiter = createGithubEnvDelimiter) {
  const text = String(value);
  for (let attempt = 0; attempt < GITHUB_ENV_DELIMITER_ATTEMPTS; attempt += 1) {
    const delimiter = createDelimiter();
    if (!text.includes(delimiter)) {
      return `${name}<<${delimiter}\n${text}\n${delimiter}\n`;
    }
  }
  throw new Error(
    `Unable to choose a GITHUB_OUTPUT delimiter that is absent from ${name}.`,
  );
}

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () => resolve(chunks.join("")));
    process.stdin.on("error", reject);
  });
}

const isCli =
  Boolean(process.argv[1]) &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (isCli) {
  const raw = await readStdin();
  if (!raw.trim()) {
    throw new Error(
      "App Configuration list was empty. az appconfig kv list produced no JSON.",
    );
  }
  let items;
  try {
    items = JSON.parse(raw);
  } catch (err) {
    throw new Error("App Configuration JSON was not parseable.", {
      cause: err,
    });
  }
  const prefixes = parsePrefixes(process.env.APP_CONFIG_KEY_PREFIXES);
  const label = String(process.env.APP_CONFIG_LABEL ?? "");
  const { applied, audit } = applyAppConfigKv(items, { prefixes: process.env.APP_CONFIG_KEY_PREFIXES, label });
  const envPath = process.env.GITHUB_ENV;
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  const outputPath = process.env.GITHUB_OUTPUT;
  if (envPath) {
    for (const { key, value } of applied) {
      appendFileSync(envPath, githubEnvBlock(key, value, prefixes));
    }
  }
  const store = String(process.env.APP_CONFIG_STORE ?? "ssd-global-appcs-build-prod-ae");
  const summary = auditSummaryMarkdown(audit, { store, label: label || "(repo)" });
  if (summaryPath) {
    appendFileSync(summaryPath, `${summary}\n`);
  }
  if (outputPath) {
    const appliedObject = Object.fromEntries(applied.map((row) => [row.key, row.value]));
    appendFileSync(outputPath, `count=${applied.length}\n`);
    appendFileSync(outputPath, githubOutputBlock("applied", JSON.stringify(appliedObject)));
  }
  for (const row of audit) {
    console.log(
      `appconfig key=${row.key} label=${row.label} value=${row.value} etag=${row.etag} lastModified=${row.lastModified}`,
    );
  }
  console.log(`appconfig applied ${applied.length} key(s)`);
}
