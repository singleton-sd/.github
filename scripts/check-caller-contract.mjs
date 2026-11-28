#!/usr/bin/env node
/**
 * Caller-contract check for repositories that call security-scan.yml.
 *
 * Scans the caller's workflow files (not this shared repo's own contract).
 * Usage:
 *   node scripts/check-caller-contract.mjs [--root DIR] [--banned-steps PATH]
 *     [--enforce-banned-steps true|false] [--json-out PATH]
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const THIS_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_BANNED = join(THIS_DIR, "banned-steps.json");
const SHA_REF = /^[0-9a-fA-F]{40}$/;
const V1_REF = /^(?:v1|v1\.\d+\.\d+)$/;

function isMain() {
  try {
    return import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
}

export function loadYaml(text) {
  const proc = spawnSync(
    "python3",
    [
      "-I",
      "-c",
      "import json,sys,yaml; json.dump(yaml.safe_load(sys.stdin), sys.stdout)",
    ],
    { input: text, encoding: "utf8", cwd: tmpdir() },
  );
  if (proc.status !== 0) {
    const lineMatch = /line (\d+)/.exec(proc.stderr || "");
    const error = new Error("YAML parse error");
    error.line = lineMatch ? Number(lineMatch[1]) : 0;
    throw error;
  }
  if (!proc.stdout) {
    return null;
  }
  return JSON.parse(proc.stdout);
}

export function loadBannedSteps(path = DEFAULT_BANNED) {
  const loaded = JSON.parse(readFileSync(path, "utf8"));
  const steps = loaded && Array.isArray(loaded.steps) ? loaded.steps : [];
  return steps.map((entry) => {
    const usesContains = entry.usesContains;
    return {
      id: String(entry.id || ""),
      replacement: String(entry.replacement || ""),
      enforce: entry.enforce === true,
      usesContains: Array.isArray(usesContains)
        ? usesContains.map(String)
        : usesContains
          ? [String(usesContains)]
          : [],
      runPattern: typeof entry.runPattern === "string" && entry.runPattern
        ? new RegExp(entry.runPattern, "i")
        : null,
      flipWhen: typeof entry.flip_when === "string" ? entry.flip_when : "",
    };
  });
}

function listYaml(dir) {
  if (!existsSync(dir)) {
    return [];
  }
  return readdirSync(dir)
    .filter((name) => name.endsWith(".yml") || name.endsWith(".yaml"))
    .filter((name) => name !== "actions.lock")
    .map((name) => join(dir, name))
    .sort();
}

export function listCallerWorkflowFiles(root) {
  return [
    ...listYaml(join(root, ".github", "workflows")),
    ...listYaml(join(root, "workflow-templates")),
  ];
}

function repoOfUses(uses) {
  const at = uses.lastIndexOf("@");
  return at === -1 ? uses : uses.slice(0, at);
}

function refOfUses(uses) {
  const at = uses.lastIndexOf("@");
  return at === -1 ? "" : uses.slice(at + 1);
}

export function classifyUses(uses) {
  if (typeof uses !== "string" || uses.trim() === "") {
    return { ok: false, reason: "empty uses" };
  }
  if (uses.startsWith("./") || uses.startsWith("docker://")) {
    return { ok: true, kind: "local" };
  }
  const repo = repoOfUses(uses);
  const ref = refOfUses(uses);
  if (!ref) {
    return { ok: false, reason: `unpinned uses: ${uses}` };
  }
  if (SHA_REF.test(ref)) {
    return { ok: true, kind: "sha" };
  }
  if (repo.startsWith("singleton-sd/") && V1_REF.test(ref)) {
    return { ok: true, kind: "v1" };
  }
  if (repo.startsWith("singleton-sd/")) {
    return {
      ok: false,
      reason: `singleton-sd ref must be a 40-hex SHA, @v1, or @v1.x.y; got ${uses}`,
    };
  }
  return {
    ok: false,
    reason: `third-party action pinned by tag or branch: ${uses}`,
  };
}

function usesContainsNeedle(uses, needle) {
  const repo = repoOfUses(uses).toLowerCase();
  const want = needle.toLowerCase();
  return repo === want || repo.endsWith(`/${want}`);
}

function collectFindings(rel, loaded, banned, enforceBannedSteps) {
  const errors = [];
  const warnings = [];

  function checkUses(uses) {
    const classified = classifyUses(uses);
    if (!classified.ok) {
      errors.push({
        rule: "unpinned-uses",
        message: `${rel}: ${classified.reason}`,
      });
    }
    for (const entry of banned) {
      const hitUses = entry.usesContains.some((needle) =>
        usesContainsNeedle(uses, needle),
      );
      if (!hitUses) {
        continue;
      }
      const finding = {
        rule: entry.id,
        message: `${rel}: banned step ${entry.id}; use ${entry.replacement}`,
      };
      if (entry.enforce && enforceBannedSteps) {
        errors.push(finding);
      } else {
        warnings.push(finding);
      }
    }
  }

  function checkRun(run) {
    for (const entry of banned) {
      if (!entry.runPattern || !entry.runPattern.test(run)) {
        continue;
      }
      const finding = {
        rule: entry.id,
        message: `${rel}: banned step ${entry.id}; use ${entry.replacement}`,
      };
      if (entry.enforce && enforceBannedSteps) {
        errors.push(finding);
      } else {
        warnings.push(finding);
      }
    }
  }

  const jobs =
    loaded.jobs && typeof loaded.jobs === "object" && !Array.isArray(loaded.jobs)
      ? loaded.jobs
      : {};
  for (const job of Object.values(jobs)) {
    if (!job || typeof job !== "object" || Array.isArray(job)) {
      continue;
    }
    if (typeof job.uses === "string") {
      checkUses(job.uses);
    }
    if (job.secrets === "inherit") {
      errors.push({
        rule: "secrets-inherit",
        message: `${rel}: secrets: inherit is forbidden`,
      });
    }
    const steps = Array.isArray(job.steps) ? job.steps : [];
    for (const step of steps) {
      if (!step || typeof step !== "object" || Array.isArray(step)) {
        continue;
      }
      if (typeof step.uses === "string") {
        checkUses(step.uses);
      }
      if (typeof step.run === "string") {
        checkRun(step.run);
      }
    }
  }

  return { errors, warnings };
}

export function checkCallerContract(root, options = {}) {
  const enforceBannedSteps = options.enforceBannedSteps !== false;
  const banned = options.bannedSteps || loadBannedSteps(options.bannedStepsPath);
  const files = listCallerWorkflowFiles(root);
  const errors = [];
  const warnings = [];

  if (files.length === 0) {
    errors.push({
      rule: "no-workflows",
      message: "no workflow files under .github/workflows or workflow-templates",
    });
    return { errors, warnings, files };
  }

  for (const file of files) {
    const rel = relative(root, file).replace(/\\/g, "/");
    const raw = readFileSync(file, "utf8");
    let loaded;
    try {
      loaded = loadYaml(raw);
    } catch (err) {
      const line = err && typeof err.line === "number" && err.line > 0 ? err.line : 0;
      errors.push({
        rule: "yaml-parse",
        message: line
          ? `YAML parse error in ${rel} at line ${line}`
          : `YAML parse error in ${rel}`,
      });
      continue;
    }
    if (!loaded || typeof loaded !== "object") {
      errors.push({
        rule: "yaml-parse",
        message: `${rel}: expected a mapping`,
      });
      continue;
    }
    const found = collectFindings(rel, loaded, banned, enforceBannedSteps);
    errors.push(...found.errors);
    warnings.push(...found.warnings);
  }

  return { errors, warnings, files };
}

function parseArgs(argv) {
  const args = {
    root: process.cwd(),
    bannedStepsPath: DEFAULT_BANNED,
    enforceBannedSteps: true,
    jsonOut: "",
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      args.help = true;
    } else if (arg === "--root") {
      args.root = argv[i + 1] || args.root;
      i += 1;
    } else if (arg.startsWith("--root=")) {
      args.root = arg.slice("--root=".length);
    } else if (arg === "--banned-steps") {
      args.bannedStepsPath = argv[i + 1] || args.bannedStepsPath;
      i += 1;
    } else if (arg.startsWith("--banned-steps=")) {
      args.bannedStepsPath = arg.slice("--banned-steps=".length);
    } else if (arg === "--enforce-banned-steps") {
      args.enforceBannedSteps = (argv[i + 1] || "true") !== "false";
      i += 1;
    } else if (arg.startsWith("--enforce-banned-steps=")) {
      args.enforceBannedSteps = arg.slice("--enforce-banned-steps=".length) !== "false";
    } else if (arg === "--json-out") {
      args.jsonOut = argv[i + 1] || "";
      i += 1;
    } else if (arg.startsWith("--json-out=")) {
      args.jsonOut = arg.slice("--json-out=".length);
    } else if (!arg.startsWith("-")) {
      args.root = arg;
    }
  }
  args.root = resolve(args.root);
  args.bannedStepsPath = resolve(args.bannedStepsPath);
  return args;
}

function uniqueRules(findings) {
  return [...new Set(findings.map((item) => item.rule).filter(Boolean))].sort();
}

export function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) {
    process.stdout.write(
      "Usage: node scripts/check-caller-contract.mjs [--root DIR] [--banned-steps PATH] [--enforce-banned-steps true|false] [--json-out PATH]\n",
    );
    return 0;
  }
  const result = checkCallerContract(args.root, {
    bannedStepsPath: args.bannedStepsPath,
    enforceBannedSteps: args.enforceBannedSteps,
  });
  for (const warning of result.warnings) {
    process.stderr.write(`::warning::${warning.message}\n`);
    process.stderr.write(`${warning.message}\n`);
  }
  for (const error of result.errors) {
    process.stderr.write(`::error::${error.message}\n`);
    process.stderr.write(`${error.message}\n`);
  }
  const payload = {
    fileCount: result.files.length,
    errorCount: result.errors.length,
    warningCount: result.warnings.length,
    errorRules: uniqueRules(result.errors),
    warningRules: uniqueRules(result.warnings),
  };
  if (args.jsonOut) {
    writeFileSync(args.jsonOut, `${JSON.stringify(payload)}\n`);
  }
  if (result.errors.length > 0) {
    process.stdout.write(
      `check-caller-contract: failed (${payload.errorCount} error(s), rules: ${payload.errorRules.join(", ") || "none"})\n`,
    );
    return 1;
  }
  process.stdout.write(
    `check-caller-contract: passed (${payload.fileCount} file(s), ${payload.warningCount} warning(s))\n`,
  );
  return 0;
}

if (isMain()) {
  process.exit(main());
}
