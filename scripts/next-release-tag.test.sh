#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/next-release-tag.sh"

run() {
  local tags="$1" labels="$2" commit_tags="$3"
  set +e
  TAGS="$tags" LABELS="$labels" COMMIT_TAGS="$commit_tags" \
    bash "$SCRIPT" >/tmp/next-release-out 2>/tmp/next-release-err
  local got=$?
  set -e
  printf '%s' "$got"
}

expect() {
  local want_code="$1" want_out="$2" tags="$3" labels="$4" commit_tags="$5" label="$6"
  local got
  got="$(run "$tags" "$labels" "$commit_tags")"
  if [ "$got" -ne "$want_code" ]; then
    echo "FAIL ${label}: expected exit ${want_code} got ${got}"
    echo "stdout: $(cat /tmp/next-release-out)"
    echo "stderr: $(cat /tmp/next-release-err)"
    exit 1
  fi
  local out
  out="$(cat /tmp/next-release-out)"
  if [ "$out" != "$want_out" ]; then
    echo "FAIL ${label}: expected stdout '${want_out}' got '${out}'"
    echo "stderr: $(cat /tmp/next-release-err)"
    exit 1
  fi
  echo "OK ${label}"
}

expect_fail_major() {
  local tags="$1" labels="$2" commit_tags="$3" label="$4"
  local got
  got="$(run "$tags" "$labels" "$commit_tags")"
  if [ "$got" -eq 0 ]; then
    echo "FAIL ${label}: expected non-zero exit"
    cat /tmp/next-release-out /tmp/next-release-err
    exit 1
  fi
  if ! grep -q "release:major" /tmp/next-release-err; then
    echo "FAIL ${label}: stderr should mention release:major"
    cat /tmp/next-release-err
    exit 1
  fi
  if ! grep -q "v2" /tmp/next-release-err; then
    echo "FAIL ${label}: stderr should mention v2"
    cat /tmp/next-release-err
    exit 1
  fi
  echo "OK ${label}"
}

# No tags -> v1.0.0
expect 0 "create v1.0.0" "" "" "" "no tags"

# Patch bump (default)
expect 0 "create v1.0.1" "v1.0.0" "" "" "patch from v1.0.0"
expect 0 "create v1.1.1" $'v1.0.9\nv1.1.0' "" "" "patch from latest minor"
expect 0 "create v1.0.11" $'v1.0.9\nv1.0.10' "" "" "semver sort patch 10 before 9"

# Minor label
expect 0 "create v1.1.0" "v1.0.0" "release:minor" "" "minor from v1.0.0"
expect 0 "create v1.3.0" "v1.2.3" "release:minor" "" "minor resets patch"
expect 0 "create v1.10.0" "v1.9.9" "release:minor" "" "minor 9 to 10"
expect 0 "create v1.0.0" "" "release:minor" "" "minor with no tags still starts at v1.0.0"

# Major label rejected (even with no tags, even with minor)
expect_fail_major "" "release:major" "" "major with no tags"
expect_fail_major "v1.0.0" "release:major" "" "major with existing tag"
expect_fail_major "v1.0.0" "release:minor release:major" "" "major wins over minor"

# Commit already tagged
expect 0 "skip v1.0.0" "v1.0.0" "" "v1.0.0" "commit already tagged"
expect 0 "skip v1.2.3" $'v1.2.3\nv1.2.2' "release:minor" $'v1\nv1.2.3' "already tagged ignores minor label"
expect 0 "create v1.0.1" "v1.0.0" "" "v1" "floating v1 alone is not a version tag"

# Pre-release and odd tags ignored
expect 0 "create v1.0.0" $'v1\nv1.0\nv1.0.0-rc.1\nv1.0.0-alpha.1\nv2.0.0\nv10.0.0\nfoo\nv1.0.0.1\nV1.0.0' "" "" "pre-release and odd tags ignored"
expect 0 "create v1.0.1" $'v1.0.0\nv1.0.1-rc.1\nv1' "" "" "pre-release does not hide real latest"
expect 0 "create v1.0.1" $'refs/tags/v1.0.0\nrefs/tags/v1' "" "" "refs/tags prefix stripped"

# Comma-separated labels
expect 0 "create v1.1.0" "v1.0.0" "bug,release:minor,docs" "" "comma-separated labels"

echo "next-release-tag: all cases passed"
