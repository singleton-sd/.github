# Versions

One pnpm and Node policy for callers of `actions/setup-pnpm-node`.

default-node: 24

A repo changes versions through `package.json#packageManager` or `.nvmrc`,
never in a workflow.

- **pnpm** comes from the caller's `package.json` `packageManager` field
  (`pnpm@<semver>`, optional `+sha512` hash). `actions/setup-pnpm-node` has no
  `version` input and does not accept a pnpm or Node override.
- **Node** comes from the caller's `.nvmrc` (or the `node_version_file` input).
  If that file is missing, the action uses the default Node major on the
  `default-node:` line above (24 today).

The `default-node: <major>` line is machine-readable. Keep exactly one such
line so the action can parse it.
