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

pm=""
if ! pm="$(python3 -c '
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
' "$PKG")"; then
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
