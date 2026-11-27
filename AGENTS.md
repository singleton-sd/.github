# AGENTS.md

Shared GitHub Actions workflows and org workflow templates for Singleton SD marketing sites.

Naming follows ADR-011 (Singleton SD reusable workflow naming).

- Callers must pin reusable workflows at `@v1`, never `@main`.
- Reusable Pages workflows are `pages-build.yml`, `pages-deploy.yml`, and
  `pages-smoke.yml`. Org starters are `pages-production.yml` and
  `pages-preview.yml`. This repo's required checks are `self-ci` and `self-test`.
- Do not store secrets in this repository. Callers pass secrets through the
  `secrets:` map on `workflow_call` (currently `RELEASE_APP_PRIVATE_KEY`).
- The singleton-release App ID is read from the caller's `vars.RELEASE_APP_ID`.
- Do not add consumer-repo changes or an App Configuration reader unless that
  is the PR's stated goal.
