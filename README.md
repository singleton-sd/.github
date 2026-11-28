# .github

Shared GitHub Actions workflows and org workflow templates for Singleton SD
marketing sites (Pages build, deploy, and live smoke checks).

Naming follows ADR-011 (Singleton SD reusable workflow naming).

Callers **must pin `@v1`**, never `@main`. The `v1` tag is cut after the
workflows land on `main`; do not follow a branch.

This repository stores **no secrets**. Callers pass secrets through the
`secrets:` map on `workflow_call`. Public build settings are read from the
**caller's** GitHub repository variables (`vars.*`).

## Pinning

```yaml
jobs:
  build:
    uses: singleton-sd/.github/.github/workflows/pages-build.yml@v1
    permissions:
      contents: read
```

The double `.github` is required: `{owner}/{repo}/.github/workflows/{file}@{ref}`.

## Workflows

| Workflow | Role |
| --- | --- |
| [`pages-build.yml`](.github/workflows/pages-build.yml) | Install, format, lint, test, Turnstile check, build, SEO/a11y, write `dist/.nojekyll`, upload artifact |
| [`pages-deploy.yml`](.github/workflows/pages-deploy.yml) | Download artifact, rewrite `.nojekyll`, mint singleton-release App token, deploy production or preview |
| [`pages-smoke.yml`](.github/workflows/pages-smoke.yml) | Check out this reusable workflow's own repo and SHA and run [`scripts/smoke-live.mjs`](scripts/smoke-live.mjs) against the live URL |
| [`self-ci.yml`](.github/workflows/self-ci.yml) | This repo's required checks `self-ci` (actionlint + Azure OIDC policy + live smoke) and `self-test` (`node --check` and script tests) |

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

| Secret | Required | Notes |
| --- | --- | --- |
| `RELEASE_APP_PRIVATE_KEY` | yes | Passed by the caller. App ID is `vars.RELEASE_APP_ID` |

The App token is minted as the last setup step and is the only credential
used to push `gh-pages`. Jobs never use `GITHUB_TOKEN` for deploy.

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
