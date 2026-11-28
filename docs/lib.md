# Lib

Shared lib verify/publish workflows are not built until two callers exist.
`lib-publish.yml` stays for GitHub Packages only until the Trusted Publishing
spike result table below says otherwise.

Kits that publish to npmjs keep their existing `release.yml` filename. That
filename is the registered Trusted Publisher; do not rename it.

## npm-publish composite

Call [`actions/npm-publish`](../actions/npm-publish/README.md) from **inside**
the kit's existing `release.yml` job (pin `@v1`). The action packs one tarball
and publishes with `--provenance` on npmjs. It does not run `npm install`. The
caller builds first.

## Trusted Publishing spike

This spike is **not run in this repository** and must **not** use a throwaway
npm package. It is exercised later on the first CI publish of the public
package `@singleton-sd/analytics-kit`.

How to run it (later, on that kit):

1. Register Trusted Publishing on `@singleton-sd/analytics-kit` against its
   existing `release.yml` filename. Do not rename that file.
2. If `actions/npm-publish` has shipped (`@v1` on this repository), call it
   from inside that `release.yml` job.
3. If it has not shipped, use an inline `npm publish --provenance` step in
   the same `release.yml` file. Do not set `registry-url` on `setup-node`.
4. Record whether npm accepted the publish, using one of: composite in the
   caller's `release.yml` / inline step / neither.

Until that result is recorded, any shared `lib-publish` workflow stays for
GitHub Packages only.

### Result

| Date | Package | Workflow file | Method | npm accepted | Notes |
| --- | --- | --- | --- | --- | --- |
| — | `@singleton-sd/analytics-kit` | `release.yml` | not yet run | — | A later human records the result here. |
