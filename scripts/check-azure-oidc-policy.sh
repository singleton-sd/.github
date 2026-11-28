#!/usr/bin/env bash
# Fail if shared YAML still uses client-secret Azure auth (ADR-012).
# Scans workflow, composite-action, and org-template YAML only.
# Comments that merely forbid these words are allowed.
set -euo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"

python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path

import yaml

ROOT = Path(sys.argv[1])
FORBIDDEN_TOKENS = ("AZURE_CLIENT_SECRET", "AZURE_CREDENTIALS", "ARM_CLIENT_SECRET")
errors = []


def collect_files():
    files = []
    files.extend(sorted((ROOT / ".github" / "workflows").glob("*.yml")))
    files.extend(sorted((ROOT / "workflow-templates").glob("*.yml")))
    actions = ROOT / "actions"
    if actions.is_dir():
        files.extend(sorted(actions.glob("**/action.yml")))
    return files


def walk_forbidden(node, path):
    if isinstance(node, dict):
        uses = node.get("uses")
        with_block = node.get("with")
        if isinstance(uses, str) and "azure/login" in uses.lower():
            if isinstance(with_block, dict) and "creds" in with_block:
                errors.append(
                    f"{path}: azure/login has a creds: input; use client-id OIDC instead"
                )
        for key, value in node.items():
            if key in FORBIDDEN_TOKENS:
                errors.append(f"{path}: forbidden key {key}")
            if key == "client-secret":
                errors.append(f"{path}: forbidden key client-secret")
            walk_forbidden(value, path)
        return
    if isinstance(node, list):
        for item in node:
            walk_forbidden(item, path)
        return
    if isinstance(node, str):
        for token in FORBIDDEN_TOKENS:
            if token in node:
                errors.append(f"{path}: forbidden token {token}")


files = collect_files()
if not files:
    print(f"check-azure-oidc-policy: no YAML files under {ROOT}", file=sys.stderr)
    sys.exit(1)

for path in files:
    try:
        with path.open(encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle)
    except yaml.YAMLError as exc:
        errors.append(f"{path}: YAML parse error: {exc}")
        continue
    if loaded is None:
        continue
    walk_forbidden(loaded, path.relative_to(ROOT))

if errors:
    for item in errors:
        print(f"::error::{item}", file=sys.stderr)
        print(item, file=sys.stderr)
    sys.exit(1)

print(f"check-azure-oidc-policy: {len(files)} YAML file(s) passed under {ROOT}")
PY
