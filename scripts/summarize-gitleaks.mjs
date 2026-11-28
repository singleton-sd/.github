#!/usr/bin/env node
/**
 * Fail-closed gitleaks report adapter.
 * Findings use exit code 2. Pass only when exit 0 and the report is a valid empty list.
 * Usage: node scripts/summarize-gitleaks.mjs EXIT_CODE REPORT_JSON DEST_FILE
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const FINDINGS_EXIT_CODE = 2;

function isMain() {
  try {
    return import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
}

function rulesOf(findings) {
  return [
    ...new Set(
      findings
        .filter((item) => item && typeof item === "object")
        .map((item) => String(item.RuleID || item.Rule || "unknown")),
    ),
  ].sort();
}

export function summarizeGitleaks(code, reportPath) {
  let findings = null;
  let valid = false;
  if (existsSync(reportPath)) {
    try {
      const raw = readFileSync(reportPath, "utf8");
      const loaded = raw.trim() ? JSON.parse(raw) : [];
      if (Array.isArray(loaded)) {
        findings = loaded;
        valid = true;
      }
    } catch {
      valid = false;
    }
  }

  if (code === 0 && valid && findings.length === 0) {
    return {
      status: "pass",
      count: 0,
      rules: [],
      note: "",
      operational: false,
      printed: ["gitleaks: 0 finding(s); rules: none"],
    };
  }

  if (code === FINDINGS_EXIT_CODE && valid && findings.length > 0) {
    const rules = rulesOf(findings);
    return {
      status: "fail",
      count: findings.length,
      rules,
      note: "",
      operational: false,
      printed: [
        `gitleaks: ${findings.length} finding(s); rules: ${rules.join(", ") || "none"}`,
      ],
    };
  }

  return {
    status: "fail",
    count: 0,
    rules: ["gitleaks-error"],
    note: "operational error",
    operational: true,
    printed: [`::error::gitleaks failed with exit ${code}`],
  };
}

export function writeGitleaksResult(dest, result) {
  writeFileSync(
    dest,
    `${result.status}\n${result.count}\n${result.rules.join(",")}\n${result.note}\n`,
    "utf8",
  );
}

if (isMain()) {
  const code = Number(process.argv[2]);
  const reportPath = process.argv[3];
  const dest = process.argv[4];
  const result = summarizeGitleaks(code, reportPath);
  writeGitleaksResult(dest, result);
  for (const line of result.printed) {
    process.stdout.write(`${line}\n`);
  }
}
