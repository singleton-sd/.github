# Security

[`actions/azure-oidc-login`](../actions/azure-oidc-login/README.md) logs in to
Azure with GitHub OIDC (`azure/login`) and optionally reads Key Vault secrets.
OIDC only: no client secret, log secret names never values. Ordinary CI stays
on `ubuntu-latest`, not the Oracle self-hosted runner.

Callers that read Key Vault must use this action. A live Azure login is not
exercised in this repository.

## `security-scan.yml`

Reusable workflow any singleton-sd repo calls from its `ci.yml`. It is the
enforcement point for the shared-CI contract (org rulesets cannot force it on
private repos on GitHub Free).

Callers pin `@v1` (or an immutable `@v1.x.y`), never `@main`. Only this
repository's `self-test.yml` uses the local `./` path.

```yaml
jobs:
  security:
    uses: singleton-sd/.github/.github/workflows/security-scan.yml@v1
    permissions:
      contents: read
      pull-requests: read
```

No secrets. Top-level `permissions: {}`; the scan job uses `contents: read`
and `pull-requests: read` (dependency review).

| Input | Default | Notes |
| --- | --- | --- |
| `working_directory` | `.` | Directory that holds `.github/workflows` (and `workflow-templates` if present) |
| `dependency_review` | `auto` | `auto` runs only when the caller is public and the event is `pull_request`. `true` / `false` force on or off. Private repos always skip |
| `enforce_banned_steps` | `true` | Fail on `scripts/banned-steps.json` entries with `enforce: true` |
| `fail_on_findings` | `true` | Fail the job when a scanner reports enforced findings |

The workflow checks out the **caller**, then checks out this repository at
`${{ job.workflow_sha }}` into `.github-workflows-src` only for the contract
script. Scanner binaries are downloaded at a pinned version and checksum
verified (actionlint 1.7.12, zizmor 1.33.1, gitleaks 8.30.1). It does not use
`gitleaks/gitleaks-action`.

### What runs

| Scanner | Target | Fail | Warn |
| --- | --- | --- | --- |
| **actionlint** | Caller `.github/workflows` and `workflow-templates` | Any actionlint error | — |
| **zizmor** | Same paths, offline, regular persona | High-severity audits, including `unpinned-uses` (third-party `uses:` must be a 40-hex SHA; `singleton-sd/*` may be `@v1` / `@v1.x.y`) | Medium, low, and informational findings |
| **gitleaks** | PR diff (`base..head`) or push range of the **caller** repo | Any finding | — |
| **dependency review** | Public `pull_request` only (`actions/dependency-review-action`) | High or worse, when the step runs | Skip line `skipped: private repo` on private callers |
| **caller contract** | Caller workflow files via `scripts/check-caller-contract.mjs` | Tag/branch-pinned third-party actions, `secrets: inherit`, banned steps with `enforce: true` | Banned steps with `enforce: false` |

Gitleaks runs with `--redact`. The job never uploads a findings report and
never writes secret values or matched content to the summary or logs. The
summary lists **counts and rule names only**.

Banned inline copies live in [`scripts/banned-steps.json`](../scripts/banned-steps.json).
Each entry has a `replacement` and `enforce` flag. Only inline `azure/login`
is enforced today (use [`actions/azure-oidc-login`](../actions/azure-oidc-login/README.md)).
GitHub App token mint, release commit-back, and spool-deploy warn until those
shared replacements ship; `flip_when` on each entry says which follow-up flips
the flag.

### How to read the summary

The job summary always includes `workflow_ref`, the caller `sha`, and
`workflow_sha`, then one line per scanner:

```
- **actionlint**: pass (count 0; rules: none)
- **zizmor**: fail (count 2; rules: unpinned-uses)
- **gitleaks**: pass (count 0; rules: none)
- **dependency-review**: skip (count 0; skipped: private repo)
- **caller-contract**: fail (count 1; rules: secrets-inherit)
```

`fail` with `fail_on_findings: true` (the default) fails the job. `warn` does
not. `skip` is not a failure.

### Exceptions

Do not weaken a scanner in a caller to silence a finding. Open a pull request
against this repository as described in [`docs/proposing.md`](proposing.md):
one concern, SHA-pinned actions, and a `self-test` fixture that proves the
change. Typical exception shapes:

- Add a `flip_when` follow-up and keep `enforce: false` until the shared
  replacement exists (already the case for three banned steps).
- Tighten or document a zizmor policy in this workflow, with a test.
- Callers may set `fail_on_findings: false` only as a temporary rollout
  switch; that is not an exception to the contract.
