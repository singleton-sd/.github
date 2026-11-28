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
output=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --vault-name|--query)
      shift 2
      ;;
    -o|--output)
      output="$2"
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
if [ "$output" != "json" ]; then
  echo "az stub expected -o json" >&2
  exit 2
fi
file="${FAKE_AZ_STORE:?}/${name}"
if [ ! -e "$file" ]; then
  echo "secret ${name} not in stub store" >&2
  exit 1
fi
python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' <"$file"
EOF
chmod +x "$FAKE_BIN/az"

PATH="$FAKE_BIN:$PATH"
export FAKE_AZ_STORE="$SECRET_STORE"

SECRET_VALUE="leaked-kv-value-42"
MULTILINE_VALUE=$'line-one-secret\nline-two-secret'
PERCENT_VALUE='100%secret'
ONE_LF_VALUE=$'password\n'
SEVERAL_LF_VALUE=$'password\n\n'
NO_LF_VALUE='password'

run_read() {
  local outfile="$1"
  shift
  set +e
  "$@" bash "$SCRIPT" >"$outfile" 2>&1
  local got=$?
  set -e
  printf '%s' "$got"
}

assert_no_plaintext() {
  local file="$1"
  shift
  local needle
  for needle in "$@"; do
    if grep -v '^::add-mask::' "$file" | grep -F -q -- "$needle"; then
      echo "FAIL: plaintext secret outside mask directives"
      cat "$file"
      exit 1
    fi
  done
}

github_env_value() {
  local file="$1" name="$2"
  python3 - "$file" "$name" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2].encode()
lines = path.read_bytes().split(b"\n")
prefix = name + b"<<"
i = 0
while i < len(lines):
    if lines[i].startswith(prefix):
        delim = lines[i][len(prefix) :]
        i += 1
        body = []
        while i < len(lines):
            if lines[i] == delim:
                sys.stdout.buffer.write(b"\n".join(body))
                raise SystemExit(0)
            body.append(lines[i])
            i += 1
        raise SystemExit(f"unterminated heredoc for {sys.argv[2]}")
    i += 1
raise SystemExit(f"{sys.argv[2]} not found in {path}")
PY
}

assert_exported_bytes() {
  local env_file="$1" name="$2" expected="$3" label="$4"
  local expected_file got_file
  expected_file="$(mktemp "$WORKDIR/expected.XXXXXX")"
  got_file="$(mktemp "$WORKDIR/got.XXXXXX")"
  printf '%s' "$expected" >"$expected_file"
  github_env_value "$env_file" "$name" >"$got_file"
  if ! cmp -s "$expected_file" "$got_file"; then
    echo "FAIL ${label}: exported bytes do not match"
    python3 -c 'import sys; from pathlib import Path; print(repr(Path(sys.argv[1]).read_bytes())); print(repr(Path(sys.argv[2]).read_bytes()))' "$expected_file" "$got_file"
    exit 1
  fi
}

printf '%s' "$SECRET_VALUE" >"$SECRET_STORE/app-connection-string"
printf '%s' "$MULTILINE_VALUE" >"$SECRET_STORE/multi-line-secret"
printf '%s' "$PERCENT_VALUE" >"$SECRET_STORE/percent-secret"
printf '%s' "$ONE_LF_VALUE" >"$SECRET_STORE/one-lf-secret"
printf '%s' "$SEVERAL_LF_VALUE" >"$SECRET_STORE/several-lf-secret"
printf '%s' "$NO_LF_VALUE" >"$SECRET_STORE/no-lf-secret"
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
assert_no_plaintext "$OUT" "$SECRET_VALUE"
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
assert_exported_bytes "$ENV_FILE" APP_CONNECTION_STRING "$SECRET_VALUE" "happy path"
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

# Multiline: encoded full value plus each line; no plaintext outside mask directives.
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
grep -F -q -- '::add-mask::line-one-secret%0Aline-two-secret' "$OUT" || {
  echo "FAIL: missing encoded multiline add-mask command"
  cat "$OUT"
  exit 1
}
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
assert_no_plaintext "$OUT" "line-one-secret" "line-two-secret"
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
assert_exported_bytes "$ENV_FILE" MULTI_SECRET "$MULTILINE_VALUE" "multiline"
echo "OK multiline masks each line and lists names only"

# Percent encoding in add-mask.
: >"$ENV_FILE"
: >"$SUMMARY_FILE"
got="$(
  GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
    KEY_VAULT_NAME="example-vault" \
    AZURE_OIDC_SECRETS="PERCENT_SECRET=percent-secret" \
    run_read "$OUT"
)"
if [ "$got" -ne 0 ]; then
  echo "FAIL percent exit $got"
  cat "$OUT"
  exit 1
fi
grep -F -q -- '::add-mask::100%25secret' "$OUT" || {
  echo "FAIL: expected percent-encoded add-mask"
  cat "$OUT"
  exit 1
}
assert_no_plaintext "$OUT" "$PERCENT_VALUE"
assert_exported_bytes "$ENV_FILE" PERCENT_SECRET "$PERCENT_VALUE" "percent"
echo "OK percent signs are encoded in add-mask"

# Trailing LF preservation: one LF, several LFs, and a no-trailing-LF control.
run_trailing() {
  local store_name="$1" env_name="$2" expected="$3" label="$4"
  : >"$ENV_FILE"
  : >"$SUMMARY_FILE"
  got="$(
    GITHUB_ENV="$ENV_FILE" GITHUB_STEP_SUMMARY="$SUMMARY_FILE" \
      KEY_VAULT_NAME="example-vault" \
      AZURE_OIDC_SECRETS="${env_name}=${store_name}" \
      run_read "$OUT"
  )"
  if [ "$got" -ne 0 ]; then
    echo "FAIL ${label} exit $got"
    cat "$OUT"
    exit 1
  fi
  assert_exported_bytes "$ENV_FILE" "$env_name" "$expected" "$label"
  echo "OK ${label}"
}

run_trailing one-lf-secret ONE_LF_SECRET "$ONE_LF_VALUE" "one trailing LF"
run_trailing several-lf-secret SEVERAL_LF_SECRET "$SEVERAL_LF_VALUE" "several trailing LFs"
run_trailing no-lf-secret NO_LF_SECRET "$NO_LF_VALUE" "no trailing LF"

echo "azure-kv-read: all cases passed"
