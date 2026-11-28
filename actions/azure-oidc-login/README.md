# Azure OIDC login

Shared composite action for GitHub OIDC login to Azure, with an optional Key
Vault read. **OIDC only, no client secret, log names never values.**

Callers that read Key Vault must use this action (or `azure/login` with the
same OIDC inputs). Do not set a client secret or pass `creds`. Ordinary CI
stays on `ubuntu-latest`; do not move it to the Oracle self-hosted runner for
this contract.

A live Azure login is not exercised in this repository (no federated
credential is configured here).

## Caller example

```yaml
jobs:
  read-vault:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Azure OIDC login
        uses: singleton-sd/.github/actions/azure-oidc-login@v1
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
          key-vault-name: ${{ vars.AZURE_KEY_VAULT_NAME }}
          secrets: |
            APP_CONNECTION_STRING=app-connection-string
```

`permissions.id-token: write` is required so GitHub can mint an OIDC token.
`key-vault-name` and `secrets` are both-or-neither: omit both to log in
without reading the vault.

## Inputs

| Input | Required | Type | Notes |
| --- | --- | --- | --- |
| `client-id` | yes | string | Entra application (client) ID. Not a secret. |
| `tenant-id` | yes | string | Entra tenant ID. Not a secret. |
| `subscription-id` | yes | string | Azure subscription ID. Not a secret. |
| `key-vault-name` | with `secrets` | string | Vault name. Omit both this and `secrets` to skip the read. |
| `secrets` | with `key-vault-name` | string | Multiline `ENV_NAME=key-vault-secret-name` mapping. |

`ENV_NAME` must match `^[A-Z][A-Z0-9_]*$`. Secret names must match
`^[A-Za-z0-9-]{1,127}$`. Values are masked (`::add-mask::`) before they are
exported to `GITHUB_ENV`.

## Job summary

The job summary lists **secret names only** (never values):

- a table of vault name and secret name for each mapping
- `github.workflow_ref`
- `github.sha`
- run id
- UTC time

If no secrets were requested, the summary says so and still records the
workflow ref, sha, run id, and UTC time.

## Vault and identity

The Entra app used as `client-id` needs a **federated credential** on the
GitHub repository/environment, and the identity needs the Azure role **Key
Vault Secrets User** on the vault. This action does not create those
resources. Do not put real vault names or directory IDs in this repository.
