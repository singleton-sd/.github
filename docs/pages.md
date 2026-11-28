# Pages

Reusable marketing GitHub Pages pipeline. Callers pin `@v1`.

| Workflow | Role |
| --- | --- |
| [`pages-build.yml`](../.github/workflows/pages-build.yml) | Install, format, lint, test, Turnstile check, build, SEO/a11y, write `dist/.nojekyll`, upload artifact |
| [`pages-deploy.yml`](../.github/workflows/pages-deploy.yml) | Download artifact, rewrite `.nojekyll`, mint singleton-release App token, deploy production or preview. `dry_run: true` skips the token and push. |
| [`pages-smoke.yml`](../.github/workflows/pages-smoke.yml) | Check out this reusable workflow's own repo and SHA and run [`scripts/smoke-live.mjs`](../scripts/smoke-live.mjs) against the live URL |

Org starters (copied into a new repo from the workflow template picker):

- [`workflow-templates/pages-production.yml`](../workflow-templates/pages-production.yml)
- [`workflow-templates/pages-preview.yml`](../workflow-templates/pages-preview.yml)

Visual-review, sticky preview comments, and extra Playwright jobs stay in the
caller.

`self-test.yml` calls all three workflows through the local `./` path against
[`tests/fixtures/pages-astro/`](../tests/fixtures/pages-astro/) (`pages-deploy`
with `dry_run: true`) and smokes `https://leasemate.singletonsd.com/`.

See the README for inputs, secrets, and caller shape.
