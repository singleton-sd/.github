#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/app-config-list.sh"
STUB="$ROOT/tests/fixtures/app-config/az-stub.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FAKE_BIN="$WORKDIR/bin"
mkdir -p "$FAKE_BIN"
cp "$STUB" "$FAKE_BIN/az"
chmod +x "$FAKE_BIN/az"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

export PATH="$FAKE_BIN:$PATH"
export APP_CONFIG_ENDPOINT="https://ssd-global-appcs-build-prod-ae.azconfig.io"
export APP_CONFIG_LABEL="leasemate-marketing"
export APP_CONFIG_KEY_PREFIXES="PUBLIC_,NEXT_PUBLIC_"
export APP_CONFIG_FIXTURE="$ROOT/tests/fixtures/app-config/happy-path.json"
export APP_CONFIG_AZ_LOG="$WORKDIR/az.log"
export RUNNER_TEMP="$WORKDIR/tmp"
mkdir -p "$RUNNER_TEMP"

# Command lines never use a store-name lookup, credential list, or resolve true.
if grep -E '^[^#]*--name' "$SCRIPT" >/dev/null; then
  fail "app-config-list.sh must not pass --name"
fi
if grep -E '^[^#]*credential list' "$SCRIPT" >/dev/null; then
  fail "app-config-list.sh must not call az appconfig credential list"
fi
if grep -E '^[^#]*--resolve-keyvault[ =]true' "$SCRIPT" >/dev/null; then
  fail "app-config-list.sh must not pass --resolve-keyvault true"
fi

out="$WORKDIR/out.json"
bash "$SCRIPT" >"$out"

python3 - "$out" "$APP_CONFIG_AZ_LOG" <<'PY'
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
log = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
if len(log) != 2:
    raise SystemExit(f"expected 2 az invocations, got {len(log)}: {log}")
if not any("key=PUBLIC_*" in line for line in log):
    raise SystemExit(f"missing PUBLIC_* list: {log}")
if not any("key=NEXT_PUBLIC_*" in line for line in log):
    raise SystemExit(f"missing NEXT_PUBLIC_* list: {log}")
for line in log:
    if "resolve=true" in line:
        raise SystemExit(f"resolve-keyvault true: {line}")
    if "resolve=false" not in line:
        raise SystemExit(f"expected resolve=false: {line}")
keys = sorted({item["key"] for item in items})
want = ["NEXT_PUBLIC_APP_URL", "PUBLIC_FOOTER", "PUBLIC_LEAD_INTAKE_ENABLED", "PUBLIC_SITE_NAME"]
if keys != want:
    raise SystemExit(f"merged keys {keys} != {want}")
print("OK list merged", len(items), "items from", len(log), "az calls")
PY

# --name must be refused by the stub if a caller tries it.
if az appconfig kv list --name nope --auth-mode login --output json >/dev/null 2>"$WORKDIR/name.err"; then
  fail "az stub accepted --name"
fi
if ! grep -q 'refuses --name' "$WORKDIR/name.err"; then
  fail "az stub --name error missing"
fi

# credential list must be refused.
if az appconfig credential list >/dev/null 2>"$WORKDIR/cred.err"; then
  fail "az stub accepted credential list"
fi
if ! grep -q 'credential list' "$WORKDIR/cred.err"; then
  fail "az stub credential error missing"
fi

# Non-https endpoint is rejected by the script (no ARM --name lookup).
set +e
APP_CONFIG_ENDPOINT="ssd-global-appcs-build-prod-ae" bash "$SCRIPT" >/dev/null 2>"$WORKDIR/endpoint.err"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  fail "store name endpoint unexpectedly passed"
fi
if ! grep -q 'https data-plane URL' "$WORKDIR/endpoint.err"; then
  fail "missing endpoint error"
fi

# Newlines in key_prefixes must not drop later prefixes.
export APP_CONFIG_AZ_LOG="$WORKDIR/az-multiline.log"
export APP_CONFIG_KEY_PREFIXES=$'PUBLIC_,\nNEXT_PUBLIC_'
bash "$SCRIPT" >"$WORKDIR/multiline.json"
python3 - "$WORKDIR/multiline.json" "$APP_CONFIG_AZ_LOG" <<'PY'
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
log = Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
if len(log) != 2:
    raise SystemExit(f"newline prefixes: expected 2 az invocations, got {len(log)}: {log}")
if not any("key=PUBLIC_*" in line for line in log):
    raise SystemExit(f"newline prefixes missing PUBLIC_*: {log}")
if not any("key=NEXT_PUBLIC_*" in line for line in log):
    raise SystemExit(f"newline prefixes missing NEXT_PUBLIC_*: {log}")
keys = sorted({item["key"] for item in items})
want = ["NEXT_PUBLIC_APP_URL", "PUBLIC_FOOTER", "PUBLIC_LEAD_INTAKE_ENABLED", "PUBLIC_SITE_NAME"]
if keys != want:
    raise SystemExit(f"newline prefixes merged keys {keys} != {want}")
print("OK newline prefixes listed both PUBLIC_ and NEXT_PUBLIC_")
PY
export APP_CONFIG_KEY_PREFIXES="PUBLIC_,NEXT_PUBLIC_"
export APP_CONFIG_AZ_LOG="$WORKDIR/az.log"

echo "OK app-config-list tests"
