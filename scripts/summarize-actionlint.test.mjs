#!/usr/bin/env node
import assert from "node:assert/strict";
import { test } from "node:test";

import { summarizeActionlint } from "./summarize-actionlint.mjs";

test("structured JSON diagnostics are counted as file:line:kind", () => {
  const output = JSON.stringify([
    { filepath: ".github/workflows/ci.yml", line: 4, kind: "expression", snippet: "ignored" },
    { filepath: ".github/workflows/ci.yml", line: 8, kind: "syntax-check" },
  ]);
  const result = summarizeActionlint(1, output);
  assert.equal(result.status, "fail");
  assert.equal(result.count, 2);
  assert.deepEqual(result.rules, ["expression", "syntax-check"]);
  assert.ok(result.printed.includes(".github/workflows/ci.yml:4:expression"));
  assert.ok(result.printed.includes(".github/workflows/ci.yml:8:syntax-check"));
});

test("source snippets never reach the summary", () => {
  const marker = "FAKE_TOKEN_SNIPPET_7c1e";
  const json = JSON.stringify([
    {
      message: `run: echo x:y:${marker}`,
      filepath: ".github/workflows/ci.yml",
      line: 12,
      kind: "expression",
      snippet: `run: echo x:y:${marker} '\${{ nonexistent.secret }}'`,
    },
  ]);
  const fromJson = summarizeActionlint(1, json);
  const jsonBlob = `${fromJson.printed.join("\n")}\n${fromJson.rules.join(",")}`;
  assert.doesNotMatch(jsonBlob, new RegExp(marker));
  assert.ok(fromJson.printed.includes(".github/workflows/ci.yml:12:expression"));

  const defaultish = [
    `.github/workflows/ci.yml:12:13: expression: unexpected token`,
    `run: echo x:y:${marker} '\${{ nonexistent.secret }}'`,
  ].join("\n");
  const fromText = summarizeActionlint(1, defaultish);
  const textBlob = `${fromText.printed.join("\n")}\n${fromText.rules.join(",")}`;
  assert.doesNotMatch(textBlob, new RegExp(marker));
});
