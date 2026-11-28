# .github

Shared GitHub Actions workflows and org workflow templates for Singleton SD
marketing sites (Pages build, deploy, and live smoke checks).

Naming follows ADR-011 (Singleton SD reusable workflow naming).

Callers **must pin `@v1` or an immutable `@v1.x.y`**, never `@main`. Do not follow a branch.
`v1` is the current major.

This repository stores **no secrets**. Callers pass secrets through the
`secrets:` map on `workflow_call`. Public build settings are read from the
**caller's** GitHub repository variables (`vars.*`).

Contract: [`docs/contract.md`](docs/contract.md). Versioning:
[`docs/versioning.md`](docs/versioning.md).

## Pinning

```yaml
jobs:
  build:
    uses: singleton-sd/.github/.github/workflows/pages-build.yml@v1
    permissions:
      contents: read
```

The double `.github` is required: `{owner}/{repo}/.github/workflows/{file}@{ref}`.

| Pin | Meaning |
| --- | --- |
| `@v1` | Floating annotated tag. A successful release moves it, so callers get fixes without changing the pin. |
| `@v1.x.y` | Immutable annotated tag. Pin this to freeze a known workflow revision. |

Releases are cut by [`.github/workflows/self-release.yml`](.github/workflows/self-release.yml) after `self-ci` and `self-test` pass on that `main` commit. The job writes an annotated `v1.x.y` tag first, then force-updates only `refs/tags/v1` with the singleton-release App token (`vars.RELEASE_APP_ID` or `secrets.RELEASE_APP_ID`, plus `secrets.RELEASE_APP_PRIVATE_KEY`). Patch bumps by default; add a `release:minor` label on the merged PR for a minor bump. A `release:major` label fails the job (a v2 line is out of scope). If the commit already has a `v1.x.y` tag, the version tag is left alone and `v1` is pointed at it when checks passed. The first release on a repo with no `v1.x.y` tags is `v1.0.0`. Manual fallback: dispatch **self-release** on `main` (optional SHA; still requires green checks).

## Index

| Area | Workflow or action | Purpose | Caller permissions | Secrets | Status | Known callers |
| --- | --- | --- | --- | --- | --- | --- |
| pages | [`pages-build.yml`](.github/workflows/pages-build.yml) | Install, format, lint, test, Turnstile check, build, SEO/a11y, write `dist/.nojekyll`, upload artifact | `contents: read` | none | active | org starters `pages-production.yml`, `pages-preview.yml` |
| pages | [`pages-deploy.yml`](.github/workflows/pages-deploy.yml) | Download artifact, rewrite `.nojekyll`, mint singleton-release App token, deploy production or preview (`dry_run` skips the push) | `contents: read`, `actions: read` | `RELEASE_APP_PRIVATE_KEY` (not required when `dry_run: true`) | active | org starters `pages-production.yml`, `pages-preview.yml` |
| pages | [`pages-smoke.yml`](.github/workflows/pages-smoke.yml) | Live Pages smoke: HTTP 200, title/root needle, CSS/JS content-types | `contents: read` | none | active | org starters `pages-production.yml`, `pages-preview.yml` |
| self | [`self-ci.yml`](.github/workflows/self-ci.yml) | Required check `self-ci`: actionlint, shellcheck, policy tests, contract lint, zizmor | n/a (this repo) | none | active | this repository |
| self | [`self-test.yml`](.github/workflows/self-test.yml) | Required check `self-test`: local Pages fixture build, deploy `dry_run`, live smoke | n/a (this repo) | none | active | this repository |
| self | [`self-release.yml`](.github/workflows/self-release.yml) | After those checks pass on `main`, cut annotated `v1.x.y` and move floating `v1` | n/a (this repo) | `RELEASE_APP_PRIVATE_KEY` (this repo) | active | this repository |
| security | [`security-scan.yml`](.github/workflows/security-scan.yml) | actionlint, zizmor, gitleaks, dependency review, caller contract | `contents: read`, `pull-requests: read` | none | active | none yet |
| security | [`actions/azure-oidc-login`](actions/azure-oidc-login/README.md) | Azure login via GitHub OIDC; optional Key Vault read | `id-token: write`, `contents: read` | none (OIDC) | active | none in this repo |
| config | — | Shared config reader | — | — | not built until two callers exist | — |
| release | — | Shared consumer release-version workflow | — | — | not built until two callers exist | — |
| lib | — | Shared lib verify/publish | — | — | not built until two callers exist | — |
| app | [`actions/setup-pnpm-node`](actions/setup-pnpm-node/README.md) | pnpm from `packageManager`, Node from `.nvmrc` or docs default | none | none | active | none yet |
| app | — | Shared app verify/image | — | — | not built until two callers exist | — |
| deploy | — | Shared deploy spool (Pages deploy is under pages) | — | — | not built until two callers exist | — |
| db | — | Shared db workflows | — | — | not built until two callers exist | — |
| infra | — | Shared infra workflows | — | — | not built until two callers exist | — |

Org starters (copied into a new repo from the workflow template picker):

- [`workflow-templates/pages-production.yml`](workflow-templates/pages-production.yml) — production
- [`workflow-templates/pages-preview.yml`](workflow-templates/pages-preview.yml) — PR preview + cleanup

