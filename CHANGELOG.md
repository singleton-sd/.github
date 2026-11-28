# Changelog

Hand-maintained. The `self-release` job does not rewrite or commit this file.

## Unreleased

- Added `actions/app-config-read`, reusable `config-read.yml`, and
  `pages-build-app-config.yml` for public Azure App Configuration reads.
  `pages-build.yml` stays `contents: read` only (existing `@v1` callers need
  no permission change). App Configuration builds call
  `pages-build-app-config.yml` with `id-token: write`. Reusable workflows
  check out this repo at `job.workflow_sha` into `.github-workflows-src`
  because `./actions/...` resolves against the caller workspace. Nested
  login is SHA-pinned `singleton-sd/.github/actions/azure-oidc-login`.
- Documented the shared workflow contract, area docs, contract lint, `self-test`
  fixture calls, `actions.lock`, and Dependabot.
- Renamed the release workflow to `self-release`.

Releases are annotated `v1.x.y` tags with a floating `v1`. See
[`docs/versioning.md`](docs/versioning.md).
