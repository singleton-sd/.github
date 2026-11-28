# Proposing a change

Open a pull request against `main` in this repository. Keep it to one concern.
Do not change consumer repositories from here.

## New shared area

A new reusable workflow or composite action belongs in its area under
`docs/<area>.md`. Reserved areas stay stubs until **two callers** exist.
Do not add `config`, `lib`, `app`, `deploy` (beyond Pages), `db`, or `infra`
workflows until that bar is met.

## Contract

Follow [`docs/contract.md`](contract.md):

- Typed, described inputs with defaults, plus `working_directory` when the
  workflow checks out the caller.
- Explicit secrets; never `secrets: inherit`.
- `permissions: {}` at the top; minimal permissions per job.
- SHA-pin third-party actions with a `# vX.Y.Z` comment and refresh
  `.github/workflows/actions.lock` (`node scripts/lint-contract.mjs --write-lock`).
- Job summary with workflow ref and SHA.
- A `self-test.yml` caller on the local `./` path; `dry_run` for deploy-type
  workflows.
- Inputs through `env:`, never interpolated into `run:`.
- Concurrency groups that do not use `github.workflow`.

Example callers in docs pin `singleton-sd/.github/...@v1`. Only `self-test.yml`
uses `./.github/workflows/<file>.yml`.

## This repository's own CI

Required check names are `self-ci` and `self-test`. Releases are cut by
`self-release` after those checks are green on `main`. See
[`docs/versioning.md`](versioning.md).

## Org-wide files

Do not add community health files (for example `CODEOWNERS` at the org
`.github` root beyond this repo's own workflows, `SECURITY.md` as an org
default, or `profile/README.md`) without the owner's approval. Files in an
organization `.github` repository can apply org-wide.
