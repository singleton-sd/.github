# setup-pnpm-node

Shared composite action that installs **one** pnpm and Node policy:

- pnpm from the caller's `package.json` `packageManager` field
- Node from the caller's `.nvmrc`, or the default in
  [`docs/versions.md`](../../docs/versions.md) when that file is missing

There is **no `version` input** and no other way to override pnpm or Node.
A repo changes versions by editing `package.json` or `.nvmrc`, never a
workflow. The pnpm store cache is on by default.

## Caller example

```yaml
jobs:
  verify:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Set up pnpm and Node
        uses: singleton-sd/.github/actions/setup-pnpm-node@v1
```

Pin `@v1` (or an immutable `@v1.x.y`). Only this repository's `self-test.yml`
uses the local `./actions/setup-pnpm-node` path.

## Inputs

| Input | Required | Default | Notes |
| --- | --- | --- | --- |
| `working_directory` | no | `.` | Package directory relative to the repository root |
| `cache` | no | `true` | pnpm store cache through `actions/setup-node` `cache: pnpm` |
| `node_version_file` | no | `.nvmrc` | Relative to `working_directory`. Used when the file exists |
| `version` | do not set | empty | Forbidden. The action fails if this is set |

## Job summary

The job summary records:

- resolved pnpm version
- resolved Node version and source (`.nvmrc` or the `docs/versions.md` default)
- `github.action_ref` and `github.action_path`
- `github.workflow_ref` and `github.sha`

When the caller uses a local `./` path, `github.action_ref` may be empty; the
summary then still records `github.action_path` and `github.sha`.