Visual-review, sticky preview comments, and extra Playwright jobs stay in the
caller.

## Key Vault access (ADR-012)

Any workflow or action that reads Key Vault must use
[`actions/azure-oidc-login`](actions/azure-oidc-login/README.md) (GitHub OIDC
via `azure/login`). OIDC only: no client secret, log secret names never
values. Ordinary CI stays on `ubuntu-latest`, not the Oracle self-hosted
runner.

## Inputs and secrets

### `pages-build.yml`

No secrets. Reads `vars.PUBLIC_LEAD_INTAKE_ENABLED`,
`vars.PUBLIC_TURNSTILE_SITE_KEY`, and `vars.PUBLIC_LEADS_API_URL` from the
caller unless overridden.

| Input | Default | Notes |
| --- | --- | --- |
| `node_version` | `24` | |
| `working_directory` | `.` | Site package directory relative to the repository root |
| `dist_path` | `dist` | Relative to `working_directory` |
| `turnstile_policy` | `when-lead-intake-enabled` | `always` requires the public Turnstile site key on every build |
| `preview_base_path` | `""` | Set on preview builds (for example `/pr-preview/pr-12/`) |
| `run_a11y` | `true` | |
| `artifact_name` | `pages-dist` | Use `preview-dist` on preview jobs |
| `public_turnstile_site_key` | `""` | Public site key only. Preview callers may pass the Cloudflare dummy key |
| `public_lead_intake_enabled` | `""` | |
| `public_leads_api_url` | `""` | |

### `pages-deploy.yml`

| Input | Default | Notes |
| --- | --- | --- |
| `mode` | required | `production` or `preview` |
| `working_directory` | `.` | Site package directory relative to the repository root |
| `dist_path` | `dist` | Relative to `working_directory` |
| `preview_umbrella` | `pr-preview` | Also used as JamesIves `clean-exclude` so production does not wipe previews |
| `repository` | caller repo name | App token allow-list (name without owner) |
| `artifact_name` | `pages-dist` | Skip download when `preview_action` is `remove` |
| `pages_base_url` | `""` | Required when `mode` is `preview` |
| `preview_action` | `deploy` | `deploy` or `remove` |
| `dry_run` | `false` | Skip minting a token and pushing `gh-pages` |

| Secret | Required | Notes |
| --- | --- | --- |
| `RELEASE_APP_PRIVATE_KEY` | unless `dry_run` | Passed by the caller. App ID is `vars.RELEASE_APP_ID` |

The App token is minted as the last setup step and is the only credential
used to push `gh-pages`. Jobs never use `GITHUB_TOKEN` for deploy.

### `security-scan.yml`

No secrets. Callers pin `@v1`. See [`docs/security.md`](docs/security.md).

| Input | Default | Notes |
| --- | --- | --- |
| `working_directory` | `.` | Directory that holds `.github/workflows` |
| `dependency_review` | `auto` | Public `pull_request` only when `auto`; private repos skip |
| `enforce_banned_steps` | `true` | Fail enforced entries in `scripts/banned-steps.json` |
| `fail_on_findings` | `true` | Fail the job on enforced scanner findings |

```yaml
jobs:
  security:
    uses: singleton-sd/.github/.github/workflows/security-scan.yml@v1
    permissions:
      contents: read
      pull-requests: read
```

### `pages-smoke.yml`

No secrets. The smoke job checks out `${{ job.workflow_repository }}` at
`${{ job.workflow_sha }}` so the script matches the reusable workflow commit
the caller pinned. It does not hard-code `v1`.

| Input | Default | Notes |
| --- | --- | --- |
| `url` | required | Live production or preview URL |
| `expect_title` | `""` | Pass title and/or `expect_root` so a cached Pages 404 cannot pass |
| `expect_root` | `""` | |
| `timeout_ms` | `300000` | Retry budget for CDN propagation |

## Caller shape

Production (`pages.yml`):

```yaml
jobs:
  build:
    uses: singleton-sd/.github/.github/workflows/pages-build.yml@v1
    permissions:
      contents: read
    with:
      turnstile_policy: when-lead-intake-enabled
      artifact_name: pages-dist

  deploy:
    needs: build
    uses: singleton-sd/.github/.github/workflows/pages-deploy.yml@v1
    permissions:
      contents: read
      actions: read
    with:
      mode: production
      repository: ${{ github.event.repository.name }}
    secrets:
      RELEASE_APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

  smoke:
    needs: deploy
    uses: singleton-sd/.github/.github/workflows/pages-smoke.yml@v1
    with:
      url: https://example.singletonsd.com/
      expect_title: Example
```

Preview jobs also pass `preview_base_path`, `artifact_name: preview-dist`,
`mode: preview`, `pages_base_url`, and `preview_action: deploy` (or `remove`
on `pull_request` closed). Nested site packages pass `working_directory`.

## `.nojekyll`

GitHub Pages runs Jekyll over `gh-pages`. Without a root `.nojekyll`, paths
under `/_astro/` 404 as `text/html` and the live page renders unstyled. Both
build and deploy write `dist/.nojekyll` and fail if it is missing. The
artifact upload sets `include-hidden-files: true`.
