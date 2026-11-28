#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  checkCallerContract,
  classifyUses,
  loadBannedSteps,
  main,
} from "./check-caller-contract.mjs";

const script = join(dirname(fileURLToPath(import.meta.url)), "check-caller-contract.mjs");
const PIN = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1";

function tempRoot() {
  return mkdtempSync(join(tmpdir(), "caller-contract-"));
}

function write(root, rel, contents) {
  const path = join(root, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents);
}

function workflow(body) {
  return `name: ci
on:
  pull_request:
permissions: {}
jobs:
${body}
`;
}

test("SHA-pinned third-party uses are allowed", () => {
  const got = classifyUses(PIN);
  assert.equal(got.ok, true);
  assert.equal(got.kind, "sha");
});

test("local and docker uses are allowed", () => {
  assert.equal(classifyUses("./actions/azure-oidc-login").ok, true);
  assert.equal(classifyUses("docker://node:24").ok, true);
});

test("singleton-sd/.github @v1 and @v1.x.y are allowed", () => {
  assert.equal(
    classifyUses("singleton-sd/.github/.github/workflows/pages-build.yml@v1").ok,
    true,
  );
  assert.equal(
    classifyUses("singleton-sd/.github/.github/workflows/pages-build.yml@v1.0.3").ok,
    true,
  );
});

test("other singleton-sd refs may be @v1 or SHA, not @main", () => {
  assert.equal(classifyUses("singleton-sd/kit/.github/workflows/ci.yml@v1").ok, true);
  assert.equal(classifyUses(`singleton-sd/kit/.github/workflows/ci.yml@${"a".repeat(40)}`).ok, true);
  const mainRef = classifyUses("singleton-sd/kit/.github/workflows/ci.yml@main");
  assert.equal(mainRef.ok, false);
});

test("tag-pinned third-party uses fail", () => {
  const got = classifyUses("actions/checkout@v4");
  assert.equal(got.ok, false);
  assert.match(got.reason, /tag or branch/);
});

test("banned-steps.json has azure/login enforced and the rest warn", () => {
  const steps = loadBannedSteps();
  const byId = Object.fromEntries(steps.map((entry) => [entry.id, entry]));
  assert.equal(byId["inline-azure-login"].enforce, true);
  assert.equal(byId["inline-github-app-token"].enforce, false);
  assert.equal(byId["inline-release-commit-back"].enforce, false);
  assert.equal(byId["inline-spool-deploy"].enforce, false);
  assert.ok(byId["inline-github-app-token"].flipWhen);
  assert.ok(byId["inline-release-commit-back"].flipWhen);
  assert.ok(byId["inline-spool-deploy"].flipWhen);
});

test("clean SHA-pinned caller passes", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  security:
    permissions:
      contents: read
    uses: singleton-sd/.github/.github/workflows/security-scan.yml@v1
  ci:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: ${PIN}
        with:
          persist-credentials: false
`),
  );
  const result = checkCallerContract(root);
  assert.equal(result.errors.length, 0, result.errors.map((item) => item.message).join("\n"));
});

test("tag-pinned checkout fails", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`),
  );
  const result = checkCallerContract(root);
  assert.ok(result.errors.some((item) => item.rule === "unpinned-uses"));
});

test("secrets: inherit fails", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  build:
    uses: singleton-sd/.github/.github/workflows/pages-build.yml@v1
    secrets: inherit
`),
  );
  const result = checkCallerContract(root);
  assert.ok(result.errors.some((item) => item.rule === "secrets-inherit"));
});

test("inline azure/login is enforced", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  login:
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906
`),
  );
  const result = checkCallerContract(root);
  assert.ok(result.errors.some((item) => item.rule === "inline-azure-login"));
});

test("inline azure/login warns when enforce-banned-steps is false", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  login:
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906
`),
  );
  const result = checkCallerContract(root, { enforceBannedSteps: false });
  assert.equal(result.errors.length, 0);
  assert.ok(result.warnings.some((item) => item.rule === "inline-azure-login"));
});

test("inline create-github-app-token warns until the shared action ships", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/ci.yml",
    workflow(`  mint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/create-github-app-token@f418cff399f7aef4c2f0ad47e25ca7a6abbdd6fc
`),
  );
  const result = checkCallerContract(root);
  assert.equal(result.errors.length, 0);
  assert.ok(result.warnings.some((item) => item.rule === "inline-github-app-token"));
});

test("inline release-it commit-back warns", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/release.yml",
    workflow(`  release:
    runs-on: ubuntu-latest
    steps:
      - run: npx release-it --ci
`),
  );
  const result = checkCallerContract(root);
  assert.equal(result.errors.length, 0);
  assert.ok(result.warnings.some((item) => item.rule === "inline-release-commit-back"));
});

test("inline spool-deploy protocol warns", () => {
  const root = tempRoot();
  write(
    root,
    ".github/workflows/deploy.yml",
    workflow(`  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo spool-deploy --env prod
`),
  );
  const result = checkCallerContract(root);
  assert.equal(result.errors.length, 0);
  assert.ok(result.warnings.some((item) => item.rule === "inline-spool-deploy"));
});

test("workflow-templates are scanned", () => {
  const root = tempRoot();
  write(
    root,
    "workflow-templates/ci.yml",
    workflow(`  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`),
  );
  const result = checkCallerContract(root);
  assert.ok(result.errors.some((item) => item.message.includes("workflow-templates/ci.yml")));
});

test("CLI exits 1 on tag-pinned caller and 0 on clean", () => {
  const bad = tempRoot();
  write(
    bad,
    ".github/workflows/ci.yml",
    workflow(`  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
`),
  );
  const failed = spawnSync(process.execPath, [script, "--root", bad], { encoding: "utf8" });
  assert.equal(failed.status, 1, failed.stderr);
  assert.match(failed.stderr, /tag or branch/);

  const good = tempRoot();
  write(
    good,
    ".github/workflows/ci.yml",
    workflow(`  security:
    uses: singleton-sd/.github/.github/workflows/security-scan.yml@v1
`),
  );
  const passed = spawnSync(process.execPath, [script, "--root", good], { encoding: "utf8" });
  assert.equal(passed.status, 0, passed.stderr);
  assert.match(passed.stdout, /check-caller-contract: passed/);
});

test("main() --help exits 0", () => {
  assert.equal(main(["--help"]), 0);
});
