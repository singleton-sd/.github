#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/azure-oidc-guard.sh"

run_guard() {
  local outfile="$1"
  shift
  set +e
  env -u AZURE_CLIENT_SECRET -u AZURE_CREDENTIALS -u ARM_CLIENT_SECRET \
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

LEAK="should-not-appear-guard-value"

out="$(assert_exit 1 "AZURE_CLIENT_SECRET set" AZURE_CLIENT_SECRET="$LEAK" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
assert_no_leak "$out" "$LEAK" "AZURE_CLIENT_SECRET"
grep -q "AZURE_CLIENT_SECRET" "$out" || {
  echo "FAIL: expected AZURE_CLIENT_SECRET in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects AZURE_CLIENT_SECRET"

out="$(assert_exit 1 "AZURE_CREDENTIALS set" AZURE_CREDENTIALS="$LEAK" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
assert_no_leak "$out" "$LEAK" "AZURE_CREDENTIALS"
grep -q "AZURE_CREDENTIALS" "$out" || {
  echo "FAIL: expected AZURE_CREDENTIALS in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects AZURE_CREDENTIALS"

out="$(assert_exit 1 "ARM_CLIENT_SECRET set" ARM_CLIENT_SECRET="$LEAK" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
assert_no_leak "$out" "$LEAK" "ARM_CLIENT_SECRET"
grep -q "ARM_CLIENT_SECRET" "$out" || {
  echo "FAIL: expected ARM_CLIENT_SECRET in error message"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects ARM_CLIENT_SECRET"

out="$(assert_exit 1 "missing id-token")"
grep -q "id-token" "$out" || {
  echo "FAIL: expected id-token hint when ACTIONS_ID_TOKEN_REQUEST_URL is empty"
  cat "$out"
  exit 1
}
rm -f "$out"
echo "OK rejects missing ACTIONS_ID_TOKEN_REQUEST_URL"

out="$(assert_exit 0 "oidc ready" ACTIONS_ID_TOKEN_REQUEST_URL="https://example.test/idtoken")"
if [ -s "$out" ]; then
  echo "FAIL: expected no output on success"
  cat "$out"
  exit 1
fi
rm -f "$out"
echo "OK accepts OIDC-ready environment"

echo "azure-oidc-guard: all cases passed"
