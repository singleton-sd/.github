#!/usr/bin/env node
/**
 * Compute gitleaks --log-opts for the caller event.
 * Usage: EVENT_NAME PR_BASE PR_HEAD PUSH_BEFORE PUSH_AFTER node scripts/gitleaks-log-opts.mjs
 */
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const ZERO = "0000000000000000000000000000000000000000";

function isMain() {
  try {
    return import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
}

function git(cwd, args) {
  const proc = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (proc.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed`);
  }
  return (proc.stdout || "").trim();
}

export function computeGitleaksLogOpts(input, gitCwd = process.cwd()) {
  const eventName = input.eventName || "";
  const prBase = input.prBase || "";
  const prHead = input.prHead || "";
  const pushBefore = input.pushBefore || "";
  const pushAfter = input.pushAfter || "";

  if (eventName === "pull_request" && prBase && prHead) {
    return `${prBase}..${prHead}`;
  }
  if (pushBefore && pushBefore !== ZERO && pushAfter) {
    return `${pushBefore}..${pushAfter}`;
  }
  const afterRef = pushAfter || "HEAD";
  const after = git(gitCwd, ["rev-parse", afterRef]);
  const listed = git(gitCwd, [
    "for-each-ref",
    "--format=%(objectname)",
    "refs/heads",
    "refs/remotes",
    "refs/tags",
  ]);
  const others = [
    ...new Set(
      listed
        .split("\n")
        .map((line) => line.trim())
        .filter((sha) => sha && sha !== after),
    ),
  ];
  if (others.length === 0) {
    return after;
  }
  return `${after} --not ${others.join(" ")}`;
}

if (isMain()) {
  try {
    const opts = computeGitleaksLogOpts({
      eventName: process.env.EVENT_NAME || "",
      prBase: process.env.PR_BASE || "",
      prHead: process.env.PR_HEAD || "",
      pushBefore: process.env.PUSH_BEFORE || "",
      pushAfter: process.env.PUSH_AFTER || "",
    });
    if (opts === "-1") {
      throw new Error("gitleaks log-opts must not fall back to -1");
    }
    process.stdout.write(`${opts}\n`);
  } catch (err) {
    process.stderr.write(`${err instanceof Error ? err.message : "gitleaks log-opts failed"}\n`);
    process.exit(1);
  }
}
