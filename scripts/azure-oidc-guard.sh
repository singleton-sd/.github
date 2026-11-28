#!/usr/bin/env bash
# Reject client-secret Azure auth. Callers must use GitHub OIDC
# (permissions: id-token: write) and never set a client secret.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

if [ -n "${AZURE_CLIENT_SECRET:-}" ]; then
  fail "AZURE_CLIENT_SECRET is set. Use GitHub OIDC (azure/login with client-id) instead of a client secret."
fi
if [ -n "${AZURE_CREDENTIALS:-}" ]; then
  fail "AZURE_CREDENTIALS is set. Use GitHub OIDC (azure/login with client-id) instead of a client secret JSON blob."
fi
if [ -n "${ARM_CLIENT_SECRET:-}" ]; then
  fail "ARM_CLIENT_SECRET is set. Use GitHub OIDC (azure/login with client-id) instead of a client secret."
fi
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  fail "ACTIONS_ID_TOKEN_REQUEST_URL is empty. Grant permissions: id-token: write on the caller job so GitHub OIDC can mint a token."
fi
