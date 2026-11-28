#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/azure-kv-read.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FAKE_BIN="$WORKDIR/bin"
mkdir -p "$FAKE_BIN"
SECRET_STORE="$WORKDIR/az-secrets"
mkdir -p "$SECRET_STORE"

cat >"$FAKE_BIN/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "keyvault" ] || [ "${2:-}" != "secret" ] || [ "${3:-}" != "show" ]; then
  echo "unexpected az invocation: $*" >&2
  exit 2
fi
shift 3
name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --vault-name|--query|-o)
      shift 2
      ;;
    *)
      echo "unexpected az flag: $1" >&2
      exit 2
      ;;
  esac
done
if [ -z "$name" ]; then
  echo "az stub missing --name" >&2
  exit 2
fi
file="${FAKE_AZ_STORE:?}/${name}"
if [ ! -e "$file" ]; then
  echo "secret ${name} not in stub store" >&2
  exit 1
fi
cat "$file"
EOF
chmod +x "$FAKE_BIN/az"

PATH="$FAKE_BIN:$PATH"
export FAKE_AZ_STORE="$SECRET_STORE"

SECRET_VALUE="leaked-kv-value-42"
MULTILINE_VALUE=$'line-one-secret\nline-two-secret'

run_read() {
  local outfile="$1"
  shift
  set +e
  "$@" bash "$SCRIPT" >"$outfile" 2>&1
  local got=$?
  set -e
  printf '%s' "$got"
}

printf '%s' "$SECRET_VALUE" >"$SECRET_STORE/app-connection-string"
printf '%s' "$MULTILINE_VALUE" >"$SECRET_STORE/multi-line-secret"
: >"$SECRET_STORE/empty-secret"

# Happy path: mask before export, names in summary, value not in stdout/summary.
ENV_FILE="$WORKDIR/github.env"
SUMMARY_FILE="$WORKDIR/summary.md"
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
OUT="$WORKDIR/out.txt"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="APP_CONNECTION_STRING=app-connection-string" \
    run_read "$OUT"
)"
if [ "$got" -ne 0 ]; then
  echo "FAIL happy path exit $got"
  cat "$OUT"
  exit 1
fi
grep -F -q -- "::add-mask::${SECRET_VALUE}" "$OUT" || {
  echo "FAIL: expected ::add-mask:: before export"
  cat "$OUT"
  exit 1
}
# Value may appear in stdout only as a mask directive, not elsewhere.
if grep -v '::add-mask::' "$OUT" | grep -F -q -- "$SECRET_VALUE"; then
  echo "FAIL: secret value printed outside ::add-mask::"
  cat "$OUT"
  exit 1
fi
grep -F -q -- "$SECRET_VALUE" "$SUMMARY_FILE" && {
  echo "FAIL: secret value in summary"
  cat "$SUMMARY_FILE"
  exit 1
}
grep -F -q "app-connection-string" "$SUMMARY_FILE" || {
  echo "FAIL: summary missing secret name"
  cat "$SUMMARY_FILE"
  exit 1
}
grep -F -q "example-vault" "$SUMMARY_FILE" || {
  echo "FAIL: summary missing vault name"
  cat "$SUMMARY_FILE"
  exit 1
}
grep -F -q "APP_CONNECTION_STRING<<ghadelim_" "$ENV_FILE" || {
  echo "FAIL: GITHUB_ENV missing heredoc export"
  cat "$ENV_FILE"
  exit 1
}
grep -F -q -- "$SECRET_VALUE" "$ENV_FILE" || {
  echo "FAIL: GITHUB_ENV missing exported value"
  cat "$ENV_FILE"
  exit 1
}
echo "OK happy path masks, exports, and lists names only"

# Mask is emitted even when export cannot proceed (GITHUB_ENV is a directory).
MASK_ONLY_ENV="$WORKDIR/env-is-dir"
mkdir -p "$MASK_ONLY_ENV"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$MASK_ONLY_ENV" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="APP_CONNECTION_STRING=app-connection-string" \
    run_read "$OUT"
)"
if [ "$got" -eq 0 ]; then
  echo "FAIL: expected non-zero when GITHUB_ENV is a directory"
  cat "$OUT"
  exit 1
fi
grep -F -q -- "::add-mask::${SECRET_VALUE}" "$OUT" || {
  echo "FAIL: mask was not emitted before export"
  cat "$OUT"
  exit 1
}
echo "OK mask emitted before export"

# Empty value fails; nothing useful to leak.
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="EMPTY_SECRET=empty-secret" \
    run_read "$OUT"
)"
if [ "$got" -ne 1 ]; then
  echo "FAIL empty value expected exit 1 got $got"
  cat "$OUT"
  exit 1
fi
grep -q "empty" "$OUT" || {
  echo "FAIL: expected empty-secret error"
  cat "$OUT"
  exit 1
}
if [ -s "$ENV_FILE" ]; then
  echo "FAIL: empty value must not be exported"
  cat "$ENV_FILE"
  exit 1
fi
echo "OK empty value fails"

# Bad ENV_NAME
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="not-valid=app-connection-string" \
    run_read "$OUT"
)"
if [ "$got" -ne 1 ]; then
  echo "FAIL bad ENV_NAME expected exit 1 got $got"
  cat "$OUT"
  exit 1
fi
grep -q "ENV_NAME" "$OUT" || {
  echo "FAIL: expected ENV_NAME validation error"
  cat "$OUT"
  exit 1
}
if [ -s "$ENV_FILE" ]; then
  echo "FAIL: bad ENV_NAME must not export"
  cat "$ENV_FILE"
  exit 1
fi
echo "OK rejects bad ENV_NAME"

# Bad secret name
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="APP_CONNECTION_STRING=bad_secret_name" \
    run_read "$OUT"
)"
if [ "$got" -ne 1 ]; then
  echo "FAIL bad secret name expected exit 1 got $got"
  cat "$OUT"
  exit 1
fi
grep -q "secret name" "$OUT" || {
  echo "FAIL: expected secret name validation error"
  cat "$OUT"
  exit 1
}
echo "OK rejects bad secret name"

# Multiline: each line masked; values not in summary; names listed.
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="MULTI_SECRET=multi-line-secret" \
    run_read "$OUT"
)"
if [ "$got" -ne 0 ]; then
  echo "FAIL multiline exit $got"
  cat "$OUT"
  exit 1
fi
grep -F -q -- "::add-mask::line-one-secret" "$OUT" || {
  echo "FAIL: missing mask for multiline first line"
  cat "$OUT"
  exit 1
}
grep -F -q -- "::add-mask::line-two-secret" "$OUT" || {
  echo "FAIL: missing mask for multiline second line"
  cat "$OUT"
  exit 1
}
if grep -F -q -- "line-one-secret" "$SUMMARY_FILE" || grep -F -q -- "line-two-secret" "$SUMMARY_FILE"; then
  echo "FAIL: multiline value in summary"
  cat "$SUMMARY_FILE"
  exit 1
fi
grep -F -q "multi-line-secret" "$SUMMARY_FILE" || {
  echo "FAIL: summary missing multiline secret name"
  cat "$SUMMARY_FILE"
  exit 1
}
echo "OK multiline masks each line and lists names only"

echo "azure-kv-read: all cases passed"
