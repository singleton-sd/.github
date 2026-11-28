#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  LOCK_HEADER,
  compositePinMismatchMessage,
  formatLock,
  lintRepo,
  parseLock,
} from "./lint-contract.mjs";

const script = join(dirname(fileURLToPath(import.meta.url)), "lint-contract.mjs");
const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "..", "tests", "fixtures");
const PIN = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1";
const PIN_LINE = `${PIN} # v7.0.1`;
const AZURE_SHA = "a641126d1b8aa4d1fa005f4f92df94a3a4c4c906";
const AZURE_PIN = `azure/login@${AZURE_SHA}`;
const AZURE_LINE = `${AZURE_PIN} # v3.1.0`;
const AZURE_WRONG_SHA = "0123456789abcdef0123456789abcdef01234567";

function tempRoot() {
  return mkdtempSync(join(tmpdir(), "lint-contract-"));
}

function write(root, rel, contents) {
  const path = join(root, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents);
}

const SUMMARY = `
      - name: Write job summary
        env:
          WORKFLOW_REF: \${{ github.workflow_ref }}
          HEAD_SHA: \${{ github.sha }}
        run: |
          set -euo pipefail
          {
            echo "## Summary"
            echo "- workflow_ref: \\\`\$WORKFLOW_REF\\\`"
            echo "- sha: \\\`\$HEAD_SHA\\\`"
          } >> "\$GITHUB_STEP_SUMMARY"
`;

function reusableWorkflow({ extraInputs = "", extraSteps = "", secrets = "", name = "Pages build", filename = "pages-build.yml" } = {}) {
  return `# ${filename}
name: ${name}
on:
  workflow_call:
    inputs:
      working_directory:
        description: Site package directory relative to the repository root
        type: string
        default: "."
${extraInputs}    secrets:${secrets || " {}"}
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: ${PIN_LINE}
      - name: Use working directory
        env:
          WORKING_DIRECTORY: \${{ inputs.working_directory }}
        run: echo "\$WORKING_DIRECTORY"
${extraSteps}${SUMMARY}`;
}

function selfTestYaml() {
  return `name: self-test
on:
  pull_request:
  push:
    branches: [main]
permissions: {}
jobs:
  pages-build:
    permissions:
      contents: read
    uses: ./.github/workflows/pages-build.yml
  pages-deploy:
    permissions:
      contents: read
    uses: ./.github/workflows/pages-deploy.yml
    with:
      dry_run: true
  pages-smoke:
    permissions:
      contents: read
    uses: ./.github/workflows/pages-smoke.yml
  self-test:
    name: self-test
    needs: [pages-build, pages-deploy, pages-smoke]
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - run: echo ok
`;
}

function deployWorkflow() {
  return reusableWorkflow({
    name: "Pages deploy",
    filename: "pages-deploy.yml",
    extraInputs: `      dry_run:
        description: Skip minting a token and deploying
        type: boolean
        default: false
`,
  }).replace("name: Pages build", "name: Pages deploy");
}

function smokeWorkflow() {
  return `name: Pages smoke
on:
  workflow_call:
    inputs:
      url:
        description: Live Pages URL
        type: string
        required: true
permissions: {}
jobs:
  smoke:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Check out shared scripts
        uses: ${PIN_LINE}
        with:
          repository: \${{ job.workflow_repository }}
          persist-credentials: false
      - name: Fetch URL
        env:
          SMOKE_URL: \${{ inputs.url }}
        run: echo "\$SMOKE_URL"
${SUMMARY}`;
}

