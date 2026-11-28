#!/usr/bin/env bash
# Fail if the self-release workflow gains a pull_request trigger or an unpinned uses:.
set -euo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
WORKFLOW="${2:-$ROOT/.github/workflows/self-release.yml}"

python3 - "$ROOT" "$WORKFLOW" <<'PY'
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(sys.argv[1])
workflow = Path(sys.argv[2])
FORBIDDEN_ON = ("pull_request", "pull_request_target")
SHA_USES = re.compile(r"^.+@[0-9a-fA-F]{40}$")
errors = []


def on_triggers(on_block):
    if on_block is None:
        return []
    if isinstance(on_block, str):
        return [on_block]
    if isinstance(on_block, list):
        return [item for item in on_block if isinstance(item, str)]
    if isinstance(on_block, dict):
        return list(on_block.keys())
    return []


def walk_uses(node, found):
    if isinstance(node, dict):
        uses = node.get("uses")
        if isinstance(uses, str):
            found.append(uses)
        for value in node.values():
            walk_uses(value, found)
        return
    if isinstance(node, list):
        for item in node:
            walk_uses(item, found)


if not workflow.is_file():
    print(f"::error::{workflow}: release workflow is missing", file=sys.stderr)
    sys.exit(1)

try:
    with workflow.open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
except yaml.YAMLError as exc:
    print(f"::error::{workflow}: YAML parse error: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(loaded, dict):
    print(f"::error::{workflow}: expected a mapping", file=sys.stderr)
    sys.exit(1)

try:
    rel = workflow.resolve().relative_to(ROOT.resolve())
except ValueError:
    rel = workflow

# PyYAML 1.1 treats the GitHub key `on` as boolean True.
on_block = loaded["on"] if "on" in loaded else loaded.get(True)
for trigger in on_triggers(on_block):
    if trigger in FORBIDDEN_ON:
        errors.append(f"{rel}: forbidden '{trigger}' trigger")

uses_values = []
walk_uses(loaded, uses_values)
if not uses_values:
    errors.append(f"{rel}: expected at least one pinned uses:")
for uses in uses_values:
    if not SHA_USES.fullmatch(uses):
        errors.append(f"{rel}: unpinned uses: {uses}")

if errors:
    for item in errors:
        print(f"::error::{item}", file=sys.stderr)
        print(item, file=sys.stderr)
    sys.exit(1)

print(f"check-release-workflow-policy: {rel} passed")
PY
