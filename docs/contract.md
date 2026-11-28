# Shared workflow contract

This is the source of truth for reusable workflows and composite actions in
`singleton-sd/.github`. `scripts/lint-contract.mjs` enforces it on every
`self-ci` run.

Callers pin `singleton-sd/.github/.github/workflows/<file>.yml@v1` (or an
immutable `@v1.x.y`). Never pin `@main`. Only this repository's `self-test.yml`
uses the local `./.github/workflows/<file>.yml` path.

## Rules

- **Inputs.** Every `workflow_call` input is typed and described. Optional
  inputs have defaults. Reusable workflows that check out the caller declare
  `working_directory` (default `.`). Composite action inputs are described;
  optional inputs have defaults.
- **Secrets.** Secrets are declared explicitly on `workflow_call`.
  `secrets: inherit` is forbidden. This repository stores no secrets; callers
  pass them through the `secrets:` map.
- **Permissions.** Workflows set `permissions: {}` at the top level and grant
  the minimum per job. Do not use `read-all` or `write-all`. GitHub validates
  nested-job permissions at parse time, so `pages-build.yml` must not request
  `id-token: write` (App Configuration builds use `pages-build-app-config.yml`).
  Org starters that call `pages-build.yml` must not grant `id-token: write`.
- **Third-party actions.** Pin every third-party `uses:` to a full 40-character
  commit SHA with a `# vX.Y.Z` comment. Record the same pin in
  [`.github/workflows/actions.lock`](../.github/workflows/actions.lock).
  `.github/workflows/actions.lock` uses GitHub's v0.0.3 lockfile schema, keyed
  by the SHA pins already in the workflows (callers and this repo keep
  `uses: owner/repo@<sha> # vX.Y.Z`). Each workflow's pin list is unique: the
  same SHA used twice in one file appears once. Generate and verify with:

  ```bash
  node scripts/lint-contract.mjs --write-lock
  node scripts/lint-contract.mjs
  gh actions-lock --verify-local
  ```

  Local `./` references and this repository's own `self-*` workflows are
  expected. `./actions/...` inside a called reusable workflow or composite
  resolves against the **caller** workspace. Reusable workflows that need
  this repository's composites check out `${{ job.workflow_repository }}` at
  `${{ job.workflow_sha }}` into `.github-workflows-src` (see `pages-smoke.yml`).
  Nested login from `actions/app-config-read` is SHA-pinned
  `singleton-sd/.github/actions/azure-oidc-login`.

  Pins used only inside `actions/*/action.yml` (today `azure/login` in
  `actions/azure-oidc-login`) are recorded in `actions.lock` by
  `node scripts/lint-contract.mjs --write-lock`. Dependabot regenerates the
  lock with `gh actions-lock`, which scans workflow files only, so those
  composite-only pins are dropped. `lint-contract` derives a missing
  composite-only pin from the action file and fails only when a lock entry
  for the same action disagrees (SHA or `# vX.Y.Z`). Dependabot also scans
  `/actions/*` so composite pins are bumped in the same grouped PR.
- **Job summary.** Each reusable workflow and composite action writes a job
  summary that includes the workflow ref (`github.workflow_ref`) and SHA
  (`github.sha`).
- **Self-test.** Every reusable workflow has a caller in `self-test.yml` that
  uses the local `./` path. Deploy-type workflows declare `dry_run` (default
  `false`); `self-test` calls them with `dry_run: true`.
- **`run:` steps.** Pass inputs and secrets through `env:`. Never interpolate
  `${{ inputs.* }}` or `${{ secrets.* }}` into a `run:` script.
- **Concurrency.** Groups never include `github.workflow`.

`self-ci`, `self-test`, and `self-release` follow the same pin, permissions,
and `env:` rules. They are not reusable workflows, so they do not take
`working_directory` or `dry_run`.
