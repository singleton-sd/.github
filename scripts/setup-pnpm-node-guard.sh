#!/usr/bin/env bash
# Resolve pnpm from package.json#packageManager. There is no version override.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

WORKDIR="${WORKING_DIRECTORY:-.}"
WORKDIR="${WORKDIR%/}"
if [ -z "$WORKDIR" ]; then
  WORKDIR="."
fi

PKG="${WORKDIR}/package.json"
if [ ! -f "$PKG" ]; then
  fail "package.json not found in ${WORKDIR}. This action reads packageManager from the caller's package.json."
fi

errfile="$(mktemp)"
pm=""
set +e
pm="$(python3 -c '
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get("packageManager")
if value is None:
    sys.stdout.write("")
elif not isinstance(value, str):
    sys.stderr.write("packageManager must be a string\n")
    sys.exit(2)
else:
    sys.stdout.write(value)
    if not value.startswith("pnpm@"):
        sys.exit(0)
    resolved = value[len("pnpm@"):].split("+", 1)[0]
    dev = data.get("devEngines")
    if not isinstance(dev, dict):
        sys.exit(0)
    pm_dev = dev.get("packageManager")
    if not isinstance(pm_dev, dict):
        sys.exit(0)
    name = pm_dev.get("name")
    ver = pm_dev.get("version")
    if isinstance(name, str) and name and name != "pnpm":
        sys.stderr.write(
            "devEngines.packageManager.name must be pnpm when packageManager is pnpm@.... "
            f"Got: {name}\n"
        )
        sys.exit(3)
    if name == "pnpm" and isinstance(ver, str) and ver and ver != resolved:
        sys.stderr.write(
            "devEngines.packageManager.version conflicts with packageManager. "
            f"packageManager resolves to {resolved}; devEngines specifies {ver}. "
            "Align them or remove devEngines.packageManager. "
            "pnpm/action-setup would otherwise install the devEngines version.\n"
        )
        sys.exit(3)
' "$PKG" 2>"$errfile")"
status=$?
set -e
err="$(tr '\n' ' ' < "$errfile" | sed 's/[[:space:]]*$//')"
rm -f "$errfile"
if [ "$status" -eq 3 ]; then
  fail "${err:-devEngines.packageManager conflicts with packageManager.}"
fi
if [ "$status" -ne 0 ]; then
  fail "Could not read packageManager from ${PKG}. The file must be valid JSON with a string packageManager field."
fi

if [ -z "$pm" ]; then
  fail "package.json is missing packageManager. Set packageManager to pnpm@<semver> (for example pnpm@10.33.4). Do not pass a version input."
fi

if ! printf '%s\n' "$pm" | grep -Eq '^pnpm@[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  fail "packageManager must be pnpm@<semver> (optional +sha512 hash). Got: ${pm}"
fi

version="${pm#pnpm@}"
version="${version%%+*}"
echo "Resolved pnpm version: ${version}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "pnpm-version=${version}" >> "$GITHUB_OUTPUT"
fi
