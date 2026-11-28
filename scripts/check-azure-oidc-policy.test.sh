#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-azure-oidc-policy.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

write_tree() {
  local dest="$1"
  mkdir -p "$dest/.github/workflows" "$dest/actions/sample" "$dest/workflow-templates"
}

run_policy() {
  local tree="$1" outfile="$2"
  set +e
  bash "$SCRIPT" "$tree" >"$outfile" 2>&1
  local got=$?
  set -e
  printf '%s' "$got"
}

# Good tree: OIDC azure/login, comments that mention forbidden words, no client secret.
GOOD="$WORKDIR/good"
write_tree "$GOOD"
cat >"$GOOD/.github/workflows/ok.yml" <<'EOF'
# Do not set AZURE_CLIENT_SECRET, AZURE_CREDENTIALS, or ARM_CLIENT_SECRET.
# Never pass client-secret: or creds: to azure/login.
name: ok
on: push
jobs:
  login:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906 # v3.1.0
        with:
          client-id: example-client-id
          tenant-id: example-tenant-id
          subscription-id: example-subscription-id
EOF
cat >"$GOOD/actions/sample/action.yml" <<'EOF'
name: sample
description: Composite sample that logs in with OIDC only
runs:
  using: composite
  steps:
    - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906 # v3.1.0
      with:
        client-id: example-client-id
        tenant-id: example-tenant-id
        subscription-id: example-subscription-id
EOF
cat >"$GOOD/workflow-templates/ok.yml" <<'EOF'
# Forbid AZURE_CLIENT_SECRET in callers.
name: template-ok
on: workflow_dispatch
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF

OUT="$WORKDIR/out.txt"
got="$(run_policy "$GOOD" "$OUT")"
if [ "$got" -ne 0 ]; then
  echo "FAIL good tree should pass"
  cat "$OUT"
  exit 1
fi
echo "OK good tree passes (comments allowed)"

expect_fail() {
  local tree="$1" needle="$2" label="$3"
  got="$(run_policy "$tree" "$OUT")"
  if [ "$got" -eq 0 ]; then
    echo "FAIL ${label}: expected policy failure"
    cat "$OUT"
    exit 1
  fi
  grep -q "$needle" "$OUT" || {
    echo "FAIL ${label}: expected '$needle' in output"
    cat "$OUT"
    exit 1
  }
  echo "OK ${label}"
}

# AZURE_CLIENT_SECRET
BAD="$WORKDIR/bad-client-secret"
write_tree "$BAD"
cat >"$BAD/.github/workflows/bad.yml" <<'EOF'
name: bad
on: push
jobs:
  login:
    runs-on: ubuntu-latest
    env:
      AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
    steps:
      - run: echo no
EOF
expect_fail "$BAD" "AZURE_CLIENT_SECRET" "AZURE_CLIENT_SECRET key"

# AZURE_CREDENTIALS
BAD="$WORKDIR/bad-credentials"
write_tree "$BAD"
cat >"$BAD/.github/workflows/bad.yml" <<'EOF'
name: bad
on: push
jobs:
  login:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ secrets.AZURE_CREDENTIALS }}"
EOF
expect_fail "$BAD" "AZURE_CREDENTIALS" "AZURE_CREDENTIALS token"

# ARM_CLIENT_SECRET
BAD="$WORKDIR/bad-arm"
write_tree "$BAD"
cat >"$BAD/workflow-templates/bad.yml" <<'EOF'
name: bad
on: workflow_dispatch
jobs:
  login:
    runs-on: ubuntu-latest
    env:
      ARM_CLIENT_SECRET: x
    steps:
      - run: echo no
EOF
expect_fail "$BAD" "ARM_CLIENT_SECRET" "ARM_CLIENT_SECRET key"

# client-secret: input
BAD="$WORKDIR/bad-client-secret-key"
write_tree "$BAD"
cat >"$BAD/actions/sample/action.yml" <<'EOF'
name: bad
description: uses a client secret
runs:
  using: composite
  steps:
    - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906
      with:
        client-id: example-client-id
        tenant-id: example-tenant-id
        client-secret: example
EOF
expect_fail "$BAD" "client-secret" "client-secret key"

# creds: on azure/login
BAD="$WORKDIR/bad-creds"
write_tree "$BAD"
cat >"$BAD/.github/workflows/bad.yml" <<'EOF'
name: bad
on: push
jobs:
  login:
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906
        with:
          creds: ${{ secrets.AZURE_CREDS_JSON }}
EOF
expect_fail "$BAD" "creds" "azure/login creds input"

# This repository must pass.
got="$(run_policy "$ROOT" "$OUT")"
if [ "$got" -ne 0 ]; then
  echo "FAIL this repository should pass the Azure OIDC policy"
  cat "$OUT"
  exit 1
fi
echo "OK this repository passes"

echo "check-azure-oidc-policy: all cases passed"
