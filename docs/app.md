# App

Shared app verify/image workflows are not built until two callers exist.

## setup-pnpm-node

Composite action that installs pnpm from `package.json#packageManager` and
Node from `.nvmrc` (or the default in [`docs/versions.md`](versions.md)).
Callers pin `@v1`. There is no `version` input and no other override.

### Inputs

| Input | Default | Notes |
| --- | --- | --- |
| `working_directory` | `.` | Package directory relative to the repository root |
| `cache` | `true` | pnpm store cache via `actions/setup-node` |
| `node_version_file` | `.nvmrc` | Relative to `working_directory` |
| `version` | empty | Forbidden. The action fails if this is set |

### Caller example

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
