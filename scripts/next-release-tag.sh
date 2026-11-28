#!/usr/bin/env bash
# Compute the next annotated v1.x.y tag for this repository.
# Env:
#   TAGS          newline-separated existing tag names (refs/tags/ prefix ok)
#   LABELS        space/newline/comma-separated PR labels
#   COMMIT_TAGS   newline-separated tags already pointing at this commit
# Stdout: "create v1.x.y" or "skip v1.x.y"
# Exit 0 on create/skip; exit 1 if release:major is present (v2 is out of scope).
set -euo pipefail

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_v1_version() {
  [[ "$1" =~ ^v1\.[0-9]+\.[0-9]+$ ]]
}

collect_tags() {
  local raw="$1" line trimmed
  TAG_LIST=()
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="$(trim "$line")"
    trimmed="${trimmed#refs/tags/}"
    [ -z "$trimmed" ] && continue
    TAG_LIST+=("$trimmed")
  done <<EOF
$raw
EOF
}

TAG_LIST=()
collect_tags "${TAGS:-}"
EXISTING_TAGS=("${TAG_LIST[@]}")

TAG_LIST=()
collect_tags "${COMMIT_TAGS:-}"
ON_COMMIT=("${TAG_LIST[@]}")

for tag in "${ON_COMMIT[@]+"${ON_COMMIT[@]}"}"; do
  if is_v1_version "$tag"; then
    printf 'skip %s\n' "$tag"
    exit 0
  fi
done

has_major=0
has_minor=0
labels_raw="${LABELS:-}"
labels_raw="${labels_raw//,/ }"
# shellcheck disable=SC2086
set -- $labels_raw
for label in "$@"; do
  case "$label" in
    release:major) has_major=1 ;;
    release:minor) has_minor=1 ;;
  esac
done

if [ "$has_major" -eq 1 ]; then
  echo "::error::release:major is out of scope because a major bump starts a v2 line." >&2
  echo "reject major" >&2
  exit 1
fi

version_tags=()
for tag in "${EXISTING_TAGS[@]+"${EXISTING_TAGS[@]}"}"; do
  if is_v1_version "$tag"; then
    version_tags+=("$tag")
  fi
done

if [ "${#version_tags[@]}" -eq 0 ]; then
  printf 'create %s\n' "v1.0.0"
  exit 0
fi

latest="$(printf '%s\n' "${version_tags[@]}" | sort -V | tail -n1)"
ver="${latest#v}"
IFS=. read -r major minor patch <<<"$ver"
if [ "$has_minor" -eq 1 ]; then
  minor=$((10#$minor + 1))
  patch=0
else
  patch=$((10#$patch + 1))
fi
printf 'create v%s.%s.%s\n' "$major" "$minor" "$patch"
