# Self

This repository's own CI and release. Required check **job names** are
`self-ci` and `self-test`.

| Workflow | Role |
| --- | --- |
| [`self-ci.yml`](../.github/workflows/self-ci.yml) | actionlint (with shellcheck), shellcheck on `scripts/**/*.sh` and `actions/**/*.sh`, policy tests, `node --test`, contract lint, `actions.lock` verify, zizmor |
| [`self-test.yml`](../.github/workflows/self-test.yml) | Calls Pages reusable workflows via `./.github/workflows/<file>.yml` against the fixture and production smoke URL; App Configuration composite tests use recorded `az` JSON (no Azure), including a caller-style side-path checkout |
| [`self-release.yml`](../.github/workflows/self-release.yml) | After both checks are green on `main`, cut annotated `v1.x.y` and move floating `v1` |

See [`docs/versioning.md`](versioning.md) for the tagging rules.
Do not create, move, or delete tags by hand.
