# Config

Shared reader for **public** Azure App Configuration build settings. Callers
pin `@v1`.

| Workflow or action | Role |
| --- | --- |
| [`actions/app-config-read`](../actions/app-config-read/README.md) | Composite: OIDC login, one `az appconfig kv list` per prefix, export to `GITHUB_ENV` |
| [`config-read.yml`](../.github/workflows/config-read.yml) | Thin `workflow_call` wrapper. Job outputs: `count`, `applied` (JSON). Checks out this repo at `job.workflow_sha` into `.github-workflows-src` because `./actions/...` resolves against the caller workspace. |

Store endpoint: `https://ssd-global-appcs-build-prod-ae.azconfig.io` (data
plane, `--endpoint` + `--auth-mode login`). Do not pass `--name`.

## Labels

- Unlabeled keys are the shared default.
- A label equal to the caller repository name is the repo override.
- Load unlabeled first, then the repo label; the repo value wins.

## Changing a value

A bot or human updates a key in the build store (Azure portal or an Azure MCP
connector). Pick **unlabeled** for every caller, or the **repository-name
label** for one site.

Then trigger a rebuild on the caller:

- `workflow_dispatch` on the production Pages workflow, or
- `repository_dispatch` if the caller exposes that event.

This repository does not watch the store. There is no Event Grid subscription
here.

## Key Vault references

Selected items with content type
`application/vnd.microsoft.appconfig.keyvaultref+json` fail the step. The key
is named; the value is never printed or resolved.

## Pages build

[`pages-build.yml`](../.github/workflows/pages-build.yml) stays
`contents: read` and keeps GitHub `vars.*` behaviour. GitHub validates
nested-job permissions at parse time, so that workflow cannot request
`id-token: write` without breaking existing callers. App Configuration
builds use [`pages-build-app-config.yml`](../.github/workflows/pages-build-app-config.yml)
(`id-token: write`). Non-empty `public_*` inputs win over store values.