function passingTree(root) {
  write(root, ".github/workflows/pages-build.yml", reusableWorkflow());
  write(root, ".github/workflows/pages-deploy.yml", deployWorkflow());
  write(root, ".github/workflows/pages-smoke.yml", smokeWorkflow());
  write(root, ".github/workflows/self-test.yml", selfTestYaml());
  write(
    root,
    ".github/workflows/self-ci.yml",
    `name: self-ci
on:
  pull_request:
permissions: {}
jobs:
  self-ci:
    name: self-ci
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: ${PIN_LINE}
`,
  );
  write(
    root,
    ".github/workflows/self-release.yml",
    `name: self-release
on:
  workflow_run:
    workflows: [self-ci, self-test]
    types: [completed]
    branches: [main]
  workflow_dispatch:
concurrency:
  group: release-v1
  cancel-in-progress: false
permissions: {}
jobs:
  self-release:
    name: self-release
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: ${PIN_LINE}
`,
  );
  write(
    root,
    "actions/sample/action.yml",
    `name: Sample
description: Composite fixture
inputs:
  working_directory:
    description: unused
    required: false
    default: "."
runs:
  using: composite
  steps:
    - name: Write job summary
      shell: bash
      env:
        WORKFLOW_REF: \${{ github.workflow_ref }}
        HEAD_SHA: \${{ github.sha }}
      run: |
        set -euo pipefail
        echo "\$WORKFLOW_REF \$HEAD_SHA" >> "\$GITHUB_STEP_SUMMARY"
`,
  );
  const result = lintRepo(root, { writeLock: true });
  assert.equal(result.errors.join("\n"), "");
  return result;
}

test("passing tree is clean", () => {
  const root = tempRoot();
  const result = passingTree(root);
  assert.equal(result.errors.length, 0);
  assert.match(result.lock, /version: 'v0\.0\.3'/);
  assert.match(result.lock, /actions\/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1/);
  assert.match(result.lock, /ref: 'v7\.0\.1'/);
});

test("secrets: inherit fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow().replace("jobs:", "jobs:\n  leaked:\n    runs-on: ubuntu-latest\n    secrets: inherit\n    steps: []\n"),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("secrets: inherit")));
});

test("unpinned uses fail", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow().replace(PIN_LINE, "actions/checkout@v4"),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("unpinned uses")));
});

test("missing permissions: {} fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow().replace("permissions: {}", "permissions:\n  contents: read"),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("permissions: {}")));
});

test("github.workflow concurrency fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/self-release.yml",
    `name: self-release
on:
  workflow_dispatch:
concurrency:
  group: \${{ github.workflow }}
permissions: {}
jobs:
  self-release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: ${PIN_LINE}
`,
  );
  lintRepo(root, { writeLock: true });
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("github.workflow")));
});

test("interpolated inputs in run fail", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow({
      extraSteps: `      - name: Bad interpolation
        run: echo "\${{ inputs.working_directory }}"
`,
    }),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("interpolate")));
});

test("missing working_directory on caller checkout fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow().replace(
      `      working_directory:
        description: Site package directory relative to the repository root
        type: string
        default: "."
`,
      "",
    ),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("working_directory")));
});

test("missing dry_run on deploy workflow fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-deploy.yml",
    reusableWorkflow({ name: "Pages deploy" }).replace("name: Pages build", "name: Pages deploy"),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("dry_run")));
});

test("missing job summary fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-smoke.yml",
    smokeWorkflow().replace(SUMMARY, ""),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("job summary")));
});

test("missing self-test caller fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/self-test.yml",
    selfTestYaml().replace("    uses: ./.github/workflows/pages-build.yml\n", ""),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("self-test.yml must call")));
});

test("lock mismatch fails", () => {
  const root = tempRoot();
  passingTree(root);
  write(root, ".github/workflows/actions.lock", `${formatLock([])}`);
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("actions.lock")));
});

test("duplicate uses of the same pin in one workflow write one lock key", () => {
  const root = tempRoot();
  passingTree(root);
  write(
    root,
    ".github/workflows/pages-deploy.yml",
    deployWorkflow().replace(
      `        uses: ${PIN_LINE}\n`,
      `        uses: ${PIN_LINE}\n      - name: Again\n        uses: ${PIN_LINE}\n`,
    ),
  );
  const result = lintRepo(root, { writeLock: true });
  assert.equal(result.errors.length, 0, result.errors.join("\n"));
  const lock = parseLock(result.lock);
  const list = lock.workflows[".github/workflows/pages-deploy.yml"] || [];
  assert.equal(list.filter((key) => key === PIN).length, 1);
});

