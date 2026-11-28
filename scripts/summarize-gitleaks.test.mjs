#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { FINDINGS_EXIT_CODE, summarizeGitleaks } from "./summarize-gitleaks.mjs";

test("operational failure with empty report is not a pass", () => {
  const dir = mkdtempSync(join(tmpdir(), "gitleaks-sum-"));
  const report = join(dir, "empty.json");
  writeFileSync(report, "[]");
  const result = summarizeGitleaks(1, report);
  assert.equal(result.status, "fail");
  assert.equal(result.operational, true);
  assert.ok(result.rules.includes("gitleaks-error"));
});

test("clean scan with valid empty report is a pass", () => {
  const dir = mkdtempSync(join(tmpdir(), "gitleaks-sum-"));
  const report = join(dir, "empty.json");
  writeFileSync(report, "[]");
  const result = summarizeGitleaks(0, report);
  assert.equal(result.status, "pass");
  assert.equal(result.operational, false);
  assert.equal(result.count, 0);
});

test("findings exit with a valid report is a fail", () => {
  const dir = mkdtempSync(join(tmpdir(), "gitleaks-sum-"));
  const report = join(dir, "hits.json");
  writeFileSync(report, JSON.stringify([{ RuleID: "aws-access-token" }]));
  const result = summarizeGitleaks(FINDINGS_EXIT_CODE, report);
  assert.equal(result.status, "fail");
  assert.equal(result.operational, false);
  assert.ok(result.rules.includes("aws-access-token"));
});

test("missing or invalid report is not a pass", () => {
  const dir = mkdtempSync(join(tmpdir(), "gitleaks-sum-"));
  const missing = summarizeGitleaks(0, join(dir, "missing.json"));
  assert.equal(missing.status, "fail");
  assert.equal(missing.operational, true);
  writeFileSync(join(dir, "bad.json"), "{");
  const invalid = summarizeGitleaks(0, join(dir, "bad.json"));
  assert.equal(invalid.status, "fail");
  assert.equal(invalid.operational, true);
});
