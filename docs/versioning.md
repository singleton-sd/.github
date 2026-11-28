# Versioning

`v1` is the current major. Callers pin `@v1` for the floating line, or an
immutable `@v1.x.y` to freeze a revision. Do not pin `@main` or any branch.

## How a release is cut

[`.github/workflows/self-release.yml`](../.github/workflows/self-release.yml)
runs after `self-ci` and `self-test` complete on a `push` to `main`, or on
`workflow_dispatch` restricted to `main`. It never runs on `pull_request` or
`pull_request_target`.

Before tagging it confirms both GitHub Actions checks named `self-ci` and
`self-test` are `completed`/`success` for that SHA. If `workflow_run` starts
when only one of those checks has finished, the job exits 0 without tagging.
It fails if either check has failed. `workflow_dispatch` still requires both
checks to be green.

Version tags:

- Latest `v1.x.y` is bumped **patch by default**.
- A `release:minor` label on the merged PR bumps minor and resets patch.
- A `release:major` label fails the job. A v2 line is out of scope.
- If no `v1.x.y` tag exists, the first tag is `v1.0.0`.
- If the commit already has a `v1.x.y` tag, that tag is left alone.

Order: push an annotated immutable `v1.x.y` first (never overwrite a version
tag), then force-update only the annotated floating `v1` to the same commit.
That tag move is the only force operation. `v1` is not moved onto an ancestor
of the current `v1`.

Tags are pushed with a singleton-release GitHub App token
(`vars.RELEASE_APP_ID` or `secrets.RELEASE_APP_ID`, plus
`secrets.RELEASE_APP_PRIVATE_KEY`). `GITHUB_TOKEN` is never used to push tags.
Do not move tags by hand. Do not add release-it or a release commit.

[`CHANGELOG.md`](../CHANGELOG.md) is hand-maintained. The release job does not
rewrite it or commit it.

Concurrency group `release-v1` serializes runs. The job is idempotent when the
commit is already tagged.
