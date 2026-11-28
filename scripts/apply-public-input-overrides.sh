#!/usr/bin/env bash
# Write non-empty public_* workflow inputs to GITHUB_ENV so they win over
# App Configuration (and over vars). Empty inputs leave existing values.
set -euo pipefail

if [ -z "${GITHUB_ENV:-}" ]; then
  echo "::error::GITHUB_ENV is not set." >&2
  exit 1
fi

write_if_set() {
  local name="$1"
  local value="$2"
  if [ -n "$value" ]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
  fi
}

write_if_set PUBLIC_TURNSTILE_SITE_KEY "${INPUT_PUBLIC_TURNSTILE_SITE_KEY:-}"
write_if_set PUBLIC_LEAD_INTAKE_ENABLED "${INPUT_PUBLIC_LEAD_INTAKE_ENABLED:-}"
write_if_set PUBLIC_LEADS_API_URL "${INPUT_PUBLIC_LEADS_API_URL:-}"
