#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/setup-pnpm-node-guard.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

run_guard() {
  local outfile="$1"
  shift
  set +e
  env -u GITHUB_OUTPUT "$@" bash "$SCRIPT" >"$outfile" 2>&1
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

write_pkg() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/package.json"
}

missing="$WORKDIR/missing"
write_pkg "$missing" '{ "name": "no-pm", "private": true }'
out="$(assert_exit 1 "missing packageManager" WORKING_DIRECTORY="$missing")"
grep -q "missing packageManager" "$out" || {
  echo "FAIL: expected missing packageManager in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects missing packageManager"

yarn="$WORKDIR/yarn"
write_pkg "$yarn" '{ "name": "yarn", "private": true, "packageManager": "yarn@4" }'
out="$(assert_exit 1 "wrong manager yarn@4" WORKING_DIRECTORY="$yarn")"
grep -q "yarn@4" "$out" || {
  echo "FAIL: expected yarn@4 in error message"
  cat "$out"
  exit 1
}
grep -q "pnpm@" "$out" || {
  echo "FAIL: expected pnpm@ hint when packageManager is yarn@4"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects yarn@4"

valid="$WORKDIR/valid"
write_pkg "$valid" '{ "name": "valid", "private": true, "packageManager": "pnpm@10.33.4" }'
out="$(assert_exit 0 "valid pnpm@10.33.4" WORKING_DIRECTORY="$valid")"
grep -Fxq "Resolved pnpm version: 10.33.4" "$out" || {
  echo "FAIL: expected resolved pnpm 10.33.4"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK accepts pnpm@10.33.4"

hashed="$WORKDIR/hashed"
write_pkg "$hashed" '{ "name": "hashed", "private": true, "packageManager": "pnpm@10.33.4+sha512.0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }'
out="$(assert_exit 0 "valid pnpm with sha512 suffix" WORKING_DIRECTORY="$hashed")"
grep -Fxq "Resolved pnpm version: 10.33.4" "$out" || {
  echo "FAIL: expected resolved pnpm 10.33.4 with +sha512 suffix stripped"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK accepts pnpm@10.33.4+sha512"

conflict="$WORKDIR/conflict"
write_pkg "$conflict" '{ "name": "conflict", "private": true, "packageManager": "pnpm@10.33.4", "devEngines": { "packageManager": { "name": "pnpm", "version": "9.15.0" } } }'
out="$(assert_exit 1 "conflicting devEngines pnpm 9.15.0" WORKING_DIRECTORY="$conflict")"
grep -q "devEngines.packageManager.version conflicts" "$out" || {
  echo "FAIL: expected conflict error for packageManager 10.33.4 vs devEngines 9.15.0"
  cat "$out"
  exit 1
}
grep -q "9.15.0" "$out" || {
  echo "FAIL: expected 9.15.0 in conflict error"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects packageManager vs devEngines conflict"

aligned="$WORKDIR/aligned"
write_pkg "$aligned" '{ "name": "aligned", "private": true, "packageManager": "pnpm@10.33.4", "devEngines": { "packageManager": { "name": "pnpm", "version": "10.33.4" } } }'
out="$(assert_exit 0 "aligned devEngines pnpm 10.33.4" WORKING_DIRECTORY="$aligned")"
grep -Fxq "Resolved pnpm version: 10.33.4" "$out" || {
  echo "FAIL: expected resolved pnpm 10.33.4 when devEngines matches"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK accepts matching packageManager and devEngines"

echo "setup-pnpm-node-guard: all cases passed"