test("lockfile duplicate workflow pin fails", () => {
  const root = tempRoot();
  const generated = passingTree(root);
  write(
    root,
    ".github/workflows/actions.lock",
    generated.lock.replace(
      `- '${PIN}'\n`,
      `- '${PIN}'\n        - '${PIN}'\n`,
    ),
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("duplicate dependency key")));
});

test("self-release is not required to have working_directory or dry_run", () => {
  const root = tempRoot();
  passingTree(root);
  const result = lintRepo(root);
  assert.equal(result.errors.length, 0);
  assert.equal(
    result.errors.some((error) => error.includes("self-release.yml") && error.includes("working_directory")),
    false,
  );
});

test("local ./ uses are allowed without a lock entry", () => {
  const root = tempRoot();
  passingTree(root);
  const result = lintRepo(root);
  assert.equal(result.errors.length, 0);
  const lock = parseLock(result.lock);
  assert.equal(
    Object.keys(lock.dependencies).some((key) => key.startsWith("./")),
    false,
  );
});

test("CLI --write-lock then verify exits 0", () => {
  const root = tempRoot();
  passingTree(root);
  const written = spawnSync(process.execPath, [script, "--write-lock", root], {
    encoding: "utf8",
  });
  assert.equal(written.status, 0, written.stderr);
  const verified = spawnSync(process.execPath, [script, root], { encoding: "utf8" });
  assert.equal(verified.status, 0, verified.stderr);
  assert.match(verified.stdout, /lint-contract: passed/);
});

function writeCompositePin(root, pinLine) {
  write(
    root,
    "actions/azure-oidc-login/action.yml",
    `name: Azure OIDC login
description: Composite fixture
inputs:
  client-id:
    description: unused
    required: true
runs:
  using: composite
  steps:
    - name: Log in to Azure with OIDC
      uses: ${pinLine}
    - name: Write job summary
      shell: bash
      env:
        WORKFLOW_REF: \${{ github.workflow_ref }}
        HEAD_SHA: \${{ github.sha }}
      run: |
        set -euo pipefail
        echo "\$WORKFLOW_REF \$HEAD_SHA" >> "\$GITHUB_STEP_SUMMARY"
`,
  );
}

test("Dependabot-style drop of a composite-only pin passes", () => {
  const root = join(FIXTURES, "actions-lock-dependabot-drop");
  const result = lintRepo(root);
  assert.equal(result.errors.join("\n"), "");
  assert.ok(
    result.pins.some((pin) => pin.uses === AZURE_PIN),
    "fixture must include the composite-only azure/login pin",
  );
  const cli = spawnSync(process.execPath, [script, root], { encoding: "utf8" });
  assert.equal(cli.status, 0, cli.stderr + cli.stdout);
});

test("composite pin that disagrees with the lock fails", () => {
  const root = join(FIXTURES, "actions-lock-composite-mismatch");
  const result = lintRepo(root);
  const expected = compositePinMismatchMessage(
    "actions/azure-oidc-login/action.yml",
    "azure/login",
    AZURE_SHA,
    AZURE_WRONG_SHA,
  );
  assert.ok(
    result.errors.includes(expected),
    result.errors.join("\n"),
  );
  const cli = spawnSync(process.execPath, [script, root], { encoding: "utf8" });
  assert.notEqual(cli.status, 0);
  assert.match(cli.stderr + cli.stdout, /azure\/login pin .* does not match/);
  assert.match(cli.stderr + cli.stdout, new RegExp(AZURE_SHA));
  assert.match(cli.stderr + cli.stdout, new RegExp(AZURE_WRONG_SHA));
});

test("matching composite pin stays in the lock on write", () => {
  const root = tempRoot();
  passingTree(root);
  writeCompositePin(root, AZURE_LINE);
  const result = lintRepo(root, { writeLock: true });
  assert.equal(result.errors.join("\n"), "");
  const lock = parseLock(result.lock);
  assert.ok(lock.dependencies[AZURE_PIN]);
  assert.equal(lock.dependencies[AZURE_PIN].ref, "v3.1.0");
});

