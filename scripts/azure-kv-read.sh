#!/usr/bin/env bash
# Read Key Vault secrets over an existing azure/login OIDC session.
# Masks values before export. Writes secret names (never values) to the job summary.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [ -z "${KEY_VAULT_NAME:-}" ]; then
  fail "KEY_VAULT_NAME is required when reading secrets."
fi
if [ -z "${AZURE_OIDC_SECRETS:-}" ]; then
  fail "secrets mapping is required when reading Key Vault (ENV_NAME=key-vault-secret-name, one per line)."
fi
if [ -z "${GITHUB_ENV:-}" ]; then
  fail "GITHUB_ENV is not set."
fi
if [ -z "${GITHUB_STEP_SUMMARY:-}" ]; then
  fail "GITHUB_STEP_SUMMARY is not set."
fi

validate_env_name() {
  local n="$1"
  if [[ ! "$n" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    fail "Invalid ENV_NAME '${n}'. Expected ^[A-Z][A-Z0-9_]*$."
  fi
}

validate_secret_name() {
  local n="$1"
  if [[ ! "$n" =~ ^[A-Za-z0-9-]{1,127}$ ]]; then
    fail "Invalid Key Vault secret name '${n}'. Expected ^[A-Za-z0-9-]{1,127}$."
  fi
}

# GitHub workflow-command data encoding (% first, then CR, then LF).
encode_workflow_data() {
  printf '%s' "$1" | python3 -c 'import sys; s=sys.stdin.read(); sys.stdout.write(s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A"))'
}

mask_secret() {
  local value="$1"
  local encoded line
  encoded="$(encode_workflow_data "$value")"
  if [ -n "$encoded" ]; then
    printf '::add-mask::%s\n' "$encoded"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ]; then
      encoded="$(encode_workflow_data "$line")"
      printf '::add-mask::%s\n' "$encoded"
    fi
  done <<< "$value"
}

export_env() {
  local name="$1"
  local value="$2"
  local delim i
  for i in 1 2 3 4 5; do
    delim="ghadelim_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    case "$value" in
      *"$delim"*) continue ;;
    esac
    {
      printf '%s<<%s\n' "$name" "$delim"
      printf '%s\n' "$value"
      printf '%s\n' "$delim"
    } >> "$GITHUB_ENV"
    return 0
  done
  fail "Failed to generate a unique heredoc delimiter for GITHUB_ENV."
}

env_names=()
secret_names=()

while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(trim "$raw")"
  if [ -z "$line" ]; then
    continue
  fi
  case "$line" in
    \#*) continue ;;
  esac
  if [[ "$line" != *=* ]]; then
    fail "Secret mapping must be ENV_NAME=key-vault-secret-name (one per line)."
  fi
  env_name="$(trim "${line%%=*}")"
  secret_name="$(trim "${line#*=}")"
  validate_env_name "$env_name"
  validate_secret_name "$secret_name"
  env_names+=("$env_name")
  secret_names+=("$secret_name")
done <<< "$AZURE_OIDC_SECRETS"

if [ "${#env_names[@]}" -eq 0 ]; then
  fail "secrets mapping is empty."
fi

for i in "${!env_names[@]}"; do
  env_name="${env_names[$i]}"
  secret_name="${secret_names[$i]}"
  set +e
  json_out="$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret_name" --query value -o json)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    fail "Failed to read Key Vault secret '${secret_name}' from vault '${KEY_VAULT_NAME}'."
  fi
  set +e
  value="$(printf '%s' "$json_out" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)); sys.stdout.write("x")')"
  decode_status=$?
  set -e
  if [ "$decode_status" -ne 0 ]; then
    fail "Failed to decode Key Vault secret '${secret_name}' from vault '${KEY_VAULT_NAME}'."
  fi
  value="${value%x}"
  mask_secret "$value"
  if [ -z "$value" ]; then
    fail "Key Vault secret '${secret_name}' in vault '${KEY_VAULT_NAME}' is empty."
  fi
  export_env "$env_name" "$value"
  echo "Read Key Vault secret name ${secret_name} from vault ${KEY_VAULT_NAME}."
done

{
  echo "## Azure Key Vault secrets"
  echo
  echo "| Vault | Secret name |"
  echo "| --- | --- |"
  for i in "${!secret_names[@]}"; do
    printf '| %s | %s |\n' "$KEY_VAULT_NAME" "${secret_names[$i]}"
  done
  echo
} >> "$GITHUB_STEP_SUMMARY"
