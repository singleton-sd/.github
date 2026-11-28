# Changelog

Hand-maintained. The `self-release` job does not rewrite or commit this file.

## Unreleased

- Added `actions/app-config-read`, reusable `config-read.yml`, and a
  `pages-build` `app_config` input for public Azure App Configuration reads.
  `pages-build` callers grant `id-token: write` (GitHub validates nested-job
  permissions even when `app_config` is false).
- Documented the shared workflow contract, area docs, contract lint, `self-test`
  fixture calls, `actions.lock`, and Dependabot.
- Renamed the release workflow to `self-release`.

Releases are annotated `v1.x.y` tags with a floating `v1`. See
[`docs/versioning.md`](docs/versioning.md).
