#!/usr/bin/env bash
# One az appconfig kv list per prefix. --endpoint + --auth-mode login only.
# Never a store-name ARM lookup, never resolve Key Vault, never credential list.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

if [ -z "${APP_CONFIG_ENDPOINT:-}" ]; then
  fail "APP_CONFIG_ENDPOINT is required."
fi
if [ -z "${APP_CONFIG_LABEL:-}" ]; then
  fail "APP_CONFIG_LABEL is required."
fi
if [ -z "${APP_CONFIG_KEY_PREFIXES:-}" ]; then
  fail "APP_CONFIG_KEY_PREFIXES is required."
fi

case "${APP_CONFIG_ENDPOINT}" in
  https://*) ;;
  *)
    fail "APP_CONFIG_ENDPOINT must be an https data-plane URL (--endpoint), not a store name."
    ;;
esac

az config set extension.use_dynamic_install=yes_without_prompt >/dev/null

workdir="${RUNNER_TEMP:-}"
if [ -z "$workdir" ]; then
  workdir="$(mktemp -d)"
fi
files=()
i=0

# shellcheck disable=SC2086
IFS=',' read -r -a prefixes <<< "${APP_CONFIG_KEY_PREFIXES}"
for raw in "${prefixes[@]}"; do
  prefix="${raw#"${raw%%[![:space:]]*}"}"
  prefix="${prefix%"${prefix##*[![:space:]]}"}"
  if [ -z "$prefix" ]; then
    continue
  fi
  if [[ ! "$prefix" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    fail "Invalid key prefix '${prefix}'."
  fi
  i=$((i + 1))
  f="${workdir}/appconfig-${i}.json"
  az appconfig kv list \
    --endpoint "${APP_CONFIG_ENDPOINT}" \
    --auth-mode login \
    --key "${prefix}*" \
    --label "\0,${APP_CONFIG_LABEL}" \
    --resolve-keyvault false \
    --all \
    --output json \
    >"$f"
  files+=("$f")
done

if [ "${#files[@]}" -eq 0 ]; then
  fail "APP_CONFIG_KEY_PREFIXES is empty."
fi

python3 - "${files[@]}" <<'PY'
import json
import sys

items = []
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        chunk = json.load(handle)
    if not isinstance(chunk, list):
        raise SystemExit(f"az appconfig kv list must return a JSON array: {path}")
    items.extend(chunk)
json.dump(items, sys.stdout)
PY
