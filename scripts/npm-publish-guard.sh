#!/usr/bin/env bash
# Guard for actions/npm-publish. No tokens. Caller needs id-token: write.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

if [ -n "${NODE_AUTH_TOKEN:-}" ]; then
  fail "NODE_AUTH_TOKEN is set. This action uses npm Trusted Publishing (OIDC). Do not pass or export NODE_AUTH_TOKEN or NPM_TOKEN."
fi
if [ -n "${NPM_TOKEN:-}" ]; then
  fail "NPM_TOKEN is set. This action uses npm Trusted Publishing (OIDC). Do not pass or export NODE_AUTH_TOKEN or NPM_TOKEN."
fi
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  fail "ACTIONS_ID_TOKEN_REQUEST_URL is empty. Grant permissions: id-token: write on the caller job so npm Trusted Publishing can mint an OIDC token."
fi

join_pkg_dir() {
  local work="${1:-.}" pkg="${2:-.}"
  work="${work%/}"
  pkg="${pkg%/}"
  if [ -z "$work" ]; then
    work="."
  fi
  if [ -z "$pkg" ]; then
    pkg="."
  fi
  if [ "$pkg" = "." ]; then
    printf '%s\n' "$work"
    return
  fi
  if [ "$work" = "." ]; then
    printf '%s\n' "$pkg"
    return
  fi
  printf '%s/%s\n' "$work" "$pkg"
}

WORKDIR="${WORKING_DIRECTORY:-.}"
PKGDIR="${PACKAGE_DIR:-.}"
RESOLVED="$(join_pkg_dir "$WORKDIR" "$PKGDIR")"

if [ ! -d "$RESOLVED" ]; then
  fail "package directory ${RESOLVED} does not exist."
fi

PKG="${RESOLVED}/package.json"
if [ ! -f "$PKG" ]; then
  fail "package.json not found in ${RESOLVED}."
fi

errfile="$(mktemp)"
meta=""
set +e
meta="$(python3 -c '
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
if not isinstance(data, dict):
    sys.stderr.write("package.json must be a JSON object\n")
    sys.exit(2)
if data.get("private") is True:
    sys.stderr.write("package.json has private: true; refusing to publish\n")
    sys.exit(3)
name = data.get("name")
version = data.get("version")
if not isinstance(name, str) or not name.strip():
    sys.stderr.write("package.json is missing a non-empty name\n")
    sys.exit(2)
if not isinstance(version, str) or not version.strip():
    sys.stderr.write("package.json is missing a non-empty version\n")
    sys.exit(2)
sys.stdout.write(name.strip() + "\n" + version.strip() + "\n")
' "$PKG" 2>"$errfile")"
status=$?
set -e
err="$(tr '\n' ' ' < "$errfile" | sed 's/[[:space:]]*$//')"
rm -f "$errfile"
if [ "$status" -eq 3 ]; then
  fail "${err:-package.json has private: true; refusing to publish.}"
fi
if [ "$status" -ne 0 ]; then
  fail "${err:-Could not read name and version from ${PKG}.}"
fi

name="$(printf '%s\n' "$meta" | sed -n '1p')"
version="$(printf '%s\n' "$meta" | sed -n '2p')"
echo "Resolved package ${name}@${version} from ${PKG}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "package-dir=${RESOLVED}"
    echo "package-json=${PKG}"
    echo "name=${name}"
    echo "version=${version}"
  } >> "$GITHUB_OUTPUT"
fi
