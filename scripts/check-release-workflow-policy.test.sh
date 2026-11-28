#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-release-workflow-policy.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

run_policy() {
  local tree="$1" workflow="$2" outfile="$3"
  set +e
  bash "$SCRIPT" "$tree" "$workflow" >"$outfile" 2>&1
  local got=$?
  set -e
  printf '%s' "$got"
}

expect_fail() {
  local tree="$1" workflow="$2" needle="$3" label="$4"
  local got
  got="$(run_policy "$tree" "$workflow" "$OUT")"
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

OUT="$WORKDIR/out.txt"
PINNED="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"

GOOD="$WORKDIR/good"
mkdir -p "$GOOD/.github/workflows"
cat >"$GOOD/.github/workflows/release.yml" <<EOF
name: release
on:
  workflow_run:
    workflows: [self-ci]
    types: [completed]
    branches: [main]
  workflow_dispatch:
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: ${PINNED}
EOF
got="$(run_policy "$GOOD" "$GOOD/.github/workflows/release.yml" "$OUT")"
if [ "$got" -ne 0 ]; then
  echo "FAIL good release workflow should pass"
  cat "$OUT"
  exit 1
fi
echo "OK good release workflow passes"

BAD="$WORKDIR/bad-pr"
mkdir -p "$BAD/.github/workflows"
cat >"$BAD/.github/workflows/release.yml" <<EOF
name: release
on:
  workflow_run:
    workflows: [self-ci]
    types: [completed]
    branches: [main]
  pull_request:
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: ${PINNED}
EOF
expect_fail "$BAD" "$BAD/.github/workflows/release.yml" "pull_request" "pull_request trigger"

BAD="$WORKDIR/bad-pr-target"
mkdir -p "$BAD/.github/workflows"
cat >"$BAD/.github/workflows/release.yml" <<EOF
name: release
on: [workflow_dispatch, pull_request_target]
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: ${PINNED}
EOF
expect_fail "$BAD" "$BAD/.github/workflows/release.yml" "pull_request_target" "pull_request_target trigger"

BAD="$WORKDIR/bad-unpinned"
mkdir -p "$BAD/.github/workflows"
cat >"$BAD/.github/workflows/release.yml" <<EOF
name: release
on:
  workflow_dispatch:
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
expect_fail "$BAD" "$BAD/.github/workflows/release.yml" "unpinned uses" "unpinned uses: @v4"

BAD="$WORKDIR/bad-v1"
mkdir -p "$BAD/.github/workflows"
cat >"$BAD/.github/workflows/release.yml" <<EOF
name: release
on:
  workflow_dispatch:
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/create-github-app-token@v3.3.0
EOF
expect_fail "$BAD" "$BAD/.github/workflows/release.yml" "unpinned uses" "unpinned uses: @v3.3.0"

got="$(run_policy "$ROOT" "$ROOT/.github/workflows/self-release.yml" "$OUT")"
if [ "$got" -ne 0 ]; then
  echo "FAIL this repository's self-release.yml should pass"
  cat "$OUT"
  exit 1
fi
echo "OK this repository passes"

default_out="$WORKDIR/default.txt"
set +e
bash "$SCRIPT" "$ROOT" >"$default_out" 2>&1
default_got=$?
set -e
if [ "$default_got" -ne 0 ]; then
  echo "FAIL default path should lint self-release.yml"
  cat "$default_out"
  exit 1
fi
echo "OK default path is self-release.yml"

echo "check-release-workflow-policy: all cases passed"
