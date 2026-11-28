# Security

[`actions/azure-oidc-login`](../actions/azure-oidc-login/README.md) logs in to
Azure with GitHub OIDC (`azure/login`) and optionally reads Key Vault secrets.
OIDC only: no client secret, log secret names never values. Ordinary CI stays
on `ubuntu-latest`, not the Oracle self-hosted runner.

Callers that read Key Vault must use this action. A live Azure login is not
exercised in this repository.

A shared `security-scan` workflow is not built until two callers exist.
