import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyAppConfigKv,
  auditSummaryMarkdown,
  githubEnvBlock,
  isKeyVaultReference,
} from "./app-config-apply.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPT = join(ROOT, "scripts", "app-config-apply.mjs");
const FIXTURES = join(ROOT, "tests", "fixtures", "app-config");
const PREFIXES = "PUBLIC_,NEXT_PUBLIC_";
const KV_LEAK = "kv-should-not-appear";

function loadFixture(name) {
  return JSON.parse(readFileSync(join(FIXTURES, name), "utf8"));
}

function runCli(fixtureName, extraEnv = {}) {
  const dir = mkdtempSync(join(tmpdir(), "app-config-apply-"));
  const envPath = join(dir, "env");
  const summaryPath = join(dir, "summary");
  const outputPath = join(dir, "output");
  const result = spawnSync(process.execPath, [SCRIPT], {
    encoding: "utf8",
    input: readFileSync(join(FIXTURES, fixtureName), "utf8"),
    env: {
      ...process.env,
      APP_CONFIG_KEY_PREFIXES: PREFIXES,
      APP_CONFIG_LABEL: "leasemate-marketing",
      GITHUB_ENV: envPath,
      GITHUB_STEP_SUMMARY: summaryPath,
      GITHUB_OUTPUT: outputPath,
      ...extraEnv,
    },
  });
  return {
    result,
    envPath,
    summaryPath,
    outputPath,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

test("unlabeled only applies the unlabeled value", () => {
  const { applied, audit } = applyAppConfigKv(loadFixture("unlabeled.json"), {
    prefixes: PREFIXES,
    label: "leasemate-marketing",
  });
  assert.deepEqual(applied, [{ key: "PUBLIC_SITE_NAME", value: "LeaseMate" }]);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].label, "(none)");
});

test("unlabeled plus repo-label override: label wins", () => {
  const { applied, audit } = applyAppConfigKv(
    loadFixture("unlabeled-and-override.json"),
    { prefixes: PREFIXES, label: "leasemate-marketing" },
  );
  const byKey = Object.fromEntries(applied.map((row) => [row.key, row.value]));
  assert.equal(byKey.PUBLIC_LEAD_INTAKE_ENABLED, "true");
  assert.equal(byKey.PUBLIC_SITE_NAME, "LeaseMate");
  assert.equal(Object.hasOwn(byKey, "PUBLIC_OTHER_REPO"), false);
  assert.ok(audit.some((row) => row.key === "PUBLIC_LEAD_INTAKE_ENABLED" && row.label === "(none)"));
  assert.ok(
    audit.some(
      (row) => row.key === "PUBLIC_LEAD_INTAKE_ENABLED" && row.label === "leasemate-marketing",
    ),
  );
});

test("NEXT_PUBLIC_* key is applied", () => {
  const { applied } = applyAppConfigKv(loadFixture("next-public.json"), {
    prefixes: PREFIXES,
    label: "leasemate-marketing",
  });
  assert.deepEqual(applied, [
    { key: "NEXT_PUBLIC_APP_URL", value: "https://leasemate.example.test" },
  ]);
});

test("Key Vault reference fails and never prints its value", () => {
  const items = loadFixture("keyvault-ref.json");
  assert.equal(isKeyVaultReference(items[0]), true);
  assert.throws(
    () => applyAppConfigKv(items, { prefixes: PREFIXES, label: "leasemate-marketing" }),
    /Key Vault reference for PUBLIC_SECRET_THING/,
  );
  const ran = runCli("keyvault-ref.json");
  assert.notEqual(ran.result.status, 0);
  const combined = `${ran.stdout}\n${ran.stderr}`;
  assert.match(combined, /Key Vault reference/);
  assert.doesNotMatch(combined, new RegExp(KV_LEAK));
  assert.doesNotMatch(combined, /leaked/);
});

test("bad key name is rejected", () => {
  assert.throws(
    () =>
      applyAppConfigKv(loadFixture("bad-key.json"), {
        prefixes: PREFIXES,
        label: "leasemate-marketing",
      }),
    /PUBLIC_BAD-NAME/,
  );
  const ran = runCli("bad-key.json");
  assert.notEqual(ran.result.status, 0);
  assert.match(`${ran.stdout}\n${ran.stderr}`, /PUBLIC_BAD-NAME/);
});

test("wrong prefix is rejected", () => {
  assert.throws(
    () =>
      applyAppConfigKv(loadFixture("wrong-prefix.json"), {
        prefixes: PREFIXES,
        label: "leasemate-marketing",
      }),
    /SECRET_VALUE/,
  );
});

test("multi-line value uses a GITHUB_ENV heredoc", () => {
  const { applied } = applyAppConfigKv(loadFixture("multiline.json"), {
    prefixes: PREFIXES,
    label: "leasemate-marketing",
  });
  assert.equal(applied[0].value, "line one\nline two");
  const block = githubEnvBlock(
    "PUBLIC_FOOTER",
    "line one\nline two",
    parsePrefixesForTest(),
    () => "APPCONFIG_fixeddelim",
  );
  assert.equal(block, "PUBLIC_FOOTER<<APPCONFIG_fixeddelim\nline one\nline two\nAPPCONFIG_fixeddelim\n");

  const ran = runCli("multiline.json");
  assert.equal(ran.result.status, 0, ran.stderr);
  const env = readFileSync(ran.envPath, "utf8");
  assert.match(env, /^PUBLIC_FOOTER<</m);
  assert.match(env, /line one\nline two\n/);
});

test("CLI writes env, summary, outputs, and audit log", () => {
  const ran = runCli("happy-path.json");
  assert.equal(ran.result.status, 0, ran.stderr);
  const env = readFileSync(ran.envPath, "utf8");
  assert.match(env, /PUBLIC_LEAD_INTAKE_ENABLED<</);
  assert.match(env, /true/);
  assert.match(env, /NEXT_PUBLIC_APP_URL<</);
  const summary = readFileSync(ran.summaryPath, "utf8");
  assert.match(summary, /Azure App Configuration audit/);
  assert.match(summary, /leasemate-marketing/);
  const output = readFileSync(ran.outputPath, "utf8");
  assert.match(output, /^count=4$/m);
  assert.match(output, /^applied<</m);
  assert.match(ran.stdout, /appconfig applied 4 key\(s\)/);
  assert.match(ran.stdout, /label=leasemate-marketing value=true/);
});

test("audit markdown uses (none) for unlabeled rows", () => {
  const md = auditSummaryMarkdown(
    [
      {
        key: "PUBLIC_SITE_NAME",
        label: "(none)",
        value: "LeaseMate",
        etag: "etag",
        lastModified: "2026-01-02T00:00:00+00:00",
      },
    ],
    { label: "leasemate-marketing" },
  );
  assert.match(md, /`\(none\)`/);
  assert.match(md, /LeaseMate/);
});

test("empty stdin fails", () => {
  const result = spawnSync(process.execPath, [SCRIPT], {
    encoding: "utf8",
    input: "  \n",
    env: {
      ...process.env,
      APP_CONFIG_KEY_PREFIXES: PREFIXES,
      APP_CONFIG_LABEL: "leasemate-marketing",
    },
  });
  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}\n${result.stderr}`, /empty/);
});

function parsePrefixesForTest() {
  return PREFIXES.split(",");
}
