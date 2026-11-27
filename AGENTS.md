# AGENTS.md

Shared GitHub Actions workflows and org workflow templates for Singleton SD marketing sites.

- Callers must pin reusable workflows at `@v1`, never `@main`.
- Do not store secrets in this repository. Callers pass secrets through the
  `secrets:` map on `workflow_call` (currently `RELEASE_APP_PRIVATE_KEY`).
- The singleton-release App ID is read from the caller's `vars.RELEASE_APP_ID`.
- Do not add consumer-repo changes or an App Configuration reader unless that
  is the PR's stated goal.
