#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { computeGitleaksLogOpts } from "./gitleaks-log-opts.mjs";

const ZERO = "0000000000000000000000000000000000000000";

function git(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  return (result.stdout || "").trim();
}

test("first-push range includes earlier secret commit", () => {
  const root = mkdtempSync(join(tmpdir(), "gitleaks-range-"));
  git(root, ["init", "-b", "main"]);
  git(root, ["config", "user.email", "ci@example.test"]);
  git(root, ["config", "user.name", "ci"]);
  writeFileSync(join(root, "README"), "base\n");
  git(root, ["add", "README"]);
  git(root, ["commit", "-m", "base"]);
  const main = git(root, ["rev-parse", "HEAD"]);

  git(root, ["checkout", "-b", "feature"]);
  const prefix = ["A", "K", "I", "A"].join("");
  const body = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"].join("");
  writeFileSync(join(root, "token.txt"), `token=${prefix}${body}\n`);
  git(root, ["add", "token.txt"]);
  git(root, ["commit", "-m", "earlier"]);
  const secretCommit = git(root, ["rev-parse", "HEAD"]);

  writeFileSync(join(root, "README"), "base\nunrelated\n");
  git(root, ["add", "README"]);
  git(root, ["commit", "-m", "later unrelated"]);
  const after = git(root, ["rev-parse", "HEAD"]);

  const opts = computeGitleaksLogOpts(
    { eventName: "push", pushBefore: ZERO, pushAfter: after },
    root,
  );
  assert.notEqual(opts, "-1");
  const log = spawnSync("git", ["log", "--pretty=%H", ...opts.split(" ").filter(Boolean)], {
    cwd: root,
    encoding: "utf8",
  });
  assert.equal(log.status, 0, log.stderr);
  const shas = log.stdout.trim().split("\n").filter(Boolean);
  assert.ok(shas.includes(secretCommit), `earlier commit missing from ${opts}: ${shas.join(",")}`);
  assert.ok(shas.includes(after), `head commit missing from ${opts}`);
  assert.ok(!shas.includes(main), "default-branch history must not be scanned");
});

test("ordinary push keeps before..after", () => {
  const opts = computeGitleaksLogOpts({
    eventName: "push",
    pushBefore: "a".repeat(40),
    pushAfter: "b".repeat(40),
  });
  assert.equal(opts, `${"a".repeat(40)}..${"b".repeat(40)}`);
});
