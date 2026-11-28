# App Configuration read

Shared composite that reads **public, non-secret** build settings from the
Azure App Configuration build store into the caller's job (`GITHUB_ENV`).
Unlabeled keys load first; a label equal to the caller repository name wins.

Callers pin `@v1`. The composite runs **inside the caller's job**, so the
federated credential is on the caller repository. This repository does not
need one.

Use `--endpoint` (data plane). `--name` does an ARM lookup the GitHub identity
cannot complete.

## Caller example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Read App Configuration
        uses: singleton-sd/.github/actions/app-config-read@v1
```

`permissions.id-token: write` is required when `login` is true (the default)
so GitHub can mint an OIDC token.

## Inputs

| Input | Default | Notes |
| --- | --- | --- |
| `endpoint` | `https://ssd-global-appcs-build-prod-ae.azconfig.io` | Data-plane URL. Do not pass a store name. |
| `label` | caller repo name | Repo-specific override label |
| `key_prefixes` | `PUBLIC_,NEXT_PUBLIC_` | Comma-separated prefixes |
| `client_id` | `4764ad98-0805-485d-8167-123cb7e90f63` | Entra app `ssd-appconfig-gha-oidc-prod`. Not a secret. |
| `tenant_id` | `9a0e57d7-e58e-4e8b-814d-037cd7d9015c` | Not a secret. |
| `subscription_id` | `01c0bb8b-3770-4765-979a-cb13ae7e3dd2` | Not a secret. |
| `login` | `true` | Set `false` when the caller already signed in |

## Outputs

| Output | Notes |
| --- | --- |
| `count` | Number of keys written to `GITHUB_ENV` |
| `applied` | JSON object of those keys and values |

Selected keys are also exported to `$GITHUB_ENV` for later steps in the same
job. One `az appconfig kv list` runs per prefix. Key Vault references
(`application/vnd.microsoft.appconfig.keyvaultref+json`) fail the step, name
the key, and never print the value.

## Audit trail

Every selected key is written to the job summary and the job log (key, label
or `(none)`, value, etag, last-modified). Allowed only because these prefixes
are public.

Local `uses: ./actions/...` inside a composite still resolves against the
**caller** workspace. Nested login is therefore SHA-pinned
`singleton-sd/.github/actions/azure-oidc-login@<sha>`. Reusable workflows that
call this composite check out this repository at `job.workflow_sha` into
`.github-workflows-src` and use `./.github-workflows-src/actions/app-config-read`.

## Same-job Pages builds

[`pages-build-app-config.yml`](../../.github/workflows/pages-build-app-config.yml)
calls this composite (callers grant `id-token: write`). `pages-build.yml`
does not: GitHub validates nested-job permissions at parse time, so adding
`id-token: write` there would break existing `contents: read` callers.
Non-empty `public_*` workflow inputs win over App Configuration. The reusable
[`config-read.yml`](../../.github/workflows/config-read.yml) wrapper exposes
`count` and `applied` as **job** outputs for a separate job.