function appConfigWorkflow() {
  return reusableWorkflow({
    name: "Pages build with App Configuration",
    filename: "pages-build-app-config.yml",
  })
    .replace("name: Pages build", "name: Pages build with App Configuration")
    .replace(
      "permissions:\n      contents: read",
      "permissions:\n      contents: read\n      id-token: write",
    );
}

function writePagesBuildAppConfigTree(root) {
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow({
      extraSteps: `      - name: App Configuration uses pages-build-app-config.yml
        run: echo pages-build-app-config.yml
`,
    }),
  );
  write(root, ".github/workflows/pages-build-app-config.yml", appConfigWorkflow());
  write(
    root,
    ".github/workflows/self-test.yml",
    selfTestYaml().replace(
      "    uses: ./.github/workflows/pages-smoke.yml\n",
      "    uses: ./.github/workflows/pages-smoke.yml\n  pages-build-app-config:\n    permissions:\n      contents: read\n      id-token: write\n    uses: ./.github/workflows/pages-build-app-config.yml\n",
    ),
  );
}

test("pages-build.yml must not request id-token: write", () => {
  const root = tempRoot();
  passingTree(root);
  writePagesBuildAppConfigTree(root);
  write(
    root,
    ".github/workflows/pages-build.yml",
    reusableWorkflow({
      extraSteps: `      - name: App Configuration uses pages-build-app-config.yml
        run: echo pages-build-app-config.yml
`,
    }).replace(
      "permissions:\n      contents: read",
      "permissions:\n      contents: read\n      id-token: write",
    ),
  );
  lintRepo(root, { writeLock: true });
  const result = lintRepo(root);
  assert.ok(
    result.errors.some((error) => error.includes("pages-build.yml") && error.includes("id-token: write")),
    result.errors.join("\n"),
  );
});

test("pages-build.yml templates must not grant id-token: write", () => {
  const root = tempRoot();
  passingTree(root);
  writePagesBuildAppConfigTree(root);
  write(
    root,
    "workflow-templates/pages-production.yml",
    `name: Deploy production GitHub Pages
on:
  push:
jobs:
  build:
    uses: singleton-sd/.github/.github/workflows/pages-build.yml@v1
    permissions:
      contents: read
      id-token: write
`,
  );
  lintRepo(root, { writeLock: true });
  const result = lintRepo(root);
  assert.ok(
    result.errors.some((error) => error.includes("workflow-templates/pages-production.yml") && error.includes("id-token: write")),
    result.errors.join("\n"),
  );
});

test("pages-build-app-config.yml must request id-token: write", () => {
  const root = tempRoot();
  passingTree(root);
  writePagesBuildAppConfigTree(root);
  write(
    root,
    ".github/workflows/pages-build-app-config.yml",
    reusableWorkflow({
      name: "Pages build with App Configuration",
      filename: "pages-build-app-config.yml",
    }).replace("name: Pages build", "name: Pages build with App Configuration"),
  );
  lintRepo(root, { writeLock: true });
  const result = lintRepo(root);
  assert.ok(
    result.errors.some((error) => error.includes("pages-build-app-config.yml") && error.includes("id-token: write")),
    result.errors.join("\n"),
  );
});

test("missing workflow pin still fails after composite-only tolerance", () => {
  const root = tempRoot();
  passingTree(root);
  writeCompositePin(root, AZURE_LINE);
  lintRepo(root, { writeLock: true });
  write(
    root,
    ".github/workflows/actions.lock",
    `${LOCK_HEADER}
version: 'v0.0.3'
workflows: {}
dependencies: {}
`,
  );
  const result = lintRepo(root);
  assert.ok(result.errors.some((error) => error.includes("actions.lock") && error.includes("missing")));
  assert.equal(
    result.errors.some((error) => error.includes("azure/login") && error.includes("missing")),
    false,
    result.errors.join("\n"),
  );
});
