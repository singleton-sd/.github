#!/usr/bin/env bash
# Keep in sync with the "Require Turnstile site key" step in
# .github/workflows/pages-build.yml
set -euo pipefail
case "${PUBLIC_LEAD_INTAKE_ENABLED:-}" in
  true|TRUE|1|yes|YES) enabled=1 ;;
  *) enabled=0 ;;
esac
case "${TURNSTILE_POLICY}" in
  always)
    if [ -z "${PUBLIC_TURNSTILE_SITE_KEY:-}" ]; then
      echo "::error::Set repository variable PUBLIC_TURNSTILE_SITE_KEY (public site key only)."
      exit 1
    fi
    ;;
  when-lead-intake-enabled)
    if [ "$enabled" = 1 ] && [ -z "${PUBLIC_TURNSTILE_SITE_KEY:-}" ]; then
      echo "::error::Set repository variable PUBLIC_TURNSTILE_SITE_KEY (public site key only) before enabling PUBLIC_LEAD_INTAKE_ENABLED."
      exit 1
    fi
    ;;
  *)
    echo "::error::Unknown turnstile_policy '${TURNSTILE_POLICY}' (expected always or when-lead-intake-enabled)."
    exit 1
    ;;
esac
