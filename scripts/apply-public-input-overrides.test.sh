#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/apply-public-input-overrides.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

export GITHUB_ENV="$WORKDIR/github.env"

{
  echo "PUBLIC_TURNSTILE_SITE_KEY=from-store"
  echo "PUBLIC_LEAD_INTAKE_ENABLED=true"
  echo "PUBLIC_LEADS_API_URL=https://store.example.test"
} >"$GITHUB_ENV"

INPUT_PUBLIC_TURNSTILE_SITE_KEY="1x00000000000000000000AA" \
INPUT_PUBLIC_LEAD_INTAKE_ENABLED="" \
INPUT_PUBLIC_LEADS_API_URL="" \
bash "$SCRIPT"

if ! grep -q '^PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA$' "$GITHUB_ENV"; then
  fail "explicit turnstile input should win"
fi
if [ "$(grep -c '^PUBLIC_LEAD_INTAKE_ENABLED=true$' "$GITHUB_ENV")" -ne 1 ]; then
  fail "empty lead-intake input should leave store value"
fi
if [ "$(grep -c '^PUBLIC_LEADS_API_URL=https://store.example.test$' "$GITHUB_ENV")" -ne 1 ]; then
  fail "empty leads-api input should leave store value"
fi

INPUT_PUBLIC_LEAD_INTAKE_ENABLED="false" \
INPUT_PUBLIC_TURNSTILE_SITE_KEY="" \
INPUT_PUBLIC_LEADS_API_URL="https://override.example.test" \
bash "$SCRIPT"

if ! grep -q '^PUBLIC_LEAD_INTAKE_ENABLED=false$' "$GITHUB_ENV"; then
  fail "explicit lead-intake input should win"
fi
if ! grep -q '^PUBLIC_LEADS_API_URL=https://override.example.test$' "$GITHUB_ENV"; then
  fail "explicit leads-api input should win"
fi

echo "OK apply-public-input-overrides"
