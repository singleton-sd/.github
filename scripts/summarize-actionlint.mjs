#!/usr/bin/env node
/**
 * Summarize actionlint JSON output. Logs only file:line:kind.
 * Usage: node scripts/summarize-actionlint.mjs EXIT_CODE OUTPUT_FILE DEST_FILE
 */
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const KIND = /^[A-Za-z0-9_-]+$/;

function isMain() {
  try {
    return import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
}

function diagnosticsFromJson(output) {
  const loaded = JSON.parse(String(output).trim() || "[]");
  if (!Array.isArray(loaded)) {
    return [];
  }
  const diagnostics = [];
  for (const item of loaded) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const kind = String(item.kind || item.Kind || "");
    if (!KIND.test(kind)) {
      continue;
    }
    const file = String(item.filepath || item.Filepath || "");
    const line = Number(item.line || item.Line || 0);
    diagnostics.push({ file, line, kind });
  }
  return diagnostics;
}

export function summarizeActionlint(code, output) {
  if (code === 0) {
    return {
      status: "pass",
      count: 0,
      rules: [],
      printed: ["actionlint: 0 error(s)"],
      diagnostics: [],
    };
  }
  if (code !== 1) {
    return {
      status: "fail",
      count: 0,
      rules: [],
      printed: [`::error::actionlint failed with exit ${code}`],
      diagnostics: [],
      exit: 1,
    };
  }
  let diagnostics = [];
  try {
    diagnostics = diagnosticsFromJson(output);
  } catch {
    diagnostics = [];
  }
  const rules = [...new Set(diagnostics.map((item) => item.kind))].sort();
  const printed = [
    `actionlint: ${diagnostics.length} error(s); rules: ${rules.join(", ") || "none"}`,
    ...diagnostics.map((item) => `${item.file}:${item.line}:${item.kind}`),
  ];
  return {
    status: "fail",
    count: diagnostics.length,
    rules,
    printed,
    diagnostics,
  };
}

export function writeActionlintResult(dest, result) {
  writeFileSync(
    dest,
    `${result.status}\n${result.count}\n${result.rules.join(",")}\n\n`,
    "utf8",
  );
}

if (isMain()) {
  const code = Number(process.argv[2]);
  const output = readFileSync(process.argv[3], "utf8");
  const dest = process.argv[4];
  const result = summarizeActionlint(code, output);
  writeActionlintResult(dest, result);
  for (const line of result.printed) {
    process.stdout.write(`${line}\n`);
  }
  if (result.exit) {
    process.exit(result.exit);
  }
}
