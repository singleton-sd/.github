#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/npm-publish-guard.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

run_guard() {
  local outfile="$1"
  shift
  set +e
  env -u GITHUB_OUTPUT -u NODE_AUTH_TOKEN -u NPM_TOKEN \
    -u ACTIONS_ID_TOKEN_REQUEST_URL \
    "$@" bash "$SCRIPT" >"$outfile" 2>&1
  local got=$?
  set -e
  printf '%s' "$got"
}

assert_exit() {
  local want="$1" label="$2"
  shift 2
  local out got
  out="$(mktemp)"
  got="$(run_guard "$out" "$@")"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL ${label}: expected exit ${want} got ${got}"
    cat "$out"
    rm -f "$out"
    exit 1
  fi
  echo "$out"
}

assert_no_leak() {
  local file="$1" needle="$2" label="$3"
  if grep -F -q -- "$needle" "$file"; then
    echo "FAIL ${label}: leaked value in guard output"
    cat "$file"
    exit 1
  fi
}

write_pkg() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/package.json"
}

LEAK="should-not-appear-guard-value"

out="$(assert_exit 1 "missing id-token" WORKING_DIRECTORY="$WORKDIR")"
grep -q "id-token" "$out" || {
  echo "FAIL: expected id-token hint when ACTIONS_ID_TOKEN_REQUEST_URL is empty"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects missing ACTIONS_ID_TOKEN_REQUEST_URL"

out="$(assert_exit 1 "NODE_AUTH_TOKEN set" NODE_AUTH_TOKEN="$LEAK" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
assert_no_leak "$out" "$LEAK" "NODE_AUTH_TOKEN"
grep -q "NODE_AUTH_TOKEN" "$out" || {
  echo "FAIL: expected NODE_AUTH_TOKEN in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects NODE_AUTH_TOKEN"

out="$(assert_exit 1 "NPM_TOKEN set" NPM_TOKEN="$LEAK" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
assert_no_leak "$out" "$LEAK" "NPM_TOKEN"
grep -q "NPM_TOKEN" "$out" || {
  echo "FAIL: expected NPM_TOKEN in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects NPM_TOKEN"

private="$WORKDIR/private"
write_pkg "$private" '{ "name": "@singleton-sd-selftest/private", "version": "1.0.0", "private": true }'
out="$(assert_exit 1 "private package" WORKING_DIRECTORY="$private" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
grep -q "private: true" "$out" || {
  echo "FAIL: expected private: true in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects private: true"

missing_name="$WORKDIR/missing-name"
write_pkg "$missing_name" '{ "version": "1.0.0" }'
out="$(assert_exit 1 "missing name" WORKING_DIRECTORY="$missing_name" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
grep -q "name" "$out" || {
  echo "FAIL: expected name in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects missing name"

missing_version="$WORKDIR/missing-version"
write_pkg "$missing_version" '{ "name": "@singleton-sd-selftest/no-version" }'
out="$(assert_exit 1 "missing version" WORKING_DIRECTORY="$missing_version" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
grep -q "version" "$out" || {
  echo "FAIL: expected version in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects missing version"

valid="$WORKDIR/valid"
write_pkg "$valid" '{ "name": "@singleton-sd-selftest/ok", "version": "0.0.0-selftest.1" }'
out="$(assert_exit 0 "valid package" WORKING_DIRECTORY="$valid" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
grep -q "@singleton-sd-selftest/ok@0.0.0-selftest.1" "$out" || {
  echo "FAIL: expected resolved package line"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK accepts public package with name and version"

nested="$WORKDIR/nested-root"
write_pkg "$nested/pkg" '{ "name": "@singleton-sd-selftest/nested", "version": "2.0.0" }'
out="$(assert_exit 0 "nested package_dir" WORKING_DIRECTORY="$nested" PACKAGE_DIR="pkg" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
grep -q "@singleton-sd-selftest/nested@2.0.0" "$out" || {
  echo "FAIL: expected nested package resolution"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK resolves working_directory/package_dir"

grep -F -q -- "--provenance" "$ROOT/scripts/npm-publish.sh" || {
  echo "FAIL: scripts/npm-publish.sh must include --provenance for Trusted Publishing"
  exit 1
}
grep -F -q -- "--dry-run" "$ROOT/scripts/npm-publish.sh" || {
  echo "FAIL: scripts/npm-publish.sh must include --dry-run"
  exit 1
}
grep -F -q -- "--ignore-scripts" "$ROOT/scripts/npm-publish.sh" || {
  echo "FAIL: scripts/npm-publish.sh must include --ignore-scripts"
  exit 1
}
echo "OK publish script includes --provenance, --dry-run, and --ignore-scripts"

echo "npm-publish-guard: all cases passed"
