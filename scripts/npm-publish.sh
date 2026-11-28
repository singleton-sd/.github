#!/usr/bin/env bash
# Pack one tarball and npm publish with provenance (npmjs only), idempotency,
# and --ignore-scripts. The caller builds before invoking this action.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

set_output() {
  local key="$1" value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

ACCESS="${ACCESS:-public}"
TAG="${TAG:-latest}"
DRY_RUN="${DRY_RUN:-false}"
REGISTRY_CHECK="${REGISTRY_CHECK:-true}"

case "$ACCESS" in
  public|restricted) ;;
  *) fail "access must be public or restricted. Got: ${ACCESS}" ;;
esac
if [ -z "$TAG" ]; then
  fail "tag must be a non-empty dist-tag."
fi
case "$DRY_RUN" in
  true|false) ;;
  *) fail "dry_run must be true or false. Got: ${DRY_RUN}" ;;
esac
case "$REGISTRY_CHECK" in
  true|false) ;;
  *) fail "registry_check must be true or false. Got: ${REGISTRY_CHECK}" ;;
esac

if [ -z "${NAME:-}" ] || [ -z "${VERSION:-}" ] || [ -z "${PACKAGE_DIR_RESOLVED:-}" ]; then
  fail "NAME, VERSION, and PACKAGE_DIR_RESOLVED must be set (run npm-publish-guard.sh first)."
fi

name="$NAME"
version="$VERSION"
pkg_dir="$PACKAGE_DIR_RESOLVED"
tarball=""
integrity=""
published="false"
skip="false"
reason=""

# Trusted Publishing (npmjs) always uses these flags. Local registries cannot
# accept --provenance; the effective command may omit it.
trusted_args=(--provenance --access "$ACCESS" --tag "$TAG" --ignore-scripts)
echo "Trusted Publishing args: npm publish <tarball> ${trusted_args[*]}"

registry="$(npm config get registry)"
registry="${registry%/}"
use_provenance=1
case "$registry" in
  https://registry.npmjs.org|http://registry.npmjs.org)
    ;;
  *)
    use_provenance=0
    echo "Omitting --provenance: registry ${registry} is not registry.npmjs.org. npm rejects provenance on other hosts."
    ;;
esac

if [ "$REGISTRY_CHECK" = true ]; then
  set +e
  viewed="$(npm view "${name}@${version}" version --silent 2>/dev/null)"
  view_status=$?
  set -e
  if [ "$view_status" -eq 0 ] && [ -n "$viewed" ]; then
    skip="true"
    reason="skipped: already published"
    echo "$reason (${name}@${version})"
    set_output published "false"
    set_output version "$version"
    set_output tarball ""
    set_output skip "true"
    set_output name "$name"
    set_output integrity ""
    set_output reason "$reason"
    exit 0
  fi
fi

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

pack_json="${tmp}/pack.json"
(
  cd "$pkg_dir"
  npm pack --json --ignore-scripts --pack-destination "$tmp" >"$pack_json"
)

filename=""
set +e
filename="$(python3 - "$pack_json" <<'PY'
import json
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
data = json.loads(raw)
if isinstance(data, dict):
    items = [data]
elif isinstance(data, list):
    items = data
else:
    print("npm pack --json did not return an object or array", file=sys.stderr)
    sys.exit(2)
if len(items) != 1:
    print(f"npm pack --json listed {len(items)} tarball(s); expected exactly one", file=sys.stderr)
    sys.exit(2)
item = items[0]
if not isinstance(item, dict):
    print("npm pack --json entry is not an object", file=sys.stderr)
    sys.exit(2)
name = item.get("filename")
if not isinstance(name, str) or not name:
    print("npm pack --json entry is missing filename", file=sys.stderr)
    sys.exit(2)
print(name)
PY
)"
pack_status=$?
set -e
if [ "$pack_status" -ne 0 ]; then
  fail "npm pack did not produce exactly one tarball."
fi

tarball="${tmp}/${filename}"
if [ ! -f "$tarball" ]; then
  fail "packed tarball ${filename} was not written to ${tmp}."
fi

integrity="sha512-$(openssl dgst -sha512 -binary "$tarball" | openssl base64 -A)"
echo "Packed ${filename} (${integrity})"
echo "Tarball file list:"
tar -tzf "$tarball"

cmd=(npm publish "$tarball" --access "$ACCESS" --tag "$TAG" --ignore-scripts)
if [ "$use_provenance" -eq 1 ]; then
  cmd+=(--provenance)
fi
if [ "$DRY_RUN" = true ]; then
  cmd+=(--dry-run)
fi

printf 'Effective publish command:'
printf ' %q' "${cmd[@]}"
printf '\n'

"${cmd[@]}"

if [ "$DRY_RUN" = true ]; then
  published="false"
  reason="dry-run"
  echo "dry-run: tarball was not published"
else
  published="true"
  reason="published"
fi

set_output published "$published"
set_output version "$version"
set_output tarball "$filename"
set_output skip "$skip"
set_output name "$name"
set_output integrity "$integrity"
set_output reason "$reason"
