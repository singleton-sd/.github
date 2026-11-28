#!/usr/bin/env bash
# Offline az stub. Returns recorded App Configuration JSON. Never talks to Azure.
set -euo pipefail

if [ "${1:-}" = "config" ]; then
  exit 0
fi

if [ "${1:-}" = "appconfig" ] && [ "${2:-}" = "credential" ]; then
  echo "az stub refuses az appconfig credential list" >&2
  exit 2
fi

if [ "${1:-}" != "appconfig" ] || [ "${2:-}" != "kv" ] || [ "${3:-}" != "list" ]; then
  echo "unexpected az invocation: $*" >&2
  exit 2
fi
shift 3

endpoint=""
auth_mode=""
key=""
label=""
resolve=""
output=""
all=0

while [ $# -gt 0 ]; do
  case "$1" in
    --endpoint)
      endpoint="${2:-}"
      shift 2
      ;;
    --name)
      echo "az stub refuses --name (ARM lookup)" >&2
      exit 2
      ;;
    --auth-mode)
      auth_mode="${2:-}"
      shift 2
      ;;
    --key)
      key="${2:-}"
      shift 2
      ;;
    --label)
      label="${2:-}"
      shift 2
      ;;
    --resolve-keyvault)
      resolve="${2:-}"
      shift 2
      ;;
    --all)
      all=1
      shift
      ;;
    --output|-o)
      output="${2:-}"
      shift 2
      ;;
    *)
      echo "unexpected az flag: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$endpoint" ]; then
  echo "az stub missing --endpoint" >&2
  exit 2
fi
case "$endpoint" in
  https://*) ;;
  *)
    echo "az stub expected --endpoint https URL, got ${endpoint}" >&2
    exit 2
    ;;
esac
if [ "$auth_mode" != "login" ]; then
  echo "az stub expected --auth-mode login" >&2
  exit 2
fi
if [ "$resolve" = "true" ]; then
  echo "az stub refuses --resolve-keyvault true" >&2
  exit 2
fi
if [ -n "$resolve" ] && [ "$resolve" != "false" ]; then
  echo "az stub expected --resolve-keyvault false" >&2
  exit 2
fi
if [ "$output" != "json" ]; then
  echo "az stub expected --output json" >&2
  exit 2
fi
if [ "$all" -ne 1 ]; then
  echo "az stub expected --all" >&2
  exit 2
fi
if [ -z "${APP_CONFIG_FIXTURE:-}" ]; then
  echo "APP_CONFIG_FIXTURE is not set" >&2
  exit 2
fi

if [ -n "${APP_CONFIG_AZ_LOG:-}" ]; then
  printf '%s\n' "endpoint=${endpoint} key=${key} label=${label} resolve=${resolve:-omit}" >> "${APP_CONFIG_AZ_LOG}"
fi

python3 - "$APP_CONFIG_FIXTURE" "$key" "$label" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key_filter = sys.argv[2]
label_filter = sys.argv[3]
items = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(items, list):
    raise SystemExit("fixture must be a JSON array")

prefix = key_filter
if prefix.endswith("*"):
    prefix = prefix[:-1]

wanted_labels = set()
unlabeled = False
for part in label_filter.split(","):
    if part in ("\\0", "\0", ""):
        unlabeled = True
    else:
        wanted_labels.add(part)

selected = []
for item in items:
    if not isinstance(item, dict):
        continue
    key = str(item.get("key") or "")
    if prefix and not key.startswith(prefix):
        continue
    raw_label = item.get("label")
    label = "" if raw_label in (None, "") else str(raw_label)
    if label == "":
        if unlabeled:
            selected.append(item)
        continue
    if label in wanted_labels:
        selected.append(item)

json.dump(selected, sys.stdout)
PY
