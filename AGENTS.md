# AGENTS.md

Shared GitHub Actions workflows and org workflow templates for Singleton SD marketing sites.

Naming follows ADR-011 (Singleton SD reusable workflow naming).

- Callers must pin reusable workflows at `@v1` (current major) or an immutable
  `@v1.x.y`, never `@main`.
- Do not use `secrets: inherit`. Callers pass secrets through the `secrets:`
  map on `workflow_call`.
- Pin third-party actions by full commit SHA with a `# vX.Y.Z` comment and
  keep [`.github/workflows/actions.lock`](.github/workflows/actions.lock) in
  sync (`node scripts/lint-contract.mjs --write-lock`;
  `gh actions-lock --verify-local`).
- Reusable Pages workflows are `pages-build.yml`, `pages-deploy.yml`, and
  `pages-smoke.yml`. Org starters are `pages-production.yml` and
  `pages-preview.yml`. Reusable security workflow is `security-scan.yml`.
  This repo's required checks are `self-ci` and `self-test`.
- Do not store secrets in this repository. Callers pass secrets through the
  `secrets:` map on `workflow_call` (currently `RELEASE_APP_PRIVATE_KEY`).
- The singleton-release App ID is read from the caller's `vars.RELEASE_APP_ID`.
- Do not add consumer-repo changes or an App Configuration reader unless that
  is the PR's stated goal.
- Any workflow or action that reads Key Vault uses `actions/azure-oidc-login`
  (OIDC), logs secret names only, and never adds `AZURE_CLIENT_SECRET` or
  `AZURE_CREDENTIALS`. Do not move ordinary CI to the Oracle runner.
- Do not add community health files or `profile/` without the owner's
  approval; they become org-wide defaults.
