# npm-publish

Composite action that a kit runs **inside its own `release.yml` job**. npmjs
Trusted Publishing is bound to one repository and one workflow filename; this
action must not become a separate reusable workflow, and callers must not
rename that `release.yml`.

It packs exactly one tarball, then `npm publish` with `--provenance` (on the
public npm registry), `--ignore-scripts`, an idempotency check, and a job
summary.

The **caller builds before calling**. This action does not run `npm install`
and does not run lifecycle scripts (`--ignore-scripts` on pack and publish).

There is **no token input**. The action fails if `NODE_AUTH_TOKEN` or
`NPM_TOKEN` is set. There is **no `registry-url` input** and the action never
calls `actions/setup-node` (setting `registry-url` there writes `always-auth`
and an empty `_authToken`, which breaks the Trusted Publishing OIDC path).

The caller job needs `permissions: id-token: write`.

## Caller example

Keep the existing `release.yml` filename. Pin `@v1` (or an immutable
`@v1.x.y`). Only this repository's `self-test.yml` uses the local
`./actions/npm-publish` path.

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Set up pnpm and Node
        uses: singleton-sd/.github/actions/setup-pnpm-node@v1

      - name: Build
        run: pnpm build

      - name: Publish to npmjs
        uses: singleton-sd/.github/actions/npm-publish@v1
```

Do not set `registry-url` on `setup-node` in that job.

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `working_directory` | no | `.` | Directory relative to the repository root |
| `package_dir` | no | `.` | Package directory relative to `working_directory` |
| `access` | no | `public` | `public` or `restricted` |
| `tag` | no | `latest` | npm dist-tag |
| `dry_run` | no | `false` | Adds `--dry-run` and still prints the tarball file list |
| `registry_check` | no | `true` | If `name@version` already exists, skip and set `published=false` |

## Outputs

| Output | Notes |
| --- | --- |
| `published` | `true` only when this run published a new version |
| `version` | Version from `package.json` |
| `tarball` | Packed filename; empty when the version was already published |

## Job summary

The job summary records:

- package name and version
- tarball filename and sha512 integrity
- published yes/no (and `skipped: already published` when the version exists)
- `github.action_ref` and `github.action_path` (the `.github` ref)
- `github.workflow_ref` and `github.sha`

When the caller uses a local `./` path, `github.action_ref` may be empty; the
summary then still records `github.action_path` and `github.sha`.

## Provenance and local registries

`--provenance` is passed when the configured npm registry is
`registry.npmjs.org`. npm rejects provenance on other hosts (including a
local Verdaccio). This repository's self-test publishes a fixture twice to
localhost Verdaccio without provenance (npm CLI still logs into that local
registry via a runtime userconfig; `NODE_AUTH_TOKEN` / `NPM_TOKEN` stay
unset), and asserts `--provenance` is on the Trusted Publishing command used
for npmjs. It never publishes to npmjs.com or GitHub Packages.
