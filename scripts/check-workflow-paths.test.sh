#!/usr/bin/env bash
# Static regression for working_directory path joins in reusable workflows.
# Nested example: working_directory=apps/site dist_path=out -> apps/site/out
# Needles are literal GitHub expressions, not expansions.
# shellcheck disable=SC2016
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.github/workflows/pages-build.yml"
DEPLOY="$ROOT/.github/workflows/pages-deploy.yml"
JOINED='${{ inputs.working_directory }}/${{ inputs.dist_path }}'
PKG='${{ inputs.working_directory }}/package.json'
LOCK='${{ inputs.working_directory }}/pnpm-lock.yaml'
WORKDIR='working-directory: ${{ inputs.working_directory }}'

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

need() {
  local file="$1" needle="$2" label="$3"
  grep -F -q -- "$needle" "$file" || fail "$label: missing $needle in ${file#"$ROOT"/}"
}

count_need() {
  local file="$1" needle="$2" want="$3" label="$4"
  local got
  got="$(grep -F -c -- "$needle" "$file" || true)"
  if [ "$got" -lt "$want" ]; then
    fail "$label: expected at least ${want} occurrence(s) of ${needle} in ${file#"$ROOT"/}, got ${got}"
  fi
}

need "$BUILD" "$WORKDIR" "pages-build run working-directory"
need "$BUILD" "$PKG" "pages-build pnpm package_json_file (nested package with no root package.json)"
need "$BUILD" "$LOCK" "pages-build pnpm cache-dependency-path"
need "$BUILD" "$JOINED" "pages-build artifact path"

need "$DEPLOY" "path: ${JOINED}" "pages-deploy download path"
need "$DEPLOY" "DIST_PATH: ${JOINED}" "pages-deploy .nojekyll DIST_PATH"
need "$DEPLOY" "folder: ${JOINED}" "pages-deploy production folder"
count_need "$DEPLOY" "source-dir: ${JOINED}" 2 "pages-deploy preview source-dir (deploy + retry)"

# Default working_directory remains "." so JOINED is ./dist at the root.
need "$BUILD" 'default: "."' "pages-build working_directory default"
need "$DEPLOY" 'default: "."' "pages-deploy working_directory default"

echo "check-workflow-paths: nested and default working_directory joins are present"
