#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-turnstile-policy.sh"

check() {
  local want="$1" policy="$2" enabled="$3" key="$4"
  set +e
  TURNSTILE_POLICY="$policy" PUBLIC_LEAD_INTAKE_ENABLED="$enabled" PUBLIC_TURNSTILE_SITE_KEY="$key" \
    bash "$SCRIPT" >/tmp/turnstile-out 2>&1
  local got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "FAIL policy=${policy} enabled=${enabled} key=${key:+set} expected ${want} got ${got}"
    cat /tmp/turnstile-out
    exit 1
  fi
  echo "OK policy=${policy} enabled=${enabled} key=${key:+set} exit ${got}"
}

check 1 always "" ""
check 0 always "" "sitekey"
check 1 when-lead-intake-enabled true ""
check 0 when-lead-intake-enabled true "sitekey"
check 0 when-lead-intake-enabled false ""
check 1 nosuch "" "sitekey"
echo "check-turnstile-policy: all cases passed"
